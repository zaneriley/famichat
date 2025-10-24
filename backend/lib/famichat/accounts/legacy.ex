defmodule Famichat.Accounts.Legacy do
  @moduledoc """
  Account, authentication, and device/session management for Famichat.

  Exposes invite → register → passkey flows together with access/refresh
  sessions and trust windows. All tokens share the `user_tokens` table with
  hashed storage.
  """

  alias Famichat.Accounts.{
    FamilyMembership,
    Passkey,
    RateLimiter,
    Token,
    User,
    UserDevice,
    UserToken
  }

  alias Famichat.Auth.Passkeys
  alias Famichat.Auth.Sessions
  alias Famichat.Auth.Tokens
  alias Famichat.Auth.Infra.Instrumentation
  alias Famichat.Chat.Family
  alias Famichat.Vault
  alias Famichat.Repo
  alias Ecto.Changeset

  import Ecto.Query
  require Famichat.Auth.Infra.Instrumentation

  @typedoc "Opaque token string returned to the client"
  @type token :: String.t()

  ## Invite lifecycle --------------------------------------------------------

  @spec issue_invite(Ecto.UUID.t(), String.t() | nil, map()) ::
          {:ok, %{invite: token(), qr: token(), admin_code: String.t()}}
          | {:error, term()}
  def issue_invite(
        inviter_id,
        email,
        %{family_id: family_id, role: role} = payload
      )
      when role in ["admin", "member", :admin, :member] do
    Instrumentation.span(
      [:famichat, :auth, :accounts, :issue_invite],
      %{},
      do:
        case rate_limit(:invite_issue, inviter_id, 20, 60) do
          :ok -> do_issue_invite(inviter_id, email, payload, family_id)
          error -> error
        end
    )
  end

  defp do_issue_invite(inviter_id, email, payload, family_id) do
    Repo.transaction(fn ->
      with {:ok, inviter} <- fetch_user(inviter_id),
           {:ok, membership} <- ensure_membership(inviter.id, family_id),
           true <- membership.role == :admin || {:error, :forbidden},
           {:ok, _family} <- fetch_family(family_id),
           payload_map <- invite_payload(payload, email),
           {:ok, %Tokens.Issue{raw: invite_raw, record: invite_record}} <-
             Tokens.issue(:invite, payload_map),
           {:ok, pairing_bundle} <-
             issue_pairing_tokens(invite_record, invite_raw) do
        telemetry(:invite, :issue, %{family_id: family_id, inviter: inviter_id})
        Map.put(pairing_bundle, :invite, invite_raw)
      else
        {:error, reason} -> Repo.rollback(reason)
        false -> Repo.rollback(:forbidden)
      end
    end)
  end

  defp invite_payload(payload, email) do
    %{
      "family_id" => payload.family_id,
      "role" => format_role(payload.role)
    }
    |> maybe_put_email_secret(email)
  end

  defp sanitize_invite_payload(payload) do
    payload
    |> Map.take(["family_id", "role", "email_fingerprint"])
    |> Map.put("email_present", Map.has_key?(payload, "email_ciphertext"))
  end

  defp issue_pairing_tokens(invite_record, invite_raw) do
    payload_base =
      invite_record.payload
      |> Map.put("invite_token_id", invite_record.id)
      |> Map.put(
        "invite_token_ciphertext",
        Base.encode64(Vault.encrypt!(invite_raw))
      )

    with {:ok, %Tokens.Issue{raw: qr_raw}} <-
           Tokens.issue(:pair_qr, Map.put(payload_base, "mode", "qr")),
         admin_code <- admin_code(),
         {:ok, %Tokens.Issue{}} <-
           Tokens.issue(
             :pair_admin_code,
             Map.put(payload_base, "mode", "admin_code"),
             raw: admin_code
           ) do
      {:ok, %{qr: qr_raw, admin_code: admin_code}}
    end
  end

  defp maybe_put_email_secret(map, email) when not is_binary(email), do: map

  defp maybe_put_email_secret(map, email) do
    normalized =
      email
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> :erlang.iolist_to_binary()

    fingerprint =
      :crypto.hash(:sha256, normalized)
      |> Base.encode16(case: :lower)

    map
    |> Map.put("email_fingerprint", fingerprint)
    |> Map.put("email_ciphertext", Base.encode64(Vault.encrypt!(normalized)))
  end

  defp decrypt_invite_token(nil), do: {:error, :invalid_pair}

  defp decrypt_invite_token(ciphertext) do
    case Base.decode64(ciphertext) do
      {:ok, decoded} -> {:ok, Vault.decrypt!(decoded)}
      :error -> {:error, :invalid_pair}
    end
  rescue
    _ -> {:error, :invalid_pair}
  end

  defp format_role(role) when is_atom(role), do: Atom.to_string(role)
  defp format_role(role), do: role

  defp admin_code do
    :rand.uniform(999_999)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  @spec accept_invite(token()) ::
          {:ok, %{payload: map(), registration_token: String.t()}}
          | {:error,
             :invalid | :expired | :used | {:rate_limited, pos_integer()}}
  def accept_invite(raw_token) when is_binary(raw_token) do
    with :ok <-
           rate_limit(:invite_accept, raw_token, 5, Tokens.default_ttl(:invite)),
         {:ok, invite} <- Tokens.fetch(:invite, raw_token),
         {:ok, _} <- Tokens.consume(invite) do
      payload = sanitize_invite_payload(invite.payload)

      registration_token =
        sign_invite_registration_token(%{
          "invite_token_id" => invite.id,
          "family_id" => payload["family_id"],
          "role" => payload["role"],
          "email_ciphertext" => Map.get(invite.payload, "email_ciphertext"),
          "email_fingerprint" => Map.get(invite.payload, "email_fingerprint")
        })

      telemetry(:invite, :accept, %{
        family_id: payload["family_id"],
        invite_id: invite.id
      })

      {:ok, %{payload: payload, registration_token: registration_token}}
    else
      {:error, {:rate_limited, retry}} -> {:error, {:rate_limited, retry}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec redeem_pairing_token(token()) ::
          {:ok, %{invite_token: String.t(), payload: map()}} | {:error, term()}
  def redeem_pairing_token(raw_token) when is_binary(raw_token) do
    with :ok <-
           rate_limit(
             :pairing_attempt,
             raw_token,
             5,
             Tokens.default_ttl(:pair_qr)
           ),
         {:ok, pairing} <- Tokens.fetch(:pair_qr, raw_token),
         invite_id when is_binary(invite_id) <-
           pairing.payload["invite_token_id"] || {:error, :invalid_pair},
         {:ok, invite} <- Token.fetch_by_id(invite_id),
         {:ok, invite_raw} <-
           decrypt_invite_token(pairing.payload["invite_token_ciphertext"]),
         {:ok, _} <- Tokens.consume(pairing) do
      {:ok,
       %{
         invite_token: invite_raw,
         payload: sanitize_invite_payload(invite.payload)
       }}
    else
      {:error, {:rate_limited, retry}} -> {:error, {:rate_limited, retry}}
    end
  end

  @spec reissue_pairing(Ecto.UUID.t(), String.t()) ::
          {:ok, %{qr: String.t(), admin_code: String.t()}} | {:error, term()}
  def reissue_pairing(requester_id, invite_raw) when is_binary(invite_raw) do
    with {:ok, invite} <- Tokens.fetch(:invite, invite_raw),
         {:ok, membership} <-
           ensure_membership(requester_id, invite.payload["family_id"]),
         true <- membership.role == :admin || {:error, :forbidden} do
      issue_pairing_tokens(invite, invite_raw)
    end
  end

  @spec register_user_from_invite(token(), map()) ::
          {:ok, %{user: User.t(), passkey_register_token: String.t()}}
          | {:error, term()}
  def register_user_from_invite(registration_token, attrs)
      when is_binary(registration_token) and is_map(attrs) do
    with {:ok, claims} <- verify_invite_registration_token(registration_token),
         rate_key <- claims["invite_token_id"] || registration_token,
         :ok <-
           rate_limit(
             :invite_register,
             rate_key,
             5,
             Tokens.default_ttl(:invite_registration)
           ) do
      Repo.transaction(fn ->
        with {:ok, family} <- fetch_family(claims["family_id"]),
             {:ok, user} <- create_user_from_invite(claims, attrs),
             {:ok, _membership} <-
               upsert_membership(user.id, family.id, claims["role"]),
             {:ok, %Tokens.Issue{raw: register_token}} <-
               issue_passkey_register_token(user.id) do
          telemetry(:invite, :complete, %{
            family_id: family.id,
            user_id: user.id,
            invite_id: claims["invite_token_id"]
          })

          %{user: user, passkey_register_token: register_token}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  defp create_user_from_invite(claims, attrs) do
    email =
      Map.get(attrs, "email") ||
        Map.get(attrs, :email) ||
        maybe_email_from_claims(claims)

    with :ok <- assert_invite_email_match(claims, email) do
      user_attrs =
        attrs
        |> atomize_keys()
        |> Map.put(:status, :active)
        |> Map.put(:confirmed_at, DateTime.utc_now())
        |> Map.put(:email, email)

      %User{}
      |> User.changeset(user_attrs)
      |> Repo.insert()
    end
  end

  defp maybe_email_from_claims(%{"email_ciphertext" => ciphertext}) do
    case Base.decode64(ciphertext) do
      {:ok, decoded} -> Vault.decrypt!(decoded)
      :error -> nil
    end
  rescue
    _ -> nil
  end

  defp maybe_email_from_claims(_), do: nil

  defp assert_invite_email_match(%{"email_fingerprint" => expected}, email)
       when is_binary(expected) do
    expected_hash =
      case Base.decode16(expected, case: :mixed) do
        {:ok, decoded} -> decoded
        :error -> expected
      end

    cond do
      not is_binary(email) ->
        {:error, :email_required}

      email_hash(normalize_email(email)) == expected_hash ->
        :ok

      true ->
        {:error, :email_mismatch}
    end
  end

  defp assert_invite_email_match(_, _), do: :ok

  defp issue_passkey_register_token(user_id) do
    Tokens.issue(:passkey_reg, %{"user_id" => user_id}, user_id: user_id)
  end

  ## Passkeys ----------------------------------------------------------------

  @spec exchange_passkey_register_token(token()) ::
          {:ok, User.t()} | {:error, term()}
  def exchange_passkey_register_token(raw_token) when is_binary(raw_token) do
    with {:ok, token} <- Tokens.fetch(:passkey_reg, raw_token),
         {:ok, user} <- fetch_user(token.payload["user_id"]),
         {:ok, _} <- Tokens.consume(token) do
      {:ok, user}
    end
  end

  @spec issue_passkey_registration_challenge(User.t() | Ecto.UUID.t()) ::
          {:ok, map()} | {:error, term()}
  def issue_passkey_registration_challenge(%User{} = user) do
    do_issue_passkey_registration_challenge(user)
  end

  def issue_passkey_registration_challenge(user_id) when is_binary(user_id) do
    with {:ok, user} <- fetch_user(user_id) do
      do_issue_passkey_registration_challenge(user)
    end
  end

  defp do_issue_passkey_registration_challenge(%User{} = user) do
    case Passkeys.issue_registration_challenge(user) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec issue_passkey_assertion_challenge(map() | String.t()) ::
          {:ok, map()} | {:error, term()}
  def issue_passkey_assertion_challenge(identifier) do
    key = passkey_identifier_key(identifier)

    with :ok <- rate_limit(:passkey_assertion_challenge, key, 10, 60),
         {:ok, user} <- resolve_user(identifier),
         {:ok, challenge} <- build_passkey_assertion_challenge(user) do
      {:ok, challenge}
    else
      {:error, {:rate_limited, retry}} -> {:error, {:rate_limited, retry}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_passkey_assertion_challenge(%User{} = user) do
    Passkeys.issue_assertion_challenge(user)
  end

  @spec register_passkey(map()) :: {:ok, Passkey.t()} | {:error, term()}
  def register_passkey(attestation_payload) do
    with {:ok, challenge_ctx} <-
           resolve_registration_challenge(attestation_payload),
         {:ok, user} <- fetch_user(challenge_ctx.user_id),
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
            telemetry(:passkey, :register, %{user_id: user.id})
            _ = sync_enrollment_requirement(user)
            {:ok, passkey}
          end

        error ->
          error
      end
    end
  end

  @spec assert_passkey(map()) ::
          {:ok, %{user: User.t(), passkey: Passkey.t()}} | {:error, term()}
  def assert_passkey(payload) when is_map(payload) do
    rate_key = passkey_rate_key(payload)

    case do_assert_passkey(payload) do
      {:ok, _} = ok ->
        ok

      {:error, _reason} = error ->
        case rate_limit(:passkey_failure, rate_key, 5, 60) do
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
      telemetry(:passkey, :assert, %{user_id: user.id})
      {:ok, %{user: user, passkey: passkey}}
    end
  end

  defp resolve_registration_challenge(payload) do
    with {:ok, handle} <-
           fetch_binary_param(payload, ["challenge_handle", :challenge_handle]),
         {:ok, challenge} <- Passkeys.fetch_registration_challenge(handle) do
      {:ok, challenge_context(challenge)}
    end
  end

  defp resolve_assertion_challenge(payload) do
    with {:ok, handle} <-
           fetch_binary_param(payload, ["challenge_handle", :challenge_handle]),
         {:ok, challenge} <- Passkeys.fetch_assertion_challenge(handle) do
      {:ok, challenge_context(challenge)}
    end
  end

  defp challenge_context(challenge) do
    binary = challenge.challenge

    %{
      record: challenge,
      user_id: challenge.user_id,
      challenge_binary: binary,
      challenge_b64: Base.url_encode64(binary, padding: false)
    }
  end

  defp finalize_registration_challenge(%{record: record}) do
    case Passkeys.consume_challenge(record) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp finalize_assertion_challenge(%{record: record}) do
    case Passkeys.consume_challenge(record) do
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
    case Famichat.Accounts.Username.normalize(username) do
      nil -> "username:missing"
      normalized -> "username:" <> normalized
    end
  end

  defp passkey_identifier_key(%{"email" => email}) when is_binary(email),
    do: "email:" <> normalize_email(email)

  defp passkey_identifier_key(identifier) when is_binary(identifier) do
    case Famichat.Accounts.Username.normalize(identifier) do
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
      |> Map.get("sign_count") || Map.get(payload, :sign_count) || stored

    if incoming >= stored do
      :ok
    else
      {:error, :replayed}
    end
  end

  defp touch_passkey(passkey, payload) do
    sign_count =
      payload
      |> Map.get("sign_count") || Map.get(payload, :sign_count) ||
        passkey.sign_count

    attrs = %{sign_count: sign_count, last_used_at: DateTime.utc_now()}

    passkey
    |> Passkey.changeset(attrs)
    |> Repo.update()
  end

  ## Sessions & device trust -------------------------------------------------

  @doc """
  Starts a new session for a user on a device.

  Options:
    * `:remember` (boolean) - hints whether the caller would like the device to
      receive a long-lived trust window. This may be ignored if policy denies.
  """
  @spec start_session(User.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def start_session(user, device_info, opts \\ []) do
    Sessions.start_session(user, device_info, opts)
  end

  @spec refresh_session(String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def refresh_session(device_id, raw_refresh) do
    Sessions.refresh_session(device_id, raw_refresh)
  end

  @spec revoke_device(Ecto.UUID.t(), String.t()) ::
          {:ok, :revoked} | {:error, :not_found}
  def revoke_device(user_id, device_id) do
    Sessions.revoke_device(user_id, device_id)
  end

  @spec verify_access_token(String.t()) ::
          {:ok, %{user_id: Ecto.UUID.t(), device_id: String.t()}}
          | {:error, term()}
  def verify_access_token(token) do
    Sessions.verify_access_token(token)
  end

  @spec require_reauth?(Ecto.UUID.t(), String.t(), atom()) :: boolean()
  def require_reauth?(user_id, device_id, action) do
    Sessions.require_reauth?(user_id, device_id, action)
  end

  ## Magic links, pairing, OTP, recovery ------------------------------------

  @spec issue_magic_link(String.t()) ::
          {:ok, token(), UserToken.t()} | {:error, term()}
  def issue_magic_link(email) do
    case rate_limit(:magic_link, normalize_email(email), 5, 60) do
      :ok -> do_issue_magic_link(email)
      error -> error
    end
  end

  defp do_issue_magic_link(email) do
    with {:ok, user} <- fetch_user_by_email(email),
         payload <- %{"user_id" => user.id},
         {:ok, %Tokens.Issue{raw: token, record: record}} <-
           Tokens.issue(:magic_link, payload, user_id: user.id) do
      telemetry(:magic, :issue, %{user_id: user.id})
      {:ok, token, record}
    end
  end

  @spec redeem_magic_link(token()) :: {:ok, User.t()} | {:error, term()}
  def redeem_magic_link(raw_token) do
    Repo.transaction(fn ->
      with {:ok, token} <- Tokens.fetch(:magic_link, raw_token),
           {:ok, user} <- fetch_user(token.payload["user_id"]),
           {:ok, user} <- sync_enrollment_requirement(user),
           {:ok, _} <- Tokens.consume(token) do
        telemetry(:magic, :redeem, %{user_id: user.id})
        user
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, %User{} = user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec issue_otp(String.t()) ::
          {:ok, String.t(), UserToken.t()} | {:error, term()}
  def issue_otp(email) do
    case rate_limit(:otp_issue, normalize_email(email), 3, 60) do
      :ok -> do_issue_otp(email)
      error -> error
    end
  end

  defp do_issue_otp(email) do
    with {:ok, user} <- fetch_user_by_email(email) do
      code = (:rand.uniform(900_000) + 99_999) |> Integer.to_string()
      payload = %{"user_id" => user.id, "code" => code}
      hashed_email = email_hash(normalize_email(email))
      context = "otp:" <> Base.encode16(hashed_email, case: :lower)

      case Tokens.issue(:otp, payload,
             context: context,
             user_id: user.id,
             raw: code
           ) do
        {:ok, %Tokens.Issue{raw: raw_code, record: record}} ->
          telemetry(:otp, :issue, %{user_id: user.id})
          {:ok, raw_code, record}

        other ->
          other
      end
    end
  end

  @spec verify_otp(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, term()}
  def verify_otp(email, code) do
    hashed_email = email_hash(normalize_email(email))
    context = "otp:" <> Base.encode16(hashed_email, case: :lower)

    with {:ok, token} <- Tokens.fetch(:otp, code, context: context),
         true <- token.payload["code"] == code || {:error, :invalid},
         {:ok, user} <- fetch_user(token.payload["user_id"]),
         {:ok, _} <- Tokens.consume(token) do
      telemetry(:otp, :verify, %{user_id: user.id})
      {:ok, user}
    end
  end

  @spec issue_recovery(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, token(), UserToken.t()} | {:error, term()}
  def issue_recovery(admin_id, user_id) do
    with {:ok, admin} <- fetch_user(admin_id),
         true <-
           admin.id == user_id || member_role(admin_id, user_id) == :admin,
         {:ok, %Tokens.Issue{raw: token, record: record}} <-
           Tokens.issue(:recovery, %{"user_id" => user_id}, user_id: admin_id) do
      telemetry(:recovery, :issue, %{user_id: user_id, admin_id: admin_id})
      {:ok, token, record}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :forbidden}
    end
  end

  defp member_role(admin_id, target_user_id) do
    query =
      from m in FamilyMembership,
        where: m.user_id == ^admin_id and m.role == :admin,
        join: t in FamilyMembership,
        on: t.family_id == m.family_id and t.user_id == ^target_user_id,
        limit: 1,
        select: t.role

    Repo.one(query)
  end

  @spec redeem_recovery(token()) :: {:ok, User.t()} | {:error, term()}
  def redeem_recovery(raw_token) do
    Repo.transaction(fn ->
      with {:ok, token} <- Tokens.fetch(:recovery, raw_token),
           {:ok, user} <- fetch_user(token.payload["user_id"]),
           {:ok, _} <- disable_devices_and_passkeys(user.id),
           {:ok, user} <- enter_enrollment_required_state(user),
           {:ok, _} <- Tokens.consume(token) do
        telemetry(:recovery, :redeem, %{user_id: user.id})
        user
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp disable_devices_and_passkeys(user_id) do
    from(d in UserDevice, where: d.user_id == ^user_id)
    |> Repo.update_all(
      set: [revoked_at: DateTime.utc_now(), refresh_token_hash: nil]
    )

    from(p in Passkey, where: p.user_id == ^user_id)
    |> Repo.update_all(set: [disabled_at: DateTime.utc_now()])
    |> case do
      {_, _} -> {:ok, :cleared}
      error -> error
    end
  end

  ## Helpers -----------------------------------------------------------------

  defp ensure_membership(user_id, family_id) do
    case Repo.get_by(FamilyMembership, user_id: user_id, family_id: family_id) do
      %FamilyMembership{} = membership -> {:ok, membership}
      nil -> {:error, :not_in_family}
    end
  end

  defp upsert_membership(user_id, family_id, role) do
    attrs = %{user_id: user_id, family_id: family_id, role: format_role(role)}

    case Repo.get_by(FamilyMembership, user_id: user_id, family_id: family_id) do
      nil ->
        %FamilyMembership{}
        |> FamilyMembership.changeset(attrs)
        |> Repo.insert()

      %FamilyMembership{} = membership ->
        membership
        |> FamilyMembership.changeset(attrs)
        |> Repo.update()
    end
  end

  defp fetch_user(user_id) do
    case Repo.get(User, user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :user_not_found}
    end
  end

  defp fetch_user_by_email(email) do
    fingerprint = email_hash(normalize_email(email))

    Repo.get_by(User, email_fingerprint: fingerprint)
    |> case do
      %User{} = user -> {:ok, user}
      nil -> {:error, :user_not_found}
    end
  end

  @spec sync_enrollment_requirement(User.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  defp sync_enrollment_requirement(%User{} = user) do
    active_count =
      from(p in Passkey,
        where: p.user_id == ^user.id and is_nil(p.disabled_at),
        select: count(p.id)
      )
      |> Repo.one()

    cond do
      active_count == 0 and is_nil(user.enrollment_required_since) ->
        user
        |> Changeset.change(enrollment_required_since: DateTime.utc_now())
        |> Repo.update()

      active_count == 0 ->
        {:ok, user}

      user.enrollment_required_since ->
        user
        |> Changeset.change(enrollment_required_since: nil)
        |> Repo.update()

      true ->
        {:ok, user}
    end
  end

  defp enter_enrollment_required_state(%User{} = user) do
    user
    |> User.changeset(%{enrollment_required_since: DateTime.utc_now()})
    |> Repo.update()
  end

  defp fetch_user_by_username(username) do
    with fingerprint when is_binary(fingerprint) <-
           Famichat.Accounts.Username.fingerprint(username),
         %User{} = user <-
           Repo.get_by(User, username_fingerprint: fingerprint) do
      {:ok, user}
    else
      _ -> {:error, :user_not_found}
    end
  end

  defp fetch_family(family_id) do
    case Repo.get(Family, family_id) do
      %Family{} = family -> {:ok, family}
      nil -> {:error, :family_not_found}
    end
  end

  defp resolve_user(%{"user_id" => user_id}) when is_binary(user_id),
    do: fetch_user(user_id)

  defp resolve_user(%{"username" => username}) when is_binary(username),
    do: fetch_user_by_username(username)

  defp resolve_user(%{"email" => email}) when is_binary(email),
    do: fetch_user_by_email(email)

  defp resolve_user(identifier) when is_binary(identifier) do
    case fetch_user_by_username(identifier) do
      {:ok, user} -> {:ok, user}
      {:error, :user_not_found} -> fetch_user_by_email(identifier)
      other -> other
    end
  end

  defp resolve_user(_), do: {:error, :user_not_found}

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

  defp rate_limit(bucket, key, limit, interval) do
    case RateLimiter.throttle(bucket, key, limit, interval) do
      :ok -> :ok
      {:error, :throttled, retry} -> {:error, {:rate_limited, retry}}
    end
  end

  defp sign_invite_registration_token(payload) do
    {:ok, %Tokens.Issue{raw: token}} =
      Tokens.issue(:invite_registration, payload)

    token
  end

  defp verify_invite_registration_token(token) do
    Tokens.verify(:invite_registration, token)
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

  @allowed_user_keys [
    :username,
    :email,
    :status,
    :password_hash,
    :confirmed_at,
    :last_login_at
  ]
  @allowed_user_key_map Map.new(@allowed_user_keys, fn key ->
                          {Atom.to_string(key), key}
                        end)
  defp atomize_keys(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case normalize_allowed_key(key) do
        {:ok, atom_key} -> Map.put(acc, atom_key, value)
        :error -> acc
      end
    end)
  end

  defp normalize_allowed_key(key) when is_atom(key) do
    if key in @allowed_user_keys do
      {:ok, key}
    else
      :error
    end
  end

  defp normalize_allowed_key(key) when is_binary(key) do
    normalized =
      key
      |> String.trim()
      |> String.downcase()

    case Map.fetch(@allowed_user_key_map, normalized) do
      {:ok, atom_key} -> {:ok, atom_key}
      :error -> :error
    end
  end

  defp normalize_allowed_key(_), do: :error

  defp normalize_email(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  defp email_hash(email), do: :crypto.hash(:sha256, email)

  defp telemetry(scope, action, metadata) do
    :telemetry.execute(
      [:famichat, :auth, scope, action],
      %{count: 1},
      metadata
    )
  end
end
