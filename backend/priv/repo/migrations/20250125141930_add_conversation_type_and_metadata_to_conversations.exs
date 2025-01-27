defmodule Famichat.Repo.Migrations.AddConversationTypeAndMetadataToConversations do
  use Ecto.Migration

  def change do
    create table(:conversation_users) do
      # Explicitly set type to :binary_id
      add :conversation_id, references(:conversations, on_delete: :delete_all, type: :binary_id),
        null: false

      # Explicitly set type to :binary_id
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      timestamps()
    end

    create index(:conversation_users, [:conversation_id, :user_id], unique: true)
    create index(:conversation_users, [:user_id])
  end
end
