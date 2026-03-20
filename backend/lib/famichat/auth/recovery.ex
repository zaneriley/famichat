defmodule Famichat.Auth.Recovery do
  @moduledoc """
  Recovery orchestration: issuing recovery links and enforcing containment when
  a household admin or the user themselves triggers account recovery.
  """

  use Boundary,
    top_level?: true,
    exports: [],
    deps: [
      Famichat,
      Famichat.Accounts,
      Famichat.Auth.Identity,
      Famichat.Auth.Passkeys,
      Famichat.Auth.Runtime,
      Famichat.Auth.Sessions,
      Famichat.Auth.Tokens
    ]

  import Ecto.Query

  alias Famichat.Accounts.{HouseholdMembership, User, UserToken}

  alias Famichat.Auth.{Identity, Passkeys, Sessions, Tokens}
  alias Famichat.Auth.Tokens.IssuedToken
  alias Famichat.Auth.Runtime.Audit
  alias Famichat.Repo
  require Logger

  @type scope :: :target_user | :household | :global

  @spec issue_recovery(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, String.t(), Famichat.Accounts.UserToken.t()} | {:error, term()}
  def issue_recovery(admin_id, user_id, opts \\ []) do
    scope = opts |> Keyword.get(:scope, :target_user) |> normalize_scope()

    with {:ok, admin} <- Identity.fetch_user(admin_id),
         {:ok, target} <- Identity.fetch_user(user_id),
         {:ok, {resolved_scope, household_id}} <-
           resolve_scope(scope, admin, target),
         {:ok, %IssuedToken{raw: token, record: %UserToken{} = record}} <-
           issue_recovery_token(
             admin.id,
             target.id,
             resolved_scope,
             household_id
           ),
         :ok <-
           telemetry_issue(admin.id, target.id, resolved_scope, household_id),
         :ok <-
           audit_issue(
             admin.id,
             target.id,
             resolved_scope,
             household_id,
             record.id
           ) do
      {:ok, token, record}
    end
  end

  @spec redeem_recovery(String.t()) :: {:ok, User.t()} | {:error, term()}
  def redeem_recovery(raw_token) when is_binary(raw_token) do
    Repo.transaction(fn ->
      with {:ok, token} <- Tokens.fetch(:recovery, raw_token),
           {:ok, user} <- Identity.fetch_user(token.payload["user_id"]),
           {:ok, {scope, household_id}} <- decode_scope(token.payload),
           {:ok, affected_users} <- enforce_scope(scope, user, household_id),
           {:ok, updated_users} <- mark_enrollment_required(affected_users),
           {:ok, _} <- Tokens.consume(token),
           :ok <- telemetry_redeem(scope, household_id, affected_users),
           :ok <-
             audit_redeem(
               token.id,
               scope,
               household_id,
               affected_users
             ) do
        Map.fetch!(updated_users, user.id)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, %User{} = user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Helpers -----------------------------------------------------------------

  defp issue_recovery_token(admin_id, user_id, scope, household_id) do
    payload =
      %{"user_id" => user_id, "scope" => Atom.to_string(scope)}
      |> maybe_put_household(household_id)

    Tokens.issue(:recovery, payload, user_id: admin_id)
  end

  defp telemetry_issue(admin_id, user_id, scope, household_id) do
    telemetry(:issue, %{
      admin_id: admin_id,
      subject_id: user_id,
      household_id: household_id,
      scope: scope
    })

    :ok
  end

  defp telemetry_redeem(scope, household_id, affected_users) do
    telemetry(:redeem, %{
      scope: scope,
      household_id: household_id,
      subject_ids: Enum.map(affected_users, & &1.id)
    })

    :ok
  end

  defp audit_issue(actor_id, subject_id, scope, household_id, token_id) do
    metadata = %{
      token_id: token_id
    }

    Audit.record("recovery.issue", %{
      actor_id: actor_id,
      subject_id: subject_id,
      household_id: household_id,
      scope: scope,
      metadata: metadata
    })
  end

  defp audit_redeem(token_id, scope, household_id, users) do
    Audit.record_many(
      "recovery.redeem",
      Enum.map(users, fn user ->
        %{
          actor_id: user.id,
          subject_id: user.id,
          household_id: household_id,
          scope: scope,
          metadata: %{token_id: token_id}
        }
      end)
    )
  end

  defp mark_enrollment_required(users) do
    Enum.reduce_while(users, {:ok, %{}}, fn user, {:ok, acc} ->
      case Identity.enter_enrollment_required_state(user) do
        {:ok, updated} -> {:cont, {:ok, Map.put(acc, user.id, updated)}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp enforce_scope(:target_user, user, _household_id) do
    Sessions.revoke_all_for_user(user.id)
    Passkeys.disable_all_for_user(user.id)
    {:ok, [user]}
  end

  defp enforce_scope(:household, _user, household_id) do
    member_ids = household_member_ids(household_id)

    Enum.each(member_ids, &Sessions.revoke_all_for_user/1)
    Passkeys.disable_all_for_users(member_ids)

    users =
      from(u in User, where: u.id in ^member_ids)
      |> Repo.all()

    {:ok, users}
  end

  defp enforce_scope(:global, _user, _household_id),
    do: {:error, :unsupported_scope}

  defp decode_scope(payload) do
    scope =
      payload
      |> Map.get("scope", "target_user")
      |> normalize_scope()

    household_id = Map.get(payload, "household_id")

    case scope do
      :target_user -> {:ok, {scope, household_id}}
      :household when is_binary(household_id) -> {:ok, {scope, household_id}}
      :household -> {:error, :missing_household}
      :global -> {:error, :unsupported_scope}
      _ -> {:error, :invalid_scope}
    end
  end

  defp resolve_scope(:target_user, admin, target) do
    cond do
      admin.id == target.id ->
        {:ok, {:target_user, nil}}

      household_admin?(admin.id, target.id) ->
        {:ok, {:target_user, nil}}

      true ->
        {:error, :forbidden}
    end
  end

  defp resolve_scope(:household, admin, target) do
    case shared_admin_households(admin.id, target.id) do
      [household_id] -> {:ok, {:household, household_id}}
      [] -> {:error, :forbidden}
      _ -> {:error, :ambiguous_household}
    end
  end

  defp resolve_scope(:global, _admin, _target), do: {:error, :unsupported_scope}
  defp resolve_scope(_other, _admin, _target), do: {:error, :invalid_scope}

  defp normalize_scope(scope) when is_atom(scope), do: scope

  defp normalize_scope(scope) when is_binary(scope) do
    scope
    |> String.trim()
    |> String.downcase()
    |> String.to_existing_atom()
  rescue
    ArgumentError -> :invalid_scope
  end

  defp maybe_put_household(payload, nil), do: payload

  defp maybe_put_household(payload, household_id),
    do: Map.put(payload, "household_id", household_id)

  defp household_admin?(admin_id, target_user_id) do
    query =
      from admin in HouseholdMembership,
        where: admin.user_id == ^admin_id and admin.role == :admin,
        join: target in HouseholdMembership,
        on:
          target.family_id == admin.family_id and
            target.user_id == ^target_user_id,
        select: true,
        limit: 1

    Repo.exists?(query)
  end

  defp shared_admin_households(admin_id, target_user_id) do
    from(admin in HouseholdMembership,
      where: admin.user_id == ^admin_id and admin.role == :admin,
      join: target in HouseholdMembership,
      on:
        target.family_id == admin.family_id and
          target.user_id == ^target_user_id,
      select: admin.family_id,
      distinct: true
    )
    |> Repo.all()
  end

  defp household_member_ids(household_id) do
    from(m in HouseholdMembership,
      where: m.family_id == ^household_id,
      select: m.user_id
    )
    |> Repo.all()
  end

  defp telemetry(action, metadata) do
    :telemetry.execute(
      [:famichat, :auth, :recovery, action],
      %{count: 1},
      metadata
    )
  end
end
