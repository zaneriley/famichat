defmodule Famichat.Repo.Migrations.AddMessagesConversationPaginationIndex do
  use Ecto.Migration

  def change do
    create index(:messages, [:conversation_id, :inserted_at, :id],
             name: :messages_conversation_id_inserted_at_id
           )
  end
end
