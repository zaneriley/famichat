defmodule Famichat.Auth.PendingUserReaperTest do
  use Famichat.DataCase, async: false

  alias Famichat.Auth.PendingUserCleanup
  alias Famichat.Accounts.User
  alias Famichat.Repo

  describe "PendingUserCleanup.run/0" do
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

    test "keeps recent pending users" do
      recent_pending =
        insert_user(%{
          status: :pending,
          inserted_at: DateTime.add(DateTime.utc_now(), -600, :second)
        })

      {:ok, _count} = PendingUserCleanup.run()
      assert Repo.get(User, recent_pending.id) != nil
    end

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
    username = "test-#{System.unique_integer([:positive])}"

    defaults = %{
      username: username,
      username_fingerprint: Famichat.Accounts.Username.fingerprint(username),
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
