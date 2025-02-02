defmodule Famichat.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    IO.puts("Migration: CreateConversations - Starting table creation...")
    # Specify primary_key: false for custom primary key if needed, or remove if default is ok.
    create table(:conversations, primary_key: false) do
      IO.puts("Migration: CreateConversations - Creating table structure...")
      # Add primary key if needed, binary_id is a good choice
      add :id, :binary_id, primary_key: true
      IO.puts("Migration: CreateConversations - Added column: id")

      IO.puts("Migration: CreateConversations - Adding column: family_id...")
      add :family_id, :binary_id, null: false
      IO.puts("Migration: CreateConversations - Added column: family_id")

      IO.puts("Migration: CreateConversations - Adding column: conversation_type...")
      add :conversation_type, :string, null: false, default: "direct"
      IO.puts("Migration: CreateConversations - Added column: conversation_type")

      IO.puts("Migration: CreateConversations - Adding column: metadata...")
      add :metadata, :map, null: false, default: "{}"
      IO.puts("Migration: CreateConversations - Added column: metadata")

      # Correct # Keep timestamps type consistent
      timestamps(type: :utc_datetime_usec)
      IO.puts("Migration: CreateConversations - Added timestamps (inserted_at, updated_at)")
    end

    IO.puts("Migration: CreateConversations - Table 'conversations' created.")

    IO.puts("Migration: CreateConversations - Creating index on family_id...")
    create index(:conversations, [:family_id])
    IO.puts("Migration: CreateConversations - Index on family_id created.")

    IO.puts("Migration: CreateConversations - Creating index on conversation_type...")
    create index(:conversations, [:conversation_type])
    IO.puts("Migration: CreateConversations - Index on conversation_type created.")

    # Create the conversation_users join table
    create table(:conversation_users, primary_key: false) do
      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:conversation_users, [:conversation_id, :user_id])
    create index(:conversation_users, [:user_id])

    IO.puts("Migration: CreateConversations - Migration completed.")
  end
end
