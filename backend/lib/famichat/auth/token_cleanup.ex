defmodule Famichat.Auth.TokenCleanup do
  @moduledoc """
  Deletes expired tokens from the `user_tokens` table.

  Tokens have an `expires_at` column (indexed) and are never useful after
  expiry. Without periodic cleanup the table grows unbounded.

  Called by `TokenReaper` on a timer.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Accounts
    ]

  import Ecto.Query

  alias Famichat.Accounts.UserToken
  alias Famichat.Repo

  @spec run() :: {:ok, non_neg_integer()}
  def run do
    now = DateTime.utc_now()

    {count, _} =
      Repo.delete_all(
        from t in UserToken,
          where: t.expires_at < ^now
      )

    :telemetry.execute(
      [:famichat, :auth, :tokens, :expired_cleaned],
      %{count: count},
      %{}
    )

    {:ok, count}
  end
end
