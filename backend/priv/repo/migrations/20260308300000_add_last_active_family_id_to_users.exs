defmodule Famichat.Repo.Migrations.AddLastActiveFamilyIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_active_family_id,
          references(:families, type: :binary_id, on_delete: :nilify_all),
          null: true
    end

    create index(:users, [:last_active_family_id])
  end
end
