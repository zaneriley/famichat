defmodule Famichat.Auth.Passkeys do
  @moduledoc """
  WebAuthn challenge orchestration: issuance, verification, and
  consumption of passkey registration/assertion challenges.

  Responses include WebAuthn `public_key_options` alongside an opaque challenge
  handle that clients must echo during attestation/assertion.
  """

  use Boundary,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Accounts,
      Famichat.Auth.Runtime,
      Famichat.Auth.RateLimit,
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
  Issues a registration challenge for the provided user.
  """
  @spec issue_registration_challenge(User.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def issue_registration_challenge(%User{} = user, opts \\ []) do
    do_issue(@registration_type, user, opts)
  end

  @doc """
  Issues an assertion challenge based on a flexible identifier (user id,
  username, or email).
  """
  @spec issue_assertion_challenge(map() | String.t()) ::
          {:ok, map()} | {:error, term()}
  def issue_assertion_challenge(identifier)
      when is_map(identifier) and not is_struct(identifier) do
    do_issue_assertion_for_identifier(identifier)
  end

  def issue_assertion_challenge(identifier) when is_binary(identifier) do
    do_issue_assertion_for_identifier(identifier)
  end

  defp do_issue_assertion_for_identifier(identifier) do
    key = passkey_identifier_key(identifier)

    with :ok <-
           RateLimit.check(:"passkey.assertion", key, limit: 10, interval: 60),
         {:ok, user} <- Identity.resolve_user(identifier),
         {:ok, challenge} <- issue_assertion_challenge(user, []) do
      {:ok, challenge}
    else
      {:error, {:rate_limited, retry}} -> {:error, {:rate_limited, retry}}
      other -> other
    end
  end

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
  """
  @spec register_passkey(map()) ::
          {:ok, Passkey.t()} | {:error, term()}
  def register_passkey(attestation_payload) when is_map(attestation_payload) do
    with {:ok, challenge_ctx} <-
           resolve_registration_challenge(attestation_payload),
         {:ok, user} <- Identity.fetch_user(challenge_ctx.user_id),
         :ok <-
           verify_payload_challenge(
             attestation_payload,
             challenge_ctx.challenge_binary
           ),
         {:ok, credential_id} <-
           decode_base64(attestation_payload, ["credential_id", :credential_id]),
         {:ok, public_key} <-
           decode_base64(attestation_payload, ["public_key", :public_key]) do
      attrs = %{
        user_id: user.id,
        credential_id: credential_id,
        public_key: public_key,
        sign_count:
          Map.get(attestation_payload, "sign_count") ||
            Map.get(attestation_payload, :sign_count, 0),
        aaguid: decode_optional(attestation_payload, ["aaguid", :aaguid]),
        label:
          Map.get(attestation_payload, "label") ||
            Map.get(attestation_payload, :label),
        last_used_at: DateTime.utc_now()
      }

      case Repo.insert(Passkey.changeset(%Passkey{}, attrs)) do
        {:ok, passkey} ->
          with :ok <- finalize_registration_challenge(challenge_ctx) do
            emit_passkey_event(:register, %{user_id: user.id})
            _ = Identity.sync_enrollment_requirement(user)
            {:ok, passkey}
          end

        error ->
          error
      end
    end
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
         :ok <- verify_assertion_user(passkey, challenge_ctx.user_id),
         :ok <-
           verify_payload_challenge(payload, challenge_ctx.challenge_binary),
         :ok <- validate_sign_count(passkey, payload),
         {:ok, passkey} <- touch_passkey(passkey, payload),
         :ok <- finalize_assertion_challenge(challenge_ctx) do
      user = Repo.preload(passkey, :user).user
      emit_passkey_event(:assert, %{user_id: user.id})
      {:ok, %{user: user, passkey: passkey}}
    end
  end

  ## Implementation ---------------------------------------------------------

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

    legacy_payload = %{
      "challenge" => challenge_b64,
      "challenge_handle" => handle,
      "expires_at" => expires_at,
      "public_key_options" => public_key_options
    }

    atom_payload = %{
      challenge: challenge_b64,
      challenge_handle: handle,
      expires_at: expires_at,
      public_key_options: public_key_options
    }

    Map.merge(legacy_payload, atom_payload)
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
        "userVerification" => "preferred"
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
      "userVerification" => "preferred"
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
        when reason in [:expired, :invalid, :invalid_challenge, :type_mismatch] ->
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
  defp adapt_fetch_error(:invalid), do: {:error, :invalid_challenge}
  defp adapt_fetch_error(:invalid_challenge), do: {:error, :invalid_challenge}
  defp adapt_fetch_error(:type_mismatch), do: {:error, :invalid_challenge}

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

  defp verify_payload_challenge(payload, expected_binary) do
    with {:ok, provided} <-
           fetch_binary_param(payload, ["challenge", :challenge]),
         {:ok, decoded} <- decode_challenge_string(provided),
         true <- decoded == expected_binary || {:error, :invalid_challenge} do
      :ok
    end
  end

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

  defp decode_challenge_string(challenge) when is_binary(challenge) do
    case Base.url_decode64(challenge, padding: false) do
      {:ok, decoded} ->
        {:ok, decoded}

      :error ->
        case Base.decode64(challenge) do
          {:ok, decoded} -> {:ok, decoded}
          :error -> {:error, :invalid_challenge}
        end
    end
  end

  defp decode_challenge_string(_), do: {:error, :invalid_challenge}

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

  defp validate_sign_count(%Passkey{sign_count: stored}, payload) do
    incoming =
      payload
      |> Map.get("sign_count") ||
        Map.get(payload, :sign_count) || stored

    if incoming >= stored do
      :ok
    else
      {:error, :replayed}
    end
  end

  defp touch_passkey(passkey, payload) do
    sign_count =
      payload
      |> Map.get("sign_count") ||
        Map.get(payload, :sign_count) ||
        passkey.sign_count

    attrs = %{sign_count: sign_count, last_used_at: DateTime.utc_now()}

    passkey
    |> Passkey.changeset(attrs)
    |> Repo.update()
  end

  defp decode_base64(map, [string_key, atom_key]) do
    case Map.get(map, string_key) || Map.get(map, atom_key) do
      nil ->
        {:error, :missing_field}

      value when is_binary(value) ->
        case Base.decode64(value, padding: false) do
          {:ok, decoded} -> {:ok, decoded}
          :error -> Base.decode64(value)
        end

      _ ->
        {:error, :invalid_field}
    end
  end

  defp decode_optional(map, keys) do
    case Enum.find_value(keys, fn key -> Map.get(map, key) end) do
      nil ->
        nil

      value when is_binary(value) ->
        case Base.decode64(value) do
          {:ok, decoded} -> decoded
          :error -> nil
        end

      value ->
        value
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
