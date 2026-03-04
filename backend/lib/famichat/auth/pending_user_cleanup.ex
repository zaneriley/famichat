defmodule Famichat.Auth.PendingUserCleanup do
  @moduledoc """
  Removes users in `status: :pending` whose passkey_registration token has
  expired and who therefore can never complete registration.

  A pending user is created by `Onboarding.complete_registration/2` but only
  activated by `Passkeys.register_passkey/1` after a successful WebAuthn
  ceremony. If the client abandons the ceremony, the user row remains in
  `:pending` status indefinitely without this cleanup.

  A safe TTL buffer of 2x the passkey_registration TTL (20 min default) is
  used to avoid races with in-progress registrations.

  Called from a scheduled job (e.g., a GenServer timer or Oban worker).
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Accounts
    ]

  import Ecto.Query

  alias Famichat.Accounts.User
  alias Famichat.Repo

  # 2x the passkey_registration default TTL (10 min). Gives in-flight
  # registrations a generous window before their pending user is reaped.
  @buffer_seconds 20 * 60

  @spec run() :: {:ok, non_neg_integer()}
  def run do
    cutoff = DateTime.add(DateTime.utc_now(), -@buffer_seconds, :second)

    {count, _} =
      Repo.delete_all(
        from u in User,
          where: u.status == :pending,
          where: u.inserted_at < ^cutoff
      )

    :telemetry.execute(
      [:famichat, :auth, :onboarding, :pending_users_cleaned],
      %{count: count},
      %{}
    )

    {:ok, count}
  end
end
