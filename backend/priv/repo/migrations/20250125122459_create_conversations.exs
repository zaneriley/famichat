defmodule Famichat.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    IO.puts("Migration: CreateConversations - Starting table creation...")
    create table(:conversations, primary_key: false) do  # Specify primary_key: false for custom primary key if needed, or remove if default is ok.
      IO.puts("Migration: CreateConversations - Creating table structure...")
      add :id, :binary_id, primary_key: true # Add primary key if needed, binary_id is a good choice
      IO.puts("Migration: CreateConversations - Added column: id")

      IO.puts("Migration: CreateConversations - Adding column: user1_id...")
      add :user1_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      IO.puts("Migration: CreateConversations - Added column: user1_id")

      IO.puts("Migration: CreateConversations - Adding column: user2_id...")
      add :user2_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      IO.puts("Migration: CreateConversations - Added column: user2_id")

      timestamps([type: :utc_datetime_usec]) # Correct # Keep timestamps type consistent
      IO.puts("Migration: CreateConversations - Added timestamps (inserted_at, updated_at)")
    end
    IO.puts("Migration: CreateConversations - Table 'conversations' created.")

    IO.puts("Migration: CreateConversations - Creating index on user1_id...")
    create index(:conversations, [:user1_id])
    IO.puts("Migration: CreateConversations - Index on user1_id created.")

    IO.puts("Migration: CreateConversations - Creating index on user2_id...")
    create index(:conversations, [:user2_id])
    IO.puts("Migration: CreateConversations - Index on user2_id created.")

    IO.puts("Migration: CreateConversations - Migration completed.")
  end
end
