defmodule Famichat.Auth.Passkeys do
  @moduledoc """
  WebAuthn challenge orchestration: issuance, verification, and
  consumption of passkey registration/assertion challenges.

  Responses include WebAuthn `public_key_options` alongside an opaque challenge
  handle that clients must echo during attestation/assertion.
  """

  use Boundary,
    top_level?: true,
    exports: [],
    deps: [
      Famichat,
      Famichat.Accounts,
      Famichat.Auth.Identity,
      Famichat.Auth.RateLimit,
      Famichat.Auth.Runtime,
      Famichat.Auth.Tokens
    ]

  import Ecto.Query

  alias Famichat.Accounts.{Passkey, User, Username}
  alias Famichat.Auth.Identity
  alias Famichat.Auth.Passkeys.Challenge
  alias Famichat.Auth.Runtime.Instrumentation
  alias Famichat.Auth.RateLimit
  alias Famichat.Auth.Tokens
  alias Famichat.Auth.Tokens.Policy
  alias Famichat.Auth.Tokens.Storage, as: TokenStorage
  alias Famichat.Repo

  require Famichat.Auth.Runtime.Instrumentation
  require Logger

  @challenge_size 32
  @registration_type :registration
  @assertion_type :assertion
  @challenge_salt "webauthn_challenge_v1"

  @doc """
  Returns `true` if the user has at least one active (non-revoked) passkey.

  A passkey is considered active when `disabled_at` is `nil`. This is used
  to gate re-issuance of `passkey_registration` tokens so that users who
  have already enrolled cannot accidentally overwrite their credential.
  """
  @spec has_active_passkey?(Ecto.UUID.t()) :: boolean()
  def has_active_passkey?(user_id) do
    Repo.exists?(
      from p in Passkey,
        where: p.user_id == ^user_id and is_nil(p.disabled_at)
    )
  end

  @doc """
  Disables all active passkeys for the given user. Emits a telemetry event
  when any passkeys are disabled.
  """
  @spec disable_all_for_user(Ecto.UUID.t()) :: :ok
  def disable_all_for_user(user_id) do
    query =
      from p in Passkey,
        where: p.user_id == ^user_id and is_nil(p.disabled_at)

    {count, _} =
      Repo.update_all(query, set: [disabled_at: DateTime.utc_now()])

    if count > 0 do
      emit_passkey_event(:disabled_all, %{user_id: user_id, count: count})
    end

    :ok
  end

  @doc """
  Disables passkeys for each user in the provided list.
  """
  @spec disable_all_for_users([Ecto.UUID.t()]) :: :ok
  def disable_all_for_users(user_ids) when is_list(user_ids) do
    Enum.each(user_ids, &disable_all_for_user/1)
    :ok
  end

  @doc """
  Issues a registration challenge for the provided user.
  """
  @spec issue_registration_challenge(User.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def issue_registration_challenge(%User{} = user, opts \\ []) do
    do_issue(@registration_type, user, opts)
  end

  @doc """
  Issues an assertion challenge based on a flexible identifier (user id,
  username, or email). When the identifier map is empty (no username/email),
  issues a discoverable credential challenge for resident keys.
  """
  @spec issue_assertion_challenge(map() | String.t()) ::
          {:ok, map()} | {:error, term()}
  def issue_assertion_challenge(identifier)
      when is_map(identifier) and not is_struct(identifier) do
    if discoverable_request?(identifier) do
      issue_discoverable_assertion_challenge()
    else
      do_issue_assertion_for_identifier(identifier)
    end
  end

  def issue_assertion_challenge(identifier) when is_binary(identifier) do
    do_issue_assertion_for_identifier(identifier)
  end

  # An empty map or a map with no username/email/identifier keys is a
  # discoverable credential request (the authenticator identifies the user).
  defp discoverable_request?(params) when is_map(params) do
    not (Map.has_key?(params, "username") or
           Map.has_key?(params, "email") or
           Map.has_key?(params, "identifier"))
  end

  @doc """
  Issues a discoverable assertion challenge (no user binding).

  The authenticator picks the credential from its resident key store, so the
  server does not need to know who is logging in ahead of time. The returned
  `allowCredentials` list is empty per the WebAuthn spec for discoverable flow.
  """
  @spec issue_discoverable_assertion_challenge() ::
          {:ok, map()} | {:error, term()}
  def issue_discoverable_assertion_challenge do
    ttl = ttl_for(@assertion_type)

    Instrumentation.span(
      [:famichat, :auth, :passkeys, :issue],
      %{user_id: nil, type: @assertion_type},
      do: persist_discoverable_challenge(ttl)
    )
  end

  defp persist_discoverable_challenge(ttl) do
    challenge_bytes = :crypto.strong_rand_bytes(@challenge_size)
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)

    attrs = %{
      type: @assertion_type,
      challenge: challenge_bytes,
      expires_at: expires_at
    }

    case Repo.insert(Challenge.discoverable_changeset(%Challenge{}, attrs)) do
      {:ok, record} ->
        handle = sign_handle(record, ttl)
        challenge_b64 = Base.url_encode64(challenge_bytes, padding: false)

        options = %{
          "challenge" => challenge_b64,
          "rpId" => rp_id(),
          "timeout" => 60_000,
          "allowCredentials" => [],
          "userVerification" => "required"
        }

        emit_challenge_event(:issued, %{
          type: @assertion_type,
          user_id: nil,
          challenge_id: record.id
        })

        {:ok,
         %{
           "challenge" => challenge_b64,
           "challenge_handle" => handle,
           "expires_at" => expires_at,
           "public_key_options" => options
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_issue_assertion_for_identifier(identifier) do
    # Reject any map that supplies only `user_id` and no accepted public lookup
    # key. The unauthenticated assert-challenge endpoint must not accept UUID
    # lookups: a nonexistent UUID returns a different path through Identity than
    # a missing identifier, enabling user-ID enumeration. Only `username` (or
    # `email` as a fallback) are valid for unauthenticated challenges.
    with :ok <- reject_user_id_only(identifier) do
      normalized = normalize_identifier(identifier)
      key = passkey_identifier_key(normalized)

      with :ok <-
             RateLimit.check(:"passkey.assertion", key, limit: 10, interval: 60),
           {:ok, user} <- Identity.resolve_user(reject_user_id_key(normalized)),
           {:ok, challenge} <- issue_assertion_challenge(user, []) do
        {:ok, challenge}
      else
        {:error, {:rate_limited, retry}} -> {:error, {:rate_limited, retry}}
        other -> other
      end
    end
  end

  defp normalize_identifier(params) when is_map(params) do
    case Map.pop(params, "identifier") do
      {nil, params} -> params
      {value, params} -> Map.put(params, "username", value)
    end
  end

  defp normalize_identifier(params), do: params

  # Returns {:error, :invalid_identifier} when the map supplies `user_id` but
  # no `username` or `email`. A binary identifier (raw string) is always allowed.
  defp reject_user_id_only(identifier) when is_map(identifier) do
    has_user_id = Map.has_key?(identifier, "user_id")

    has_public_key =
      Map.has_key?(identifier, "username") or Map.has_key?(identifier, "email")

    if has_user_id and not has_public_key do
      {:error, :invalid_identifier}
    else
      :ok
    end
  end

  defp reject_user_id_only(_identifier), do: :ok

  # Strips the `user_id` key from a map before forwarding to Identity.resolve_user/1
  # so that even a map containing both `user_id` and `username` cannot trigger
  # the user_id lookup path in Identity.resolve_user/1.
  defp reject_user_id_key(identifier) when is_map(identifier),
    do: Map.delete(identifier, "user_id")

  defp reject_user_id_key(identifier), do: identifier

  @doc """
  Issues an assertion (authentication) challenge for the provided user.
  """
  @spec issue_assertion_challenge(User.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def issue_assertion_challenge(%User{} = user, opts \\ []) do
    do_issue(@assertion_type, user, opts)
  end

  @doc """
  Fetches (without consuming) a previously issued registration challenge
  using the opaque handle returned to the client.
  """
  @spec fetch_registration_challenge(String.t()) ::
          {:ok, Challenge.t()} | {:error, term()}
  def fetch_registration_challenge(handle) when is_binary(handle) do
    fetch_by_handle(@registration_type, handle)
  end

  @doc """
  Fetches (without consuming) a previously issued assertion challenge.
  """
  @spec fetch_assertion_challenge(String.t()) ::
          {:ok, Challenge.t()} | {:error, term()}
  def fetch_assertion_challenge(handle) when is_binary(handle) do
    fetch_by_handle(@assertion_type, handle)
  end

  @doc """
  Marks a challenge as consumed. Returns `{:error, :already_used}` if the
  handle has already been redeemed.
  """
  @spec consume_challenge(Challenge.t()) ::
          {:ok, Challenge.t()} | {:error, term()}
  def consume_challenge(%Challenge{id: id} = challenge) do
    now = DateTime.utc_now()

    {count, _} =
      from(c in Challenge,
        where: c.id == ^id and is_nil(c.consumed_at)
      )
      |> Repo.update_all(set: [consumed_at: now])

    if count == 1 do
      emit_challenge_event(:consumed, %{
        challenge_id: challenge.id,
        user_id: challenge.user_id
      })

      {:ok, %{challenge | consumed_at: now}}
    else
      {:error, :already_used}
    end
  end

  ## Registration & assertion flows ----------------------------------------

  @doc """
  Exchanges a registration token for the associated user.
  """
  @spec exchange_registration_token(String.t()) ::
          {:ok, User.t()} | {:error, term()}
  def exchange_registration_token(raw_token) when is_binary(raw_token) do
    with {:ok, token} <- Tokens.fetch(:passkey_registration, raw_token),
         {:ok, user} <- Identity.fetch_user(token.payload["user_id"]),
         {:ok, _} <- Tokens.consume(token) do
      {:ok, user}
    end
  end

  @doc """
  Registers a new passkey using the attestation payload from the client.

  Expects the payload to contain:
  - `attestation_object`: base64-encoded attestation object from the WebAuthn API
  - `client_data_json`: base64-encoded client data JSON from the WebAuthn API
  - `credential_id`: base64-encoded credential ID
  - `challenge_handle`: the opaque handle from the registration challenge issuance

  Calls `Wax.register/3` to perform full cryptographic attestation verification.
  """
  @spec register_passkey(map()) ::
          {:ok, Passkey.t()} | {:error, term()}
  def register_passkey(attestation_payload) when is_map(attestation_payload) do
    with {:ok, challenge_ctx} <-
           resolve_registration_challenge(attestation_payload),
         {:ok, user} <- Identity.fetch_user(challenge_ctx.user_id),
         {:ok, attestation_object_cbor} <-
           decode_base64(
             attestation_payload,
             ["attestation_object", :attestation_object]
           ),
         {:ok, client_data_json_raw} <-
           decode_base64(
             attestation_payload,
             ["client_data_json", :client_data_json]
           ),
         {:ok, credential_id} <-
           decode_base64(
             attestation_payload,
             ["credential_id", :credential_id]
           ),
         wax_challenge <- build_registration_challenge(challenge_ctx),
         {:ok, {auth_data, _attestation_result}} <-
           safe_wax_register(
             attestation_object_cbor,
             client_data_json_raw,
             wax_challenge
           ),
         :ok <- check_user_verified(auth_data) do
      cose_key = auth_data.attested_credential_data.credential_public_key
      sign_count = auth_data.sign_count

      aaguid =
        case Wax.AuthenticatorData.get_aaguid(auth_data) do
          nil -> nil
          aaguid_bin -> aaguid_bin
        end

      public_key_bin = encode_cose_key_json(cose_key)

      attrs = %{
        user_id: user.id,
        credential_id: credential_id,
        public_key: public_key_bin,
        sign_count: sign_count,
        aaguid: aaguid,
        label:
          Map.get(attestation_payload, "label") ||
            Map.get(attestation_payload, :label),
        last_used_at: DateTime.utc_now()
      }

      case Repo.insert(Passkey.changeset(%Passkey{}, attrs)) do
        {:ok, passkey} ->
          with {:ok, _user} <- maybe_activate_pending_user(user),
               :ok <- finalize_registration_challenge(challenge_ctx) do
            emit_passkey_event(:register, %{user_id: user.id})
            _ = Identity.sync_enrollment_requirement(user)
            {:ok, passkey}
          end

        error ->
          error
      end
    end
  end

  # If the user is in :pending status (created during complete_registration but
  # passkey registration was not yet completed), activate them now that a
  # credential has been successfully verified. This runs inside the same logical
  # execution context as the passkey insert so that a half-completed registration
  # leaves no active credentialless user.
  defp maybe_activate_pending_user(%User{status: :pending} = user) do
    user
    |> User.changeset(%{
      status: :active,
      confirmed_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  defp maybe_activate_pending_user(%User{} = user) do
    # Already active (bootstrap_admin path or future re-enrolment). No-op.
    {:ok, user}
  end

  @doc """
  Verifies an assertion payload, returning the authenticated user + passkey.
  """
  @spec assert_passkey(map()) ::
          {:ok, %{user: User.t(), passkey: Passkey.t()}} | {:error, term()}
  def assert_passkey(payload) when is_map(payload) do
    rate_key = passkey_rate_key(payload)

    case do_assert_passkey(payload) do
      {:ok, _} = ok ->
        ok

      {:error, _reason} = error ->
        case RateLimit.check(:"passkey.assertion", rate_key,
               limit: 5,
               interval: 60
             ) do
          :ok -> error
          {:error, {:rate_limited, retry}} -> {:error, {:rate_limited, retry}}
        end
    end
  end

  defp do_assert_passkey(payload) do
    with {:ok, credential_id} <-
           decode_base64(payload, ["credential_id", :credential_id]),
         {:ok, challenge_ctx} <- resolve_assertion_challenge(payload),
         {:ok, passkey} <- find_active_passkey(credential_id),
         :ok <- maybe_verify_assertion_user(passkey, challenge_ctx.user_id),
         {:ok, cose_key} <- load_cose_key(passkey),
         {:ok, authenticator_data_bin} <-
           decode_base64(
             payload,
             ["authenticator_data", :authenticator_data]
           ),
         {:ok, client_data_json_raw} <-
           decode_base64(
             payload,
             ["client_data_json", :client_data_json]
           ),
         {:ok, signature} <-
           decode_base64(payload, ["signature", :signature]),
         wax_challenge <-
           build_assertion_challenge(challenge_ctx, credential_id, cose_key),
         {:ok, auth_data} <-
           safe_wax_authenticate(
             credential_id,
             authenticator_data_bin,
             signature,
             client_data_json_raw,
             wax_challenge
           ),
         :ok <- check_user_verified(auth_data),
         :ok <- check_sign_count_regression(passkey, auth_data.sign_count),
         {:ok, passkey} <- update_sign_count(passkey, auth_data.sign_count),
         :ok <- finalize_assertion_challenge(challenge_ctx) do
      user = Repo.preload(passkey, :user).user
      emit_passkey_event(:assert, %{user_id: user.id})
      {:ok, %{user: user, passkey: passkey}}
    end
  end

  ## Implementation ---------------------------------------------------------

  # Builds a Wax.Challenge struct for registration using the raw challenge bytes
  # and RP configuration. The challenge bytes are injected directly so Wax does
  # not generate its own — this is necessary because the challenge was already
  # issued and delivered to the client.
  defp build_registration_challenge(%{challenge_binary: challenge_bytes}) do
    cfg = rp_config()
    origin = Keyword.get(cfg, :origin, "http://localhost")
    rp = Keyword.get(cfg, :rp_id, "localhost")

    Wax.new_registration_challenge(
      bytes: challenge_bytes,
      origin: origin,
      rp_id: rp,
      trusted_attestation_types: [
        :none,
        :self,
        :basic,
        :uncertain,
        :attca,
        :anonca
      ],
      verify_trust_root: false
    )
  end

  # Builds a Wax.Challenge struct for assertion using the raw challenge bytes,
  # RP configuration, and the single allowed credential.
  defp build_assertion_challenge(
         %{challenge_binary: challenge_bytes},
         credential_id,
         cose_key
       ) do
    cfg = rp_config()
    origin = Keyword.get(cfg, :origin, "http://localhost")
    rp = Keyword.get(cfg, :rp_id, "localhost")

    Wax.new_authentication_challenge(
      bytes: challenge_bytes,
      origin: origin,
      rp_id: rp,
      allow_credentials: [{credential_id, cose_key}]
    )
  end

  # Checks that the user_verified flag is set in the authenticator data.
  # Returns :ok when UV is true, {:error, :user_verification_required} otherwise.
  # This enforces that the authenticator performed biometric or PIN verification.
  defp check_user_verified(%{flag_user_verified: true}), do: :ok
  defp check_user_verified(_), do: {:error, :user_verification_required}

  # Encodes a COSE key map to a portable JSON binary.
  # COSE keys have integer keys and binary coordinate values; JSON requires string
  # keys and cannot represent raw binaries, so binary values are base64-encoded.
  # This format is stable across Erlang/OTP major versions (unlike term_to_binary).
  defp encode_cose_key_json(cose_key) when is_map(cose_key) do
    cose_key
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      key_str = Integer.to_string(k)
      val = if is_binary(v), do: Base.encode64(v), else: v
      Map.put(acc, key_str, val)
    end)
    |> Jason.encode!()
  end

  # Decodes a COSE key from the portable JSON format produced by encode_cose_key_json/1.
  # String keys are converted back to integers; base64 strings that decode cleanly are
  # treated as binary coordinate values (integers are left as integers).
  defp decode_cose_key_json(json_str) when is_binary(json_str) do
    try do
      cose_key =
        json_str
        |> Jason.decode!()
        |> Enum.reduce(%{}, fn {k, v}, acc ->
          int_key = String.to_integer(k)

          val =
            cond do
              is_binary(v) ->
                case Base.decode64(v) do
                  {:ok, bin} -> bin
                  :error -> v
                end

              true ->
                v
            end

          Map.put(acc, int_key, val)
        end)

      if is_map(cose_key) do
        {:ok, cose_key}
      else
        {:error, :invalid_public_key}
      end
    rescue
      _ -> {:error, :invalid_public_key}
    end
  end

  # Deserializes the stored public key back into a COSE key map.
  # Supports both the new portable JSON format (produced by encode_cose_key_json/1)
  # and the legacy term_to_binary format (for passkeys registered before this fix).
  # Legacy passkeys stored with term_to_binary should be disabled separately since
  # the binary format is not portable across Erlang major versions.
  defp load_cose_key(%Passkey{public_key: pk_bin}) when is_binary(pk_bin) do
    # Detect JSON format: JSON strings begin with '{'
    if String.starts_with?(pk_bin, "{") do
      decode_cose_key_json(pk_bin)
    else
      # Legacy term_to_binary path — attempt to read but log a warning.
      # These passkeys should be disabled and re-enrolled.
      Logger.warning(
        "[Passkeys] Loading passkey stored in legacy term_to_binary format. " <>
          "This passkey should be disabled and re-enrolled for Erlang version portability."
      )

      try do
        cose_key = :erlang.binary_to_term(pk_bin, [:safe])

        if is_map(cose_key) do
          {:ok, cose_key}
        else
          {:error, :invalid_public_key}
        end
      rescue
        _ -> {:error, :invalid_public_key}
      end
    end
  end

  defp load_cose_key(_), do: {:error, :invalid_public_key}

  # Returns :ok when the incoming sign_count is strictly greater than the stored
  # value (or both are zero, which means the authenticator does not implement
  # sign counts), and {:error, :replayed} otherwise.
  defp check_sign_count_regression(%Passkey{sign_count: stored}, incoming) do
    # Per WebAuthn spec §7.2 step 17: if the stored sign_count is 0 and
    # the new sign_count is also 0, the authenticator does not support sign
    # counts, which is allowed. Otherwise the new value must be strictly
    # greater than the stored value.
    cond do
      stored == 0 and incoming == 0 -> :ok
      incoming > stored -> :ok
      true -> {:error, :replayed}
    end
  end

  defp update_sign_count(passkey, new_count) do
    passkey
    |> Passkey.changeset(%{
      sign_count: new_count,
      last_used_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  # Wraps Wax.register/3 to catch exceptions raised by malformed CBOR/binary input.
  # Wax may raise CaseClauseError or similar when the CBOR library encounters
  # unexpected tags in garbage data.
  defp safe_wax_register(
         attestation_object_cbor,
         client_data_json_raw,
         challenge
       ) do
    result =
      Wax.register(attestation_object_cbor, client_data_json_raw, challenge)

    map_wax_error(result)
  rescue
    e ->
      Logger.warning(
        "[Passkeys] Wax.register raised exception for malformed input: #{inspect(e)}"
      )

      {:error, :invalid_attestation_object}
  end

  # Wraps Wax.authenticate/6 to catch exceptions raised by malformed binary input.
  defp safe_wax_authenticate(
         credential_id,
         auth_data_bin,
         signature,
         client_data_json_raw,
         challenge
       ) do
    result =
      Wax.authenticate(
        credential_id,
        auth_data_bin,
        signature,
        client_data_json_raw,
        challenge
      )

    map_wax_error(result)
  rescue
    e ->
      Logger.warning(
        "[Passkeys] Wax.authenticate raised exception for malformed input: #{inspect(e)}"
      )

      {:error, :invalid_authenticator_data}
  end

  # Maps Wax error structs to canonical application error tuples.
  defp map_wax_error({:ok, _} = ok), do: ok

  defp map_wax_error({:error, %Wax.InvalidSignatureError{}}) do
    {:error, :invalid_signature}
  end

  defp map_wax_error(
         {:error, %Wax.InvalidClientDataError{reason: :origin_mismatch}}
       ) do
    {:error, :invalid_origin}
  end

  defp map_wax_error(
         {:error, %Wax.InvalidClientDataError{reason: :challenge_mismatch}}
       ) do
    {:error, :invalid_challenge}
  end

  defp map_wax_error(
         {:error, %Wax.InvalidClientDataError{reason: :rp_id_mismatch}}
       ) do
    {:error, :invalid_rp_id}
  end

  defp map_wax_error(
         {:error, %Wax.InvalidClientDataError{reason: :credential_id_mismatch}}
       ) do
    {:error, :not_found}
  end

  defp map_wax_error({:error, %Wax.ExpiredChallengeError{}}) do
    {:error, :expired}
  end

  defp map_wax_error({:error, _} = err), do: err

  defp do_issue(type, %User{} = user, opts)
       when type in [@registration_type, @assertion_type] do
    ttl = ttl_for(type)

    Instrumentation.span(
      [:famichat, :auth, :passkeys, :issue],
      %{user_id: user.id, type: type},
      do:
        case Repo.transaction(fn ->
               persist_challenge(user, type, ttl, opts)
             end) do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, reason}
        end
    )
  end

  defp ttl_for(@registration_type),
    do: Policy.default_ttl(:passkey_registration)

  defp ttl_for(@assertion_type),
    do: Policy.default_ttl(:passkey_assertion)

  defp persist_challenge(user, type, ttl, opts) do
    challenge_bytes = :crypto.strong_rand_bytes(@challenge_size)
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)

    attrs = %{
      user_id: user.id,
      type: type,
      challenge: challenge_bytes,
      expires_at: expires_at
    }

    case Repo.insert(Challenge.changeset(%Challenge{}, attrs)) do
      {:ok, record} ->
        handle = sign_handle(record, ttl)

        response =
          base_response(
            user,
            type,
            handle,
            challenge_bytes,
            expires_at,
            opts
          )

        emit_challenge_event(:issued, %{
          type: type,
          user_id: user.id,
          challenge_id: record.id
        })

        response

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp base_response(
         user,
         type,
         handle,
         challenge_bytes,
         expires_at,
         opts
       ) do
    challenge_b64 = Base.url_encode64(challenge_bytes, padding: false)

    public_key_options =
      case type do
        @registration_type -> registration_options(user, challenge_b64, opts)
        @assertion_type -> assertion_options(user, challenge_b64, opts)
      end

    %{
      "challenge" => challenge_b64,
      "challenge_handle" => handle,
      "expires_at" => expires_at,
      "public_key_options" => public_key_options
    }
  end

  defp registration_options(user, challenge_b64, _opts) do
    loaded_user = Repo.preload(user, :passkeys)

    exclude =
      Enum.map(loaded_user.passkeys, fn %Passkey{credential_id: cred} ->
        %{
          "type" => "public-key",
          "id" => Base.encode64(cred, padding: false)
        }
      end)

    %{
      "attestation" => "none",
      "authenticatorSelection" => %{
        "residentKey" => "preferred",
        "userVerification" => "required"
      },
      "challenge" => challenge_b64,
      "excludeCredentials" => exclude,
      "pubKeyCredParams" => pubkey_cred_params(),
      "rp" => %{"id" => rp_id(), "name" => rp_name()},
      "timeout" => 120_000,
      "user" => %{
        "id" => encode_user_handle(user.id),
        "name" => user.username || "famichat-user",
        "displayName" => user.username || "Famichat User"
      }
    }
  end

  defp assertion_options(user, challenge_b64, _opts) do
    loaded_user = Repo.preload(user, :passkeys)

    allow_credentials =
      Enum.map(loaded_user.passkeys, fn %Passkey{credential_id: cred} ->
        %{
          "id" => Base.encode64(cred, padding: false),
          "type" => "public-key",
          "transports" => default_transports()
        }
      end)

    %{
      "challenge" => challenge_b64,
      "rpId" => rp_id(),
      "timeout" => 60_000,
      "allowCredentials" => allow_credentials,
      "userVerification" => "required"
    }
  end

  defp pubkey_cred_params do
    [
      %{"type" => "public-key", "alg" => -7},
      %{"type" => "public-key", "alg" => -257}
    ]
  end

  defp default_transports, do: ["platform", "internal", "hybrid"]

  defp encode_user_handle(uuid) when is_binary(uuid) do
    case Ecto.UUID.dump(uuid) do
      {:ok, binary} ->
        Base.encode64(binary, padding: false)

      :error ->
        Logger.warning(
          "[Passkeys] Invalid user UUID for handle: #{inspect(uuid)}"
        )

        raise ArgumentError, "user.id must be a valid UUID"
    end
  end

  defp rp_config do
    Application.get_env(:famichat, :webauthn, [])
  end

  defp rp_id do
    rp_config() |> Keyword.get(:rp_id, "localhost")
  end

  defp rp_name do
    rp_config() |> Keyword.get(:rp_name, "Famichat")
  end

  defp sign_handle(%Challenge{id: id, type: type}, ttl) do
    payload = %{"challenge_id" => id, "type" => Atom.to_string(type)}
    TokenStorage.sign(payload, @challenge_salt, ttl: ttl)
  end

  defp fetch_by_handle(type, handle) do
    ttl = ttl_for(type)

    Instrumentation.span(
      [:famichat, :auth, :passkeys, :fetch],
      %{type: type},
      do: do_fetch_by_handle(type, handle, ttl)
    )
  end

  defp do_fetch_by_handle(type, handle, ttl) do
    result =
      with {:ok, %{"challenge_id" => id, "type" => token_type}} <-
             TokenStorage.verify(handle, @challenge_salt, max_age: ttl),
           true <-
             token_type == Atom.to_string(type) || {:error, :type_mismatch},
           %Challenge{} = challenge <- Repo.get(Challenge, id),
           :ok <- ensure_type(challenge, type),
           :ok <- ensure_fresh(challenge) do
        {:ok, challenge}
      else
        {:error, reason}
        when reason in [
               :expired,
               :invalid,
               :invalid_challenge,
               :type_mismatch,
               :already_used
             ] ->
          emit_challenge_event(:invalid, %{type: type, reason: reason})
          adapt_fetch_error(reason)

        nil ->
          emit_challenge_event(:invalid, %{type: type, reason: :not_found})
          {:error, :invalid_challenge}

        false ->
          emit_challenge_event(:invalid, %{type: type, reason: :type_mismatch})
          {:error, :invalid_challenge}
      end

    result
  end

  defp adapt_fetch_error(:expired), do: {:error, :expired}
  defp adapt_fetch_error(:already_used), do: {:error, :already_used}

  defp adapt_fetch_error(reason)
       when reason in [:invalid, :invalid_challenge, :type_mismatch],
       do: {:error, :invalid_challenge}

  defp emit_challenge_event(kind, metadata) do
    event =
      case kind do
        :issued -> [:famichat, :auth, :passkeys, :challenge_issued]
        :consumed -> [:famichat, :auth, :passkeys, :challenge_consumed]
        :invalid -> [:famichat, :auth, :passkeys, :challenge_invalid]
      end

    :telemetry.execute(event, %{count: 1}, metadata)
  end

  defp ensure_type(%Challenge{type: type}, type), do: :ok
  defp ensure_type(_challenge, _type), do: {:error, :invalid_challenge}

  defp ensure_fresh(%Challenge{expires_at: expires_at, consumed_at: nil}) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
      :ok
    else
      {:error, :expired}
    end
  end

  defp ensure_fresh(%Challenge{consumed_at: %DateTime{}}),
    do: {:error, :already_used}

  defp resolve_registration_challenge(payload) do
    with {:ok, handle} <-
           fetch_binary_param(payload, ["challenge_handle", :challenge_handle]),
         {:ok, challenge} <- fetch_registration_challenge(handle) do
      {:ok, challenge_context(challenge)}
    end
  end

  defp resolve_assertion_challenge(payload) do
    with {:ok, handle} <-
           fetch_binary_param(payload, ["challenge_handle", :challenge_handle]),
         {:ok, challenge} <- fetch_assertion_challenge(handle) do
      {:ok, challenge_context(challenge)}
    end
  end

  defp challenge_context(%Challenge{} = challenge) do
    binary = challenge.challenge

    %{
      record: challenge,
      user_id: challenge.user_id,
      challenge_binary: binary,
      challenge_b64: Base.url_encode64(binary, padding: false)
    }
  end

  defp finalize_registration_challenge(%{record: record}) do
    case consume_challenge(record) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp finalize_assertion_challenge(%{record: record}) do
    case consume_challenge(record) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Discoverable flow: challenge has no user_id — credential identifies the user.
  defp maybe_verify_assertion_user(_passkey, nil), do: :ok

  defp maybe_verify_assertion_user(passkey, user_id),
    do: verify_assertion_user(passkey, user_id)

  defp verify_assertion_user(%Passkey{user_id: user_id}, user_id), do: :ok
  defp verify_assertion_user(_passkey, _), do: {:error, :invalid_credentials}

  defp fetch_binary_param(payload, keys) do
    case first_binary(payload, keys) do
      nil -> {:error, :invalid_challenge}
      value -> {:ok, value}
    end
  end

  defp first_binary(map, keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.get(map, key) do
        value when is_binary(value) ->
          value |> String.trim() |> continue_or_halt()

        _ ->
          {:cont, nil}
      end
    end)
  end

  defp continue_or_halt(""), do: {:cont, nil}
  defp continue_or_halt(trimmed), do: {:halt, trimmed}

  defp passkey_rate_key(payload) do
    Map.get(payload, "device_id") ||
      Map.get(payload, :device_id) ||
      Map.get(payload, "credential_id") ||
      "unknown_device"
  end

  defp passkey_identifier_key(%{"user_id" => user_id})
       when is_binary(user_id),
       do: "user:" <> user_id

  defp passkey_identifier_key(%{"username" => username})
       when is_binary(username) do
    case Username.normalize(username) do
      nil -> "username:missing"
      normalized -> "username:" <> normalized
    end
  end

  defp passkey_identifier_key(%{"email" => email}) when is_binary(email),
    do: "email:" <> Identity.normalize_email(email)

  defp passkey_identifier_key(identifier) when is_binary(identifier) do
    case Username.normalize(identifier) do
      nil -> "identifier:" <> String.downcase(String.trim(identifier))
      normalized -> "identifier:" <> normalized
    end
  end

  defp passkey_identifier_key(_), do: "identifier:unknown"

  defp find_active_passkey(credential_id) do
    query =
      from p in Passkey,
        where: p.credential_id == ^credential_id and is_nil(p.disabled_at)

    case Repo.one(query) do
      %Passkey{} = passkey -> {:ok, passkey}
      nil -> {:error, :not_found}
    end
  end

  defp decode_base64(map, [string_key, atom_key]) do
    case Map.get(map, string_key) || Map.get(map, atom_key) do
      nil ->
        {:error, :missing_field}

      value when is_binary(value) ->
        # Browsers send base64url (uses - and _). Try url-safe first, then
        # fall back to standard base64 for any server-generated values.
        case Base.url_decode64(value, padding: false) do
          {:ok, decoded} ->
            {:ok, decoded}

          :error ->
            case Base.decode64(value, padding: false) do
              {:ok, decoded} -> {:ok, decoded}
              :error -> {:error, :invalid_field}
            end
        end

      _ ->
        {:error, :invalid_field}
    end
  end

  defp emit_passkey_event(action, metadata) do
    :telemetry.execute(
      [:famichat, :auth, :passkeys, action],
      %{count: 1},
      metadata
    )
  end
end
