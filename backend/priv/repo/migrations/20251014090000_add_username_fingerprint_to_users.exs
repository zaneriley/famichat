defmodule Famichat.Repo.Migrations.AddUsernameFingerprintToUsers do
  use Ecto.Migration

  import Ecto.Query

  alias Famichat.Accounts.Username
  alias Famichat.Repo
  alias MapSet
  require Logger

  defmodule MigrationUser do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: false}
    schema "users" do
      field(:username, :string)
      field(:username_fingerprint, :binary)
    end
  end

  def up do
    alter table(:users) do
      add :username_fingerprint, :binary, null: true
    end

    flush()

    backfill_usernames()

    execute("ALTER TABLE users ALTER COLUMN username_fingerprint SET NOT NULL")

    drop_if_exists(unique_index(:users, [:username]))

    create unique_index(:users, [:username_fingerprint], name: :users_username_fingerprint_index)
  end

  def down do
    drop_if_exists(
      unique_index(:users, [:username_fingerprint], name: :users_username_fingerprint_index)
    )

    create unique_index(:users, [:username], name: :users_username_index)

    alter table(:users) do
      remove :username_fingerprint
    end
  end

  defp backfill_usernames do
    Repo.transaction(fn ->
      users =
        from(u in MigrationUser,
          select: %{id: u.id, username: u.username},
          order_by: [asc: u.id],
          lock: "FOR UPDATE"
        )
        |> Repo.all()

      Enum.reduce(users, MapSet.new(), fn %{id: id, username: username}, assigned ->
        {candidate, fingerprint, updated_assigned, changed?} =
          Username.maybe_suffix(username, assigned)

        attrs = %{
          username: candidate,
          username_fingerprint: fingerprint
        }

        from(u in MigrationUser, where: u.id == ^id)
        |> Repo.update_all(set: attrs)

        if changed? or Username.sanitize(username) != candidate do
          Logger.warning(
            "Adjusted username during fingerprint migration",
            original_username: username,
            adjusted_username: candidate,
            user_id: id
          )
        end

        updated_assigned
      end)
    end)
  end
end
