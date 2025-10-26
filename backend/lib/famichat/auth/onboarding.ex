defmodule Famichat.Auth.Onboarding do
  @moduledoc """
  Invite, pairing, and registration orchestration for households.
  """

  use Boundary,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Accounts,
      Famichat.Auth.Households,
      Famichat.Auth.Identity,
      Famichat.Auth.Runtime,
      Famichat.Auth.RateLimit,
      Famichat.Auth.Tokens
    ]

  alias Famichat.Accounts.User
  alias Famichat.Auth.Households
  alias Famichat.Auth.Identity
  alias Famichat.Auth.Runtime.Instrumentation
  alias Famichat.Auth.RateLimit
  alias Famichat.Auth.Tokens
  alias Famichat.Auth.Tokens.Storage, as: TokenStorage
  alias Famichat.Auth.IssuedToken
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

  defp do_issue_invite(inviter_id, email, payload, household_id) do
    Repo.transaction(fn ->
      with {:ok, inviter} <- Identity.fetch_user(inviter_id),
           {:ok, _membership} <-
             Households.ensure_admin_membership(inviter.id, household_id),
           {:ok, _family} <- fetch_family(household_id),
           payload_map <- invite_payload(payload, email),
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
          "email_fingerprint" => Map.get(invite.payload, "email_fingerprint")
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
          | {:error, term()}
  def complete_registration(registration_token, attrs)
      when is_binary(registration_token) and is_map(attrs) do
    with {:ok, claims} <- verify_invite_registration_token(registration_token),
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
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def complete_registration(_, _), do: {:error, :invalid_registration}

  ## Helpers ----------------------------------------------------------------

  defp invite_payload(payload, email) do
    household_id = household_id_from_payload(payload)

    %{
      "household_id" => household_id,
      "family_id" => household_id,
      "role" => format_role(payload[:role] || payload["role"])
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
    :rand.uniform(999_999)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
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
end
