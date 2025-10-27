defmodule Famichat.Repo.Migrations.CreateAuthAuditLogs do
  use Ecto.Migration

  def change do
    create table(:auth_audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event, :string, null: false
      add :actor_id, :binary_id
      add :subject_id, :binary_id
      add :household_id, :binary_id
      add :scope, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:auth_audit_logs, [:event, :inserted_at])
    create index(:auth_audit_logs, [:household_id, :inserted_at])
  end
end
