defmodule Famichat.Auth.Recovery do
  @moduledoc """
  Recovery orchestration: issuing recovery links and enforcing containment when
  a household admin or the user themselves triggers account recovery.
  """

  use Boundary,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Accounts,
      Famichat.Auth.Identity,
      Famichat.Auth.Tokens
    ]

  import Ecto.Query

  alias Famichat.Accounts.{
    HouseholdMembership,
    Passkey,
    User,
    UserDevice,
    UserToken
  }

  alias Famichat.Auth.{Identity, IssuedToken, Tokens}
  alias Famichat.Repo

  @spec issue_recovery(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, String.t(), Famichat.Accounts.UserToken.t()} | {:error, term()}
  def issue_recovery(admin_id, user_id) do
    with {:ok, admin} <- Identity.fetch_user(admin_id),
         {:ok, _target} <- Identity.fetch_user(user_id),
         true <- admin.id == user_id || household_admin?(admin_id, user_id),
         {:ok, %IssuedToken{raw: token, record: %UserToken{} = record}} <-
           Tokens.issue(:recovery, %{"user_id" => user_id}, user_id: admin_id) do
      telemetry(:issue, %{user_id: user_id, admin_id: admin_id})
      {:ok, token, record}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :forbidden}
    end
  end

  @spec redeem_recovery(String.t()) :: {:ok, User.t()} | {:error, term()}
  def redeem_recovery(raw_token) when is_binary(raw_token) do
    Repo.transaction(fn ->
      with {:ok, token} <- Tokens.fetch(:recovery, raw_token),
           {:ok, user} <- Identity.fetch_user(token.payload["user_id"]),
           {:ok, _} <- disable_devices_and_passkeys(user.id),
           {:ok, user} <- Identity.enter_enrollment_required_state(user),
           {:ok, _} <- Tokens.consume(token) do
        telemetry(:redeem, %{user_id: user.id})
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

  ## Helpers -----------------------------------------------------------------

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

  defp telemetry(action, metadata) do
    :telemetry.execute(
      [:famichat, :auth, :recovery, action],
      %{count: 1},
      metadata
    )
  end
end
