defmodule Famichat.Auth.Onboarding do
  @moduledoc """
  Invite, pairing, and registration orchestration for households.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Accounts,
      Famichat.Chat,
      Famichat.Auth.Households,
      Famichat.Auth.Identity,
      Famichat.Auth.RateLimit,
      Famichat.Auth.Runtime,
      Famichat.Auth.Tokens
    ]

  import Ecto.Query, only: [from: 2]

  alias Famichat.Accounts.User
  alias Famichat.Auth.Households
  alias Famichat.Auth.Identity
  alias Famichat.Auth.Runtime.Instrumentation
  alias Famichat.Auth.RateLimit
  alias Famichat.Auth.Tokens
  alias Famichat.Auth.Tokens.IssuedToken
  alias Famichat.Auth.Tokens.Storage, as: TokenStorage
  alias Famichat.Chat.Family
  alias Famichat.Repo
  alias Famichat.Vault

  require Famichat.Auth.Runtime.Instrumentation

  @invite_issue_bucket :"invite.issue"
  @invite_accept_bucket :"invite.accept"
  @invite_complete_bucket :"invite.complete"
  @pairing_redeem_bucket :"pairing.redeem"
  @pairing_reissue_bucket :"pairing.reissue"

  @spec issue_invite(Ecto.UUID.t(), String.t() | nil, map()) ::
          {:ok, %{invite: String.t(), qr: String.t(), admin_code: String.t()}}
          | {:error, term()}
  def issue_invite(inviter_id, email, %{role: role} = payload)
      when role in ["admin", "member", :admin, :member] do
    household_id = household_id_from_payload(payload)

    if is_nil(household_id) do
      {:error, :missing_household_id}
    else
      Instrumentation.span(
        [:famichat, :auth, :onboarding, :issue_invite],
        %{inviter_id: inviter_id, household_id: household_id},
        do:
          case RateLimit.check(@invite_issue_bucket, inviter_id,
                 limit: 20,
                 interval: 60
               ) do
            :ok -> do_issue_invite(inviter_id, email, payload, household_id)
            error -> error
          end
      )
    end
  end

  def issue_invite(_, _, _), do: {:error, :invalid_role}

  @spec bootstrap_admin(String.t(), map()) ::
          {:ok, %{user: User.t(), family: Famichat.Chat.Family.t(), passkey_register_token: String.t()}}
          | {:error, :admin_exists}
          | {:error, :invalid_input}
          | {:error, :username_required}
          | {:error, Ecto.Changeset.t()}
  def bootstrap_admin(username, opts \\ %{}) do
    with {:ok, normalized_username} <- validate_bootstrap_username(username) do
      family_name = Map.get(opts, :family_name) || Map.get(opts, "family_name") || "My Family"

      result =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:check_admin, fn repo, _changes ->
          count = repo.one(from u in User, select: count(u.id))

          if count > 0 do
            {:error, :admin_exists}
          else
            {:ok, :no_admin}
          end
        end)
        |> Ecto.Multi.insert(:family, Famichat.Chat.Family.changeset(%Famichat.Chat.Family{}, %{name: family_name}))
        |> Ecto.Multi.run(:user, fn _repo, _changes ->
          user_attrs =
            opts
            |> Identity.permit_user_attrs()
            |> Map.put(:username, normalized_username)
            |> Map.put(:status, :active)
            |> Map.put(:confirmed_at, DateTime.utc_now())

          %User{}
          |> User.changeset(user_attrs)
          |> Repo.insert()
        end)
        |> Ecto.Multi.run(:membership, fn _repo, %{user: user, family: family} ->
          Households.add_member(family.id, user.id, :admin)
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{user: user, family: family}} ->
          :telemetry.execute(
            [:famichat, :auth, :onboarding, :bootstrap_admin_created],
            %{count: 1},
            %{user_id: user.id, family_id: family.id}
          )

          {:ok, %IssuedToken{raw: register_token}} =
            Tokens.issue(:passkey_registration, %{"user_id" => user.id},
              user_id: user.id
            )

          {:ok, %{user: user, family: family, passkey_register_token: register_token}}

        {:error, :check_admin, :admin_exists, _} ->
          {:error, :admin_exists}

        {:error, _step, %Ecto.Changeset{} = changeset, _} ->
          {:error, changeset}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  defp validate_bootstrap_username(username) when is_binary(username) do
    normalized = Identity.normalize_username(username)

    cond do
      is_nil(normalized) or String.trim(normalized) == "" ->
        {:error, :username_required}

      String.length(normalized) < 3 ->
        {:error, :invalid_input}

      true ->
        {:ok, normalized}
    end
  end

  defp validate_bootstrap_username(nil), do: {:error, :username_required}
  defp validate_bootstrap_username(_), do: {:error, :invalid_input}

  defp do_issue_invite(inviter_id, email, payload, household_id) do
    Repo.transaction(fn ->
      with {:ok, inviter} <- Identity.fetch_user(inviter_id),
           {:ok, _membership} <-
             Households.ensure_admin_membership(inviter.id, household_id),
           {:ok, _family} <- fetch_family(household_id),
           payload_map <- invite_payload(payload, email, inviter_id),
           {:ok, %IssuedToken{raw: invite_raw, record: invite_record}} <-
             Tokens.issue(:invite, payload_map),
           {:ok, pairing_bundle} <-
             issue_pairing_tokens(invite_record, invite_raw) do
        emit_onboarding_event(:invite_issued, %{
          household_id: household_id,
          inviter_id: inviter_id
        })

        Map.put(pairing_bundle, :invite, invite_raw)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Validates an invite token without consuming it.

  Returns `:ok` if the token exists and is valid (not expired, not used).
  Returns `{:error, :invalid}`, `{:error, :expired}`, or `{:error, :used}`
  for invalid tokens.

  Used by `FamichatWeb.Plugs.ValidateInviteToken` to gate the invite route
  at the HTTP layer before the LiveView mounts.
  """
  @spec validate_invite_token(String.t()) ::
          :ok | {:error, :invalid | :expired | :used}
  def validate_invite_token(raw_token) when is_binary(raw_token) do
    case Tokens.fetch(:invite, raw_token) do
      {:ok, _invite} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec accept_invite(String.t()) ::
          {:ok, %{payload: map(), registration_token: String.t()}}
          | {:error, term()}
  def accept_invite(raw_token) when is_binary(raw_token) do
    with :ok <-
           RateLimit.check(@invite_accept_bucket, raw_token,
             limit: 5,
             interval: Tokens.default_ttl(:invite)
           ),
         {:ok, invite} <- Tokens.fetch(:invite, raw_token),
         {:ok, _} <- Tokens.consume(invite) do
      payload = sanitize_invite_payload(invite.payload)

      registration_token =
        sign_invite_registration_token(%{
          "invite_token_id" => invite.id,
          "family_id" => payload["household_id"] || payload["family_id"],
          "role" => payload["role"],
          "email_ciphertext" => Map.get(invite.payload, "email_ciphertext"),
          "email_fingerprint" => Map.get(invite.payload, "email_fingerprint"),
          "inviter_id" => Map.get(invite.payload, "inviter_id")
        })

      emit_onboarding_event(:invite_accepted, %{
        household_id: payload["household_id"] || payload["family_id"],
        invite_id: invite.id
      })

      {:ok, %{payload: payload, registration_token: registration_token}}
    else
      {:error, {:rate_limited, retry}} -> {:error, {:rate_limited, retry}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches the sanitized payload of a previously-accepted invite token and
  re-issues a fresh registration token. Does NOT consume the token. Used by
  InviteLive to recover payload on WebSocket reconnect after the invite has
  already been accepted (the `:used` path).

  Returns `{:ok, payload, registration_token}` even if `used_at` is set (i.e.,
  already consumed), as long as the token exists and has not expired.
  Returns `{:error, :invalid}` if the token does not exist.
  Returns `{:error, :expired}` if the token has expired.
  Returns `{:error, :reinvite_needed}` if a new registration token cannot be
  issued (e.g. missing required payload fields).
  """
  @spec peek_invite(String.t()) ::
          {:ok, map(), String.t()} | {:error, :invalid | :expired | :reinvite_needed}
  def peek_invite(raw_token) when is_binary(raw_token) do
    hash = TokenStorage.hash(raw_token)
    context = Famichat.Auth.Tokens.Policy.legacy_context(:invite)

    case Repo.get_by(Famichat.Accounts.UserToken,
           context: context,
           token_hash: hash
         ) do
      nil ->
        {:error, :invalid}

      %Famichat.Accounts.UserToken{expires_at: expires_at} = token ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :lt do
          {:error, :expired}
        else
          payload = sanitize_invite_payload(token.payload)

          reg_token_result =
            sign_invite_registration_token(%{
              "invite_token_id" => token.id,
              "family_id" => token.payload["household_id"] || token.payload["family_id"],
              "role" => token.payload["role"],
              "email_ciphertext" => Map.get(token.payload, "email_ciphertext"),
              "email_fingerprint" => Map.get(token.payload, "email_fingerprint"),
              "inviter_id" => Map.get(token.payload, "inviter_id")
            })

          case reg_token_result do
            registration_token when is_binary(registration_token) ->
              {:ok, payload, registration_token}

            _ ->
              {:error, :reinvite_needed}
          end
        end
    end
  end

  @spec redeem_pairing(String.t()) ::
          {:ok, %{invite_token: String.t(), payload: map()}} | {:error, term()}
  def redeem_pairing(raw_token) when is_binary(raw_token) do
    with :ok <-
           RateLimit.check(@pairing_redeem_bucket, raw_token,
             limit: 5,
             interval: Tokens.default_ttl(:pair_qr)
           ),
         {:ok, pairing} <- Tokens.fetch(:pair_qr, raw_token),
         invite_id when is_binary(invite_id) <-
           pairing.payload["invite_token_id"] || {:error, :invalid_pair},
         {:ok, invite} <- TokenStorage.fetch_ledgered_by_id(invite_id),
         {:ok, invite_raw} <-
           decrypt_invite_token(pairing.payload["invite_token_ciphertext"]) do
      finalize_pairing(pairing, invite, invite_raw)
    else
      {:error, {:rate_limited, retry}} -> {:error, {:rate_limited, retry}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec reissue_pairing(Ecto.UUID.t(), String.t()) ::
          {:ok, %{qr: String.t(), admin_code: String.t()}} | {:error, term()}
  def reissue_pairing(requester_id, invite_raw) when is_binary(invite_raw) do
    with :ok <-
           RateLimit.check(@pairing_reissue_bucket, requester_id,
             limit: 5,
             interval: 60
           ),
         {:ok, invite} <- Tokens.fetch(:invite, invite_raw),
         {:ok, _membership} <-
           Households.ensure_admin_membership(
             requester_id,
             invite.payload["household_id"] || invite.payload["family_id"]
           ) do
      issue_pairing_tokens(invite, invite_raw)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec complete_registration(String.t(), map()) ::
          {:ok, %{user: User.t(), passkey_register_token: String.t()}}
          | {:error, :invalid_registration_token}
          | {:error, :expired_registration_token}
          | {:error, :invalid_registration}
          | {:error, :rate_limited, retry_in :: pos_integer()}
          | {:error, :user_not_found}
          | {:error, :email_required}
          | {:error, :email_mismatch}
          | {:error, :family_not_found}
          | {:error, Ecto.Changeset.t()}
  def complete_registration(registration_token, attrs)
      when is_binary(registration_token) and is_map(attrs) do
    with {:verify, {:ok, claims}} <-
           {:verify, verify_invite_registration_token(registration_token)},
         rate_key <- claims["invite_token_id"] || registration_token,
         :ok <-
           RateLimit.check(@invite_complete_bucket, rate_key,
             limit: 5,
             interval: Tokens.default_ttl(:invite_registration)
           ) do
      case Repo.transaction(fn ->
             with {:ok, family} <-
                    fetch_family(claims["household_id"] || claims["family_id"]),
                  {:ok, user} <- create_user_from_invite(claims, attrs),
                  {:ok, _membership} <-
                    Households.upsert_membership(
                      user.id,
                      family.id,
                      claims["role"]
                    ),
                  {:ok, %IssuedToken{raw: register_token}} <-
                    Tokens.issue(:passkey_registration, %{"user_id" => user.id},
                      user_id: user.id
                    ) do
               emit_onboarding_event(:invite_completed, %{
                 household_id: family.id,
                 user_id: user.id,
                 invite_id: claims["invite_token_id"]
               })

               %{user: user, passkey_register_token: register_token}
             else
               {:error, reason} -> Repo.rollback(reason)
             end
           end) do
        {:ok, result} ->
          schedule_direct_conversation_creation(
            Map.get(claims, "inviter_id"),
            result.user.id
          )

          {:ok, result}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:verify, {:error, :expired}} ->
        {:error, :expired_registration_token}

      {:verify, {:error, :invalid}} ->
        {:error, :invalid_registration_token}

      {:verify, {:error, :missing}} ->
        {:error, :invalid_registration_token}

      {:error, {:rate_limited, retry_in}} ->
        {:error, {:rate_limited, retry_in}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def complete_registration(_, _), do: {:error, :invalid_registration}

  ## Helpers ----------------------------------------------------------------

  defp invite_payload(payload, email, inviter_id) do
    household_id = household_id_from_payload(payload)

    %{
      "household_id" => household_id,
      "family_id" => household_id,
      "role" => format_role(payload[:role] || payload["role"]),
      "inviter_id" => inviter_id
    }
    |> maybe_put_email_secret(email)
  end

  defp household_id_from_payload(payload) do
    Map.get(payload, :household_id) ||
      Map.get(payload, "household_id") ||
      Map.get(payload, :family_id) ||
      Map.get(payload, "family_id")
  end

  defp sanitize_invite_payload(payload) do
    payload
    |> Map.put_new("household_id", Map.get(payload, "family_id"))
    |> Map.take(["household_id", "role", "email_fingerprint"])
    |> Map.put("email_present", Map.has_key?(payload, "email_ciphertext"))
  end

  defp finalize_pairing(pairing, invite, invite_raw) do
    Repo.transaction(fn ->
      case Tokens.consume(pairing) do
        {:ok, _} ->
          %{
            invite_token: invite_raw,
            payload: sanitize_invite_payload(invite.payload)
          }

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp issue_pairing_tokens(invite_record, invite_raw) do
    payload_base =
      invite_record.payload
      |> Map.put("invite_token_id", invite_record.id)
      |> Map.put(
        "invite_token_ciphertext",
        Base.encode64(Vault.encrypt!(invite_raw))
      )

    with {:ok, %IssuedToken{raw: qr_raw}} <-
           Tokens.issue(:pair_qr, Map.put(payload_base, "mode", "qr")),
         admin_code <- admin_code(),
         {:ok, %IssuedToken{}} <-
           Tokens.issue(
             :pair_admin_code,
             Map.put(payload_base, "mode", "admin_code"),
             raw: admin_code
           ) do
      {:ok, %{qr: qr_raw, admin_code: admin_code}}
    end
  end

  defp decrypt_invite_token(ciphertext) do
    case Base.decode64(ciphertext) do
      {:ok, decoded} -> {:ok, Vault.decrypt!(decoded)}
      :error -> {:error, :invalid_pair}
    end
  rescue
    _ -> {:error, :invalid_pair}
  end

  defp create_user_from_invite(claims, attrs) do
    email =
      Map.get(attrs, "email") ||
        Map.get(attrs, :email) ||
        maybe_email_from_claims(claims)

    with :ok <- assert_invite_email_match(claims, email) do
      user_attrs =
        attrs
        |> Identity.permit_user_attrs()
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

      Identity.email_hash(Identity.normalize_email(email)) == expected_hash ->
        :ok

      true ->
        {:error, :email_mismatch}
    end
  end

  defp assert_invite_email_match(_, _), do: :ok

  defp format_role(role) when is_atom(role), do: Atom.to_string(role)
  defp format_role(role), do: role

  defp admin_code do
    <<n::unsigned-32>> = :crypto.strong_rand_bytes(4)
    Integer.to_string(rem(n, 900_000) + 100_000)
  end

  defp sign_invite_registration_token(payload) do
    {:ok, %IssuedToken{raw: token}} =
      Tokens.issue(:invite_registration, payload)

    token
  end

  defp verify_invite_registration_token(token) do
    Tokens.verify(:invite_registration, token)
  end

  defp fetch_family(household_id) do
    case Repo.get(Family, household_id) do
      %Family{} = family -> {:ok, family}
      nil -> {:error, :family_not_found}
    end
  end

  defp maybe_put_email_secret(map, email) when not is_binary(email), do: map

  defp maybe_put_email_secret(map, email) do
    normalized = Identity.normalize_email(email)

    fingerprint =
      Identity.email_hash(normalized)
      |> Base.encode16(case: :lower)

    map
    |> Map.put("email_fingerprint", fingerprint)
    |> Map.put("email_ciphertext", Base.encode64(Vault.encrypt!(normalized)))
  end

  defp emit_onboarding_event(action, metadata) do
    :telemetry.execute(
      [:famichat, :auth, :onboarding, action],
      %{count: 1},
      metadata
    )
  end

  defp schedule_direct_conversation_creation(nil, _invitee_id), do: :ok

  defp schedule_direct_conversation_creation(inviter_id, invitee_id)
       when is_binary(inviter_id) and is_binary(invitee_id) do
    # Fire-and-forget: create direct conversation between inviter and invitee
    # without blocking registration. Failures are logged but do not roll back registration.
    Task.Supervisor.start_child(Famichat.TaskSupervisor, fn ->
      case Famichat.Chat.create_direct_conversation(inviter_id, invitee_id) do
        {:ok, _conversation} ->
          :telemetry.execute(
            [:famichat, :auth, :onboarding, :direct_conversation_created],
            %{count: 1},
            %{inviter_id: inviter_id, invitee_id: invitee_id}
          )

        {:error, reason} ->
          require Logger

          Logger.warning(
            "[Onboarding] Failed to create direct conversation: #{inspect(reason)}, inviter=#{inviter_id}, invitee=#{invitee_id}"
          )
      end
    end)

    :ok
  end
end
