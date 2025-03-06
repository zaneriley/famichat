defmodule Famichat.Repo.Migrations.CreateGroupConversationPrivileges do
  use Ecto.Migration

  def change do
    create table(:group_conversation_privileges, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :granted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :role, :string, null: false
      add :granted_at, :utc_datetime, null: false, default: fragment("NOW()")

      timestamps()
    end

    # Create indexes for performance and constraints
    create unique_index(:group_conversation_privileges, [:conversation_id, :user_id])
    create index(:group_conversation_privileges, [:conversation_id])
    create index(:group_conversation_privileges, [:user_id])
    create index(:group_conversation_privileges, [:granted_by_id])
  end
end
