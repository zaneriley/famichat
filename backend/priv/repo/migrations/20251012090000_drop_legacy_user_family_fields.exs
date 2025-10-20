defmodule Famichat.Repo.Migrations.DropLegacyUserFamilyFields do
  use Ecto.Migration

  def up do
    drop_if_exists index(:users, [:role])
    drop_if_exists index(:users, [:family_id])

    alter table(:users) do
      remove_if_exists :family_id, :binary_id
      remove_if_exists :role, :string
    end
  end

  def down do
    alter table(:users) do
      add :family_id, references(:families, type: :binary_id)
      add :role, :string, null: false, default: "member"
    end

    create index(:users, [:role])
    create index(:users, [:family_id])
  end
end
