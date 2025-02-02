defmodule Famichat.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "member"
      add :family_id, :binary_id, null: false
    end

    create index(:users, [:role])
    create index(:users, [:family_id])
  end
end
