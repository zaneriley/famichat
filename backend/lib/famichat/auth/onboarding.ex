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
      Famichat.Auth.Passkeys,
      Famichat.Auth.RateLimit,
      Famichat.Auth.Runtime,
      Famichat.Auth.Tokens
    ]

  import Ecto.Query, only: [from: 2]

  alias Famichat.Accounts.User
  alias Famichat.Auth.Households
  alias Famichat.Auth.Identity
  alias Famichat.Auth.Passkeys
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
  @self_service_bucket :"family.self_service"
  @passkey_reissue_bucket :"passkey.reissue"

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

  @spec issue_invite_validated(Ecto.UUID.t(), map()) ::
          {:ok, %{invite: String.t(), qr: String.t(), admin_code: String.t()}}
          | {:error, term()}
  def issue_invite_validated(inviter_id, params)
      when is_binary(inviter_id) and is_map(params) do
    household_id = household_id_from_payload(params)
    role = Map.get(params, "role") || Map.get(params, :role) || "member"
    email = Map.get(params, "email") || Map.get(params, :email)

    with {:ok, normalized_household_id} <- validate_household_id(household_id) do
      issue_invite(inviter_id, email, %{
        household_id: normalized_household_id,
        role: role
      })
    end
  end

  def issue_invite_validated(_, _), do: {:error, :invalid_parameters}

  @spec bootstrap_admin(String.t(), map()) ::
          {:ok,
           %{
             user: User.t(),
             family: Famichat.Chat.Family.t(),
             passkey_register_token: String.t()
           }}
          | {:error, :admin_exists}
          | {:error, :invalid_input}
          | {:error, :username_required}
          | {:error, Ecto.Changeset.t()}
  def bootstrap_admin(username, opts \\ %{}) do
    with {:ok, normalized_username} <- validate_bootstrap_username(username) do
      family_name =
        Map.get(opts, :family_name) || Map.get(opts, "family_name") ||
          "My Family"

      # Advisory lock key for serializing concurrent bootstrap_admin/2 calls.
      # Value 4210637 = 0x404D4D = "ADM" in ASCII.
      advisory_lock_key = 4_210_637

      result =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:lock, fn repo, _changes ->
          repo.query!("SELECT pg_advisory_xact_lock($1)", [advisory_lock_key])
          {:ok, :locked}
        end)
        |> Ecto.Multi.run(:check_admin, fn repo, _changes ->
          count = repo.one(from u in User, select: count(u.id))

          if count > 0 do
            {:error, :admin_exists}
          else
            {:ok, :no_admin}
          end
        end)
        |> Ecto.Multi.insert(
          :family,
          Famichat.Chat.Family.changeset(%Famichat.Chat.Family{}, %{
            name: family_name
          })
        )
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
        |> Ecto.Multi.run(:membership, fn _repo,
                                          %{user: user, family: family} ->
          Households.add_member(family.id, user.id, :admin)
        end)
        |> Ecto.Multi.run(:passkey_token, fn _repo, %{user: user} ->
          Tokens.issue(:passkey_registration, %{"user_id" => user.id},
            user_id: user.id
          )
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{user: user, family: family, passkey_token: %IssuedToken{raw: register_token}}} ->
          :telemetry.execute(
            [:famichat, :auth, :onboarding, :bootstrap_admin_created],
            %{count: 1},
            %{user_id: user.id, family_id: family.id}
          )

          {:ok,
           %{user: user, family: family, passkey_register_token: register_token}}

        {:error, :check_admin, :admin_exists, _} ->
          {:error, :admin_exists}

        {:error, _step, %Ecto.Changeset{} = changeset, _} ->
          {:error, changeset}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Creates a new family via self-service (no authenticated admin required) and
  issues a `:family_setup` token so the caller can proceed to user registration
  and passkey setup.

  Rate-limited to 3 creations per hour per IP address.

  ## Parameters

    - `family_name` — string, 1-100 chars. Blank or nil returns `{:error, :family_name_required}`.
    - `opts` — map with optional `:remote_ip` key (string) used as rate-limit key.

  ## Returns

    - `{:ok, %{family: Family.t(), setup_token: String.t()}}` on success.
    - `{:error, :family_name_required}` if family_name is blank after trimming.
    - `{:error, :family_name_too_long}` if family_name exceeds 100 chars.
    - `{:error, {:rate_limited, pos_integer()}}` if IP rate limit exceeded.
    - `{:error, Ecto.Changeset.t()}` on family insertion failure (e.g. name taken).
    - `{:error, term()}` on unexpected error.
  """
  @spec create_family_self_service(String.t() | nil, map()) ::
          {:ok, %{family: Family.t(), setup_token: String.t()}}
          | {:error,
             :family_name_required
             | :family_name_too_long
             | {:rate_limited, pos_integer()}
             | Ecto.Changeset.t()
             | term()}
  def create_family_self_service(family_name, opts \\ %{}) do
    name = if is_binary(family_name), do: String.trim(family_name), else: ""
    rate_key = Map.get(opts, :remote_ip) || Map.get(opts, "remote_ip") || "unknown"

    with {:ok, normalized_name} <- validate_family_name(name),
         :ok <-
           RateLimit.check(@self_service_bucket, rate_key,
             limit: 10,
             interval: 3600
           ) do
      community_id = Famichat.Accounts.CommunityScope.default_id()

      result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(
          :family,
          Family.changeset(%Family{}, %{
            name: normalized_name,
            community_id: community_id
          })
        )
        |> Ecto.Multi.run(:setup_token, fn _repo, %{family: family} ->
          Tokens.issue(:family_setup, %{
            "family_id" => family.id,
            "family_name" => family.name,
            "issued_by" => "self_service",
            "community_id" => community_id,
            "intended_role" => "admin"
          })
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{family: family, setup_token: %IssuedToken{raw: raw_token}}} ->
          :telemetry.execute(
            [:famichat, :auth, :onboarding, :family_self_service_created],
            %{count: 1},
            %{family_id: family.id, community_id: community_id}
          )

          {:ok, %{family: family, setup_token: raw_token}}

        {:error, :family, %Ecto.Changeset{} = changeset, _} ->
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

      String.length(normalized) < 1 ->
        {:error, :invalid_input}

      true ->
        {:ok, normalized}
    end
  end

  defp validate_bootstrap_username(nil), do: {:error, :username_required}
  defp validate_bootstrap_username(_), do: {:error, :invalid_input}

  defp validate_household_id(nil), do: {:error, :missing_household_id}

  defp validate_household_id(household_id) do
    case Ecto.UUID.cast(household_id) do
      {:ok, normalized_household_id} -> {:ok, normalized_household_id}
      :error -> {:error, :invalid_household_id}
    end
  end

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
      payload =
        invite.payload
        |> sanitize_invite_payload()
        |> maybe_put_inviter_username(Map.get(invite.payload, "inviter_id"))

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
          {:ok, map(), String.t()}
          | {:error, :invalid | :expired | :reinvite_needed}
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
        cond do
          DateTime.compare(expires_at, DateTime.utc_now()) == :lt ->
            {:error, :expired}

          invite_already_completed?(token.id) ->
            {:error, :already_completed}

          true ->
            payload =
              token.payload
              |> sanitize_invite_payload()
              |> maybe_put_inviter_username(Map.get(token.payload, "inviter_id"))

            reg_token_result =
              sign_invite_registration_token(%{
                "invite_token_id" => token.id,
                "family_id" =>
                  token.payload["household_id"] || token.payload["family_id"],
                "role" => token.payload["role"],
                "email_ciphertext" => Map.get(token.payload, "email_ciphertext"),
                "email_fingerprint" =>
                  Map.get(token.payload, "email_fingerprint"),
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
         :ok <- assert_token_kind(invite, "invite"),
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
          | {:error, :used_registration_token}
          | {:error, :invalid_registration}
          | {:error, {:rate_limited, pos_integer()}}
          | {:error, :email_required}
          | {:error, :email_mismatch}
          | {:error, :family_not_found}
          | {:error, :username_taken}
          | {:error, Ecto.Changeset.t()}
  def complete_registration(registration_token, attrs)
      when is_binary(registration_token) and is_map(attrs) do
    with {:fetch, {:ok, reg_token_record}} <-
           {:fetch, Tokens.fetch(:invite_registration, registration_token)},
         claims <- reg_token_record.payload,
         rate_key <- claims["invite_token_id"] || registration_token,
         :ok <-
           RateLimit.check(@invite_complete_bucket, rate_key,
             limit: 5,
             interval: Tokens.default_ttl(:invite_registration)
           ) do
      case Repo.transaction(fn ->
             # Consume the registration token inside the transaction so that
             # a concurrent request with the same token either wins the consume
             # or sees {:error, :used} from the fetch above (after commit).
             with {:ok, _} <- Tokens.consume(reg_token_record),
                  {:ok, family} <-
                    fetch_family(claims["household_id"] || claims["family_id"]),
                  {:ok, user} <-
                    find_or_create_pending_user(
                      claims,
                      attrs,
                      reg_token_record.id
                    ),
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
      {:fetch, {:error, :invalid}} ->
        {:error, :invalid_registration_token}

      {:fetch, {:error, :expired}} ->
        {:error, :expired_registration_token}

      {:fetch, {:error, :used}} ->
        {:error, :used_registration_token}

      {:error, {:rate_limited, retry_in}} ->
        {:error, {:rate_limited, retry_in}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def complete_registration(_, _), do: {:error, :invalid_registration}

  @doc """
  Re-issues a `passkey_registration` token for an existing user who does not
  yet have an active passkey.

  This is the retry path when the original `passkey_registration` token was
  consumed by a failed challenge fetch and the user needs a fresh token to
  attempt registration again.

  Returns `{:ok, raw_token}` on success.

  Returns `{:error, :user_not_found}` if no user with the given `user_id` exists.

  Returns `{:error, :invalid_user_state}` if the user's status is not `:active`
  or `:pending` (e.g. the account is locked or deleted).

  Returns `{:error, :already_registered}` if the user already has at least one
  active (non-revoked) passkey — there is no reason to re-issue a registration
  token in that case.
  """
  @spec reissue_passkey_token(Ecto.UUID.t()) ::
          {:ok, String.t()}
          | {:error,
             :user_not_found | :already_registered | :invalid_user_state}
  def reissue_passkey_token(user_id) do
    with :ok <- RateLimit.check(@passkey_reissue_bucket, user_id, limit: 5, interval: 300),
         {:ok, user} <- Identity.fetch_user(user_id),
         :ok <- assert_reissuable_user_state(user),
         :ok <- assert_no_active_passkey(user_id),
         {:ok, %IssuedToken{raw: register_token}} <-
           Tokens.issue(:passkey_registration, %{"user_id" => user_id},
             user_id: user_id
           ) do
      {:ok, register_token}
    end
  end

  @doc """
  Detects the "setup incomplete" state: exactly one user exists in the DB,
  that user has no active (non-revoked) passkey, and that user has at least
  one household membership (i.e. was created by bootstrap_admin/2).

  Returns `{:ok, user, family}` when re-entry is appropriate.
  Returns `{:error, :not_found}` in all other cases.

  Used exclusively by SetupLive to gate passkey-ceremony re-entry when the
  admin navigates back to /setup after an interrupted ceremony.
  """
  @spec fetch_incomplete_bootstrap() ::
          {:ok, User.t(), Family.t()} | {:error, :not_found}
  def fetch_incomplete_bootstrap do
    count = Repo.one(from(u in User, select: count(u.id)))

    with 1 <- count,
         %User{} = user <-
           Repo.one(from(u in User, limit: 1))
           |> Repo.preload(memberships: :family),
         false <- Passkeys.has_active_passkey?(user.id),
         [%{family: %Family{} = family} | _] <- user.memberships do
      {:ok, user, family}
    else
      _ -> {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # Family Setup (post-bootstrap family creation)
  # ---------------------------------------------------------------------------

  @family_create_bucket :"family.create"
  @family_setup_complete_bucket :"family_setup.complete"
  @family_setup_reissue_bucket :"family_setup.reissue"

  @doc """
  Creates a new family and issues a one-time setup link that the designated
  first household admin can use to register their account.

  This is the post-bootstrap path for community admins creating additional
  families on the deployment. It is intentionally separate from
  `bootstrap_admin/2`, which is a one-shot first-run path.

  The community admin who calls this function becomes the *issuer* of the
  setup link, not a member of the new family.

  ## Parameters

    - `community_admin_id` — UUID of the authenticated community admin user.
      Must have at least one `:admin` household membership (MLP check).
    - `family_name` — string, 1-100 chars. Will be the family's display name.
    - `opts` — optional map. Currently unused; reserved for future extension.

  ## Returns

    - `{:ok, %{family: Family.t(), setup_url_token: String.t()}}` on success.
    - `{:error, :not_community_admin}` if the caller lacks community admin role.
    - `{:error, :family_name_required}` if family_name is blank.
    - `{:error, :family_name_too_long}` if family_name exceeds 100 chars.
    - `{:error, Ecto.Changeset.t()}` on family insertion failure.
    - `{:error, term()}` on unexpected error.
  """
  @spec create_family_with_setup_link(Ecto.UUID.t(), String.t(), map()) ::
          {:ok, %{family: Family.t(), setup_url_token: String.t()}}
          | {:error,
             :not_community_admin
             | :family_name_required
             | :family_name_too_long
             | Ecto.Changeset.t()
             | term()}
  def create_family_with_setup_link(community_admin_id, family_name, _opts \\ %{}) do
    with {:ok, normalized_name} <- validate_family_name(family_name),
         {:ok, _admin_user} <- assert_community_admin(community_admin_id),
         :ok <-
           RateLimit.check(@family_create_bucket, community_admin_id,
             limit: 5,
             interval: 3600
           ) do
      community_id = Famichat.Accounts.CommunityScope.default_id()

      result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(
          :family,
          Family.changeset(%Family{}, %{
            name: normalized_name,
            community_id: community_id
          })
        )
        |> Ecto.Multi.run(:setup_token, fn _repo, %{family: family} ->
          Tokens.issue(:family_setup, %{
            "family_id" => family.id,
            "family_name" => family.name,
            "issued_by" => community_admin_id,
            "community_id" => community_id,
            "intended_role" => "admin"
          })
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{family: family, setup_token: %IssuedToken{raw: raw_token}}} ->
          :telemetry.execute(
            [:famichat, :auth, :onboarding, :family_created],
            %{count: 1},
            %{
              family_id: family.id,
              community_admin_id: community_admin_id,
              community_id: community_id
            }
          )

          {:ok, %{family: family, setup_url_token: raw_token}}

        {:error, :family, %Ecto.Changeset{} = changeset, _} ->
          {:error, changeset}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Validates a family setup token without consuming it.

  Returns `{:ok, payload}` if the token exists and is valid (not expired, not used).
  Returns `{:error, :invalid}`, `{:error, :expired}`, or `{:error, :used}`
  for invalid tokens.

  Used by `FamichatWeb.Plugs.ValidateFamilySetupToken` to gate the family
  setup route at the HTTP layer before the LiveView mounts.
  """
  @spec validate_family_setup_token(String.t()) ::
          {:ok, map()} | {:error, :invalid | :expired | :used}
  def validate_family_setup_token(raw_token) when is_binary(raw_token) do
    case Tokens.fetch(:family_setup, raw_token) do
      {:ok, token} -> {:ok, token.payload}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches the payload of a family setup token without consuming it.

  Used by `FamilySetupLive` to recover state on WebSocket reconnect after
  the token has already been consumed by `complete_family_setup/2`.

  Returns `{:ok, result}` even if `used_at` is set, as long as the token
  exists and has not expired. The result map always contains `:payload`.
  If a pending user was already created for this token, the result also
  contains `:user` and `:passkey_register_token`.

  Returns `{:error, :invalid}` if the token does not exist.
  Returns `{:error, :expired}` if the token has expired.
  Returns `{:error, :already_completed}` if the family setup has been
  fully completed (user has an active passkey).
  """
  @spec peek_family_setup(String.t()) ::
          {:ok, map()} | {:error, :invalid | :expired | :already_completed}
  def peek_family_setup(raw_token) when is_binary(raw_token) do
    hash = TokenStorage.hash(raw_token)
    context = Tokens.Policy.legacy_context(:family_setup)

    case Repo.get_by(Famichat.Accounts.UserToken,
           context: context,
           token_hash: hash
         ) do
      nil ->
        {:error, :invalid}

      %Famichat.Accounts.UserToken{expires_at: expires_at} = token ->
        cond do
          DateTime.compare(expires_at, DateTime.utc_now()) == :lt ->
            {:error, :expired}

          family_setup_already_completed?(token.payload) ->
            {:error, :already_completed}

          true ->
            # Check if a pending user was already created for this token
            pending_user = Repo.get_by(User, registration_token_id: token.id)

            result = %{payload: token.payload}

            result =
              if pending_user do
                # Re-issue passkey registration token for the pending user
                case reissue_passkey_token(pending_user.id) do
                  {:ok, passkey_token} ->
                    Map.merge(result, %{
                      user: pending_user,
                      passkey_register_token: passkey_token
                    })

                  {:error, :already_registered} ->
                    # Passkey exists but family_setup_already_completed? returned
                    # false — edge case, treat as completed.
                    nil

                  {:error, _} ->
                    result
                end
              else
                result
              end

            if result, do: {:ok, result}, else: {:error, :already_completed}
        end
    end
  end

  @doc """
  Completes a family setup link redemption: creates the user account,
  adds them as a household admin of the pre-created family, and issues
  a passkey_registration token so they can complete the WebAuthn ceremony.

  This is analogous to `complete_registration/2` for the invite flow but
  operates on a `:family_setup` token instead of an `:invite_registration`
  token.

  The `:family_setup` token is consumed inside the transaction to prevent
  duplicate redemptions.
  """
  @spec complete_family_setup(String.t(), map()) ::
          {:ok, %{user: User.t(), passkey_register_token: String.t()}}
          | {:error,
             :invalid_setup_token
             | :expired_setup_token
             | :used_setup_token
             | :family_not_found
             | :username_required
             | :username_taken
             | Ecto.Changeset.t()
             | term()}
  def complete_family_setup(setup_token, attrs)
      when is_binary(setup_token) and is_map(attrs) do
    with {:fetch, {:ok, token_record}} <-
           {:fetch, Tokens.fetch(:family_setup, setup_token)},
         claims <- token_record.payload,
         :ok <-
           RateLimit.check(
             @family_setup_complete_bucket,
             setup_token,
             limit: 3,
             interval: Tokens.default_ttl(:family_setup)
           ) do
      case Repo.transaction(fn ->
             with {:ok, _} <- Tokens.consume(token_record),
                  {:ok, family} <- fetch_family(claims["family_id"]),
                  {:ok, user} <-
                    create_pending_family_admin(claims, attrs, token_record.id),
                  {:ok, _membership} <-
                    Households.add_member(family.id, user.id, :admin),
                  {:ok, %IssuedToken{raw: register_token}} <-
                    Tokens.issue(:passkey_registration, %{"user_id" => user.id},
                      user_id: user.id
                    ) do
               emit_onboarding_event(:family_setup_completed, %{
                 family_id: family.id,
                 user_id: user.id
               })

               %{user: user, passkey_register_token: register_token}
             else
               {:error, reason} -> Repo.rollback(reason)
             end
           end) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    else
      {:fetch, {:error, :invalid}} -> {:error, :invalid_setup_token}
      {:fetch, {:error, :expired}} -> {:error, :expired_setup_token}
      {:fetch, {:error, :used}} -> {:error, :used_setup_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def complete_family_setup(_, _), do: {:error, :invalid_setup_token}

  @doc """
  Issues a new `:family_setup` token for an existing family. Used by the
  admin panel to re-send a setup link when the original has expired or been
  revoked, without creating a duplicate family.
  """
  @spec issue_family_setup_link_for_existing_family(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, %{setup_url_token: String.t()}}
          | {:error, :not_community_admin | :family_not_found | term()}
  def issue_family_setup_link_for_existing_family(community_admin_id, family_id) do
    with {:ok, _admin} <- assert_community_admin(community_admin_id),
         {:ok, family} <- fetch_family(family_id),
         :ok <-
           RateLimit.check(@family_setup_reissue_bucket, community_admin_id,
             limit: 5,
             interval: 3600
           ) do
      community_id = Famichat.Accounts.CommunityScope.default_id()

      case Tokens.issue(:family_setup, %{
             "family_id" => family.id,
             "family_name" => family.name,
             "issued_by" => community_admin_id,
             "community_id" => community_id,
             "intended_role" => "admin"
           }) do
        {:ok, %IssuedToken{raw: raw_token}} ->
          {:ok, %{setup_url_token: raw_token}}

        error ->
          error
      end
    end
  end

  ## Helpers ----------------------------------------------------------------

  defp assert_reissuable_user_state(%User{status: status})
       when status in [:active, :pending],
       do: :ok

  defp assert_reissuable_user_state(%User{}), do: {:error, :invalid_user_state}

  defp assert_no_active_passkey(user_id) do
    if Passkeys.has_active_passkey?(user_id),
      do: {:error, :already_registered},
      else: :ok
  end

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

  defp invite_already_completed?(invite_token_id) do
    alias Famichat.Accounts.UserToken

    Repo.exists?(
      from u in User,
        join: rt in UserToken,
        on: u.registration_token_id == rt.id,
        where:
          rt.context == "invite_registration" and
            fragment("?->>'invite_token_id' = ?", rt.payload, ^invite_token_id) and
            u.status == :active
    )
  end

  defp sanitize_invite_payload(payload) do
    payload
    |> Map.put_new("household_id", Map.get(payload, "family_id"))
    |> Map.take(["household_id", "role", "email_fingerprint"])
    |> Map.put("email_present", Map.has_key?(payload, "email_ciphertext"))
  end

  defp maybe_put_inviter_username(payload, nil), do: payload

  defp maybe_put_inviter_username(payload, inviter_id)
       when is_binary(inviter_id) do
    case Identity.fetch_user(inviter_id) do
      {:ok, %{username: username}} when is_binary(username) ->
        Map.put(payload, "inviter_username", username)

      _ ->
        payload
    end
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

  # Find an existing pending user tied to this registration token id, or create
  # a new one. This makes complete_registration idempotent on the user-creation
  # step: if a previous attempt inserted a pending user but the passkey step
  # never completed, the same registration token (re-issued by peek_invite) can
  # be used to reach the same pending user rather than colliding on username
  # uniqueness.
  #
  # NOTE: a pending user is only reachable via the passkey registration path.
  # It cannot log in, cannot be discovered by username lookup in auth flows,
  # and will be cleaned up by the pending-user expiry job.
  defp find_or_create_pending_user(claims, attrs, registration_token_id) do
    case Repo.get_by(User, registration_token_id: registration_token_id) do
      %User{} = existing_pending ->
        {:ok, existing_pending}

      nil ->
        create_pending_user_from_invite(claims, attrs, registration_token_id)
    end
  end

  defp create_pending_user_from_invite(claims, attrs, registration_token_id) do
    email =
      Map.get(attrs, "email") ||
        Map.get(attrs, :email) ||
        maybe_email_from_claims(claims)

    with :ok <- assert_invite_email_match(claims, email) do
      user_attrs =
        attrs
        |> Identity.permit_user_attrs()
        |> Map.put(:status, :pending)
        |> Map.put(:email, email)
        |> Map.put(:registration_token_id, registration_token_id)

      # Note: confirmed_at is NOT set here. It is set in maybe_activate_pending_user/1
      # inside passkeys.ex after passkey registration succeeds.
      %User{}
      |> User.changeset(user_attrs)
      |> Repo.insert()
      |> case do
        {:ok, user} ->
          {:ok, user}

        {:error, %Ecto.Changeset{} = cs} ->
          if username_taken?(cs) do
            {:error, :username_taken}
          else
            {:error, cs}
          end
      end
    end
  end

  defp username_taken?(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {_msg, opts} -> opts end)
    |> Map.get(:username, [])
    |> Enum.any?(&(Keyword.get(&1, :constraint) == :unique))
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

  # Asserts that a fetched token record has the expected kind.
  # Guards against token substitution when fetching by ID.
  defp assert_token_kind(%{context: context}, expected_kind)
       when is_binary(expected_kind) do
    if context == expected_kind, do: :ok, else: {:error, :invalid}
  end

  defp assert_token_kind(%{kind: kind}, expected_kind)
       when is_binary(expected_kind) do
    if kind == expected_kind, do: :ok, else: {:error, :invalid}
  end

  defp assert_token_kind(_, _), do: {:error, :invalid}

  # -- Family setup helpers --------------------------------------------------

  defp family_setup_already_completed?(%{"family_id" => family_id}) do
    alias Famichat.Accounts.HouseholdMembership
    alias Famichat.Accounts.Passkey

    Repo.exists?(
      from m in HouseholdMembership,
        join: u in User, on: u.id == m.user_id,
        join: p in Passkey, on: p.user_id == u.id,
        where:
          m.family_id == ^family_id and
            m.role == :admin and
            is_nil(p.revoked_at)
    )
  end

  defp family_setup_already_completed?(_), do: false

  defp validate_family_name(name) when is_binary(name) do
    normalized = String.trim(name)

    cond do
      normalized == "" -> {:error, :family_name_required}
      String.length(normalized) > 100 -> {:error, :family_name_too_long}
      true -> {:ok, normalized}
    end
  end

  defp validate_family_name(_), do: {:error, :family_name_required}

  # For MLP: community admin = user with at least one household admin
  # membership. A formal community_admin role column on users is a future
  # hardening step for L3.
  defp assert_community_admin(user_id) do
    alias Famichat.Accounts.HouseholdMembership

    case Identity.fetch_user(user_id) do
      {:ok, %User{status: :active} = user} ->
        has_any_admin =
          Repo.exists?(
            from(m in HouseholdMembership,
              where: m.user_id == ^user_id and m.role == :admin
            )
          )

        if has_any_admin do
          {:ok, user}
        else
          {:error, :not_community_admin}
        end

      {:ok, _user} ->
        {:error, :not_community_admin}

      error ->
        error
    end
  end

  defp create_pending_family_admin(claims, attrs, token_id) do
    username =
      Map.get(attrs, "username") || Map.get(attrs, :username)

    case validate_bootstrap_username(username) do
      {:error, reason} ->
        {:error, reason}

      {:ok, normalized} ->
        user_attrs = %{
          username: normalized,
          status: :pending,
          registration_token_id: token_id,
          community_id:
            claims["community_id"] ||
              Famichat.Accounts.CommunityScope.default_id()
        }

        %User{}
        |> User.changeset(user_attrs)
        |> Repo.insert()
        |> case do
          {:ok, user} ->
            {:ok, user}

          {:error, %Ecto.Changeset{} = cs} ->
            if username_taken?(cs), do: {:error, :username_taken}, else: {:error, cs}
        end
    end
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
