defmodule Famichat.Repo.Migrations.CreateCommunitiesAndScopeExistingRows do
  use Ecto.Migration

  @default_community_id "00000000-0000-0000-0000-000000000001"
  @default_community_name "Famichat Community"

  def up do
    create table(:communities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :settings, :map, default: fragment("'{}'::jsonb"), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:communities, [:name])

    execute("""
    INSERT INTO communities (id, name, settings, inserted_at, updated_at)
    VALUES (
      '#{@default_community_id}',
      '#{@default_community_name}',
      '{}'::jsonb,
      timezone('utc', now()),
      timezone('utc', now())
    )
    ON CONFLICT (id) DO NOTHING
    """)

    alter table(:users) do
      add :community_id,
          references(:communities, type: :binary_id, on_delete: :restrict),
          default: @default_community_id,
          null: false
    end

    alter table(:families) do
      add :community_id,
          references(:communities, type: :binary_id, on_delete: :restrict),
          default: @default_community_id,
          null: false
    end

    alter table(:conversations) do
      add :community_id,
          references(:communities, type: :binary_id, on_delete: :restrict),
          default: @default_community_id,
          null: false
    end

    alter table(:auth_audit_logs) do
      add :community_id,
          references(:communities, type: :binary_id, on_delete: :restrict),
          default: @default_community_id,
          null: false
    end

    execute(
      "UPDATE users SET community_id = '#{@default_community_id}' WHERE community_id IS NULL"
    )

    execute(
      "UPDATE families SET community_id = '#{@default_community_id}' WHERE community_id IS NULL"
    )

    execute(
      "UPDATE conversations SET community_id = '#{@default_community_id}' WHERE community_id IS NULL"
    )

    execute(
      "UPDATE auth_audit_logs SET community_id = '#{@default_community_id}' WHERE community_id IS NULL"
    )

    create index(:users, [:community_id])
    create index(:families, [:community_id])
    create index(:conversations, [:community_id])
    create index(:auth_audit_logs, [:community_id, :inserted_at])
  end

  def down do
    drop index(:auth_audit_logs, [:community_id, :inserted_at])
    drop index(:conversations, [:community_id])
    drop index(:families, [:community_id])
    drop index(:users, [:community_id])

    alter table(:auth_audit_logs) do
      remove :community_id
    end

    alter table(:conversations) do
      remove :community_id
    end

    alter table(:families) do
      remove :community_id
    end

    alter table(:users) do
      remove :community_id
    end

    drop index(:communities, [:name])
    drop table(:communities)
  end
end
