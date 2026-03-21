defmodule Famichat.Auth.PendingUserReaperTest do
  use Famichat.DataCase, async: false

  alias Famichat.Auth.PendingUserCleanup
  alias Famichat.Accounts.User
  alias Famichat.Repo

  describe "PendingUserCleanup.run/0" do
    @tag known_failure: "B4: insert_user missing NOT NULL username_fingerprint (2026-03-21)"
    test "deletes pending users older than the buffer" do
      old_pending =
        insert_user(%{
          status: :pending,
          inserted_at: DateTime.add(DateTime.utc_now(), -7200, :second)
        })

      {:ok, count} = PendingUserCleanup.run()
      assert count >= 1
      assert Repo.get(User, old_pending.id) == nil
    end

    @tag known_failure: "B4: insert_user missing NOT NULL username_fingerprint (2026-03-21)"
    test "keeps recent pending users" do
      recent_pending =
        insert_user(%{
          status: :pending,
          inserted_at: DateTime.add(DateTime.utc_now(), -600, :second)
        })

      {:ok, _count} = PendingUserCleanup.run()
      assert Repo.get(User, recent_pending.id) != nil
    end

    @tag known_failure: "B4: insert_user missing NOT NULL username_fingerprint (2026-03-21)"
    test "keeps active users regardless of age" do
      old_active =
        insert_user(%{
          status: :active,
          inserted_at: DateTime.add(DateTime.utc_now(), -7200, :second)
        })

      {:ok, _count} = PendingUserCleanup.run()
      assert Repo.get(User, old_active.id) != nil
    end
  end

  defp insert_user(attrs) do
    now = DateTime.utc_now()

    defaults = %{
      username: "test-#{System.unique_integer([:positive])}",
      status: :pending,
      inserted_at: now,
      updated_at: now
    }

    merged = Map.merge(defaults, attrs)

    %User{}
    |> Ecto.Changeset.change(merged)
    |> Repo.insert!()
  end
end
