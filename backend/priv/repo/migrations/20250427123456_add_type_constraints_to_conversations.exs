defmodule Famichat.Repo.Migrations.AddTypeConstraintsToConversations do
  use Ecto.Migration

  def change do
    # Add NOT NULL constraint to conversation_type field
    alter table(:conversations) do
      modify :conversation_type, :string, null: false
    end

    # Add a check constraint to ensure conversation_type is one of the valid types
    create constraint(:conversations, :conversation_type_must_be_valid,
      check: "conversation_type IN ('direct', 'group', 'self', 'letter')")
  end
end
