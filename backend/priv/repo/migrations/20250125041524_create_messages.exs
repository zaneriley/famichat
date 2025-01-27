defmodule Famichat.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    IO.puts("Migration: CreateMessages - Starting table creation...")

    create table(:messages, primary_key: false) do
      IO.puts("Migration: CreateMessages - Creating table structure...")
      add :id, :binary_id, primary_key: true
      IO.puts("Migration: CreateMessages - Added column: id")
      add :sender_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      IO.puts("Migration: CreateMessages - Added column: sender_id")
      add :message_type, :string, null: false
      IO.puts("Migration: CreateMessages - Added column: message_type")
      add :content, :text
      IO.puts("Migration: CreateMessages - Added column: content")
      add :media_url, :text
      IO.puts("Migration: CreateMessages - Added column: media_url")
      add :metadata, :map, default: %{}
      IO.puts("Migration: CreateMessages - Added column: metadata")
      add :timestamp, :utc_datetime_usec
      # <--- CRITICAL COLUMN
      IO.puts("Migration: CreateMessages - Added column: timestamp")
      # Corrected timestamps macro usage
      timestamps(type: :utc_datetime_usec)
      IO.puts("Migration: CreateMessages - Added timestamps (inserted_at, updated_at)")
    end

    IO.puts("Migration: CreateMessages - Table 'messages' created.")

    IO.puts("Migration: CreateMessages - Creating index on sender_id...")
    create index(:messages, [:sender_id])
    IO.puts("Migration: CreateMessages - Index on sender_id created.")

    IO.puts("Migration: CreateMessages - Creating index on inserted_at...")
    create index(:messages, [:inserted_at])
    IO.puts("Migration: CreateMessages - Index on inserted_at created.")

    IO.puts("Migration: CreateMessages - Migration completed.")
  end
end
