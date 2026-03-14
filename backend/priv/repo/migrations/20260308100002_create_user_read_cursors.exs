defmodule Famichat.Repo.Migrations.CreateUserReadCursors do
  use Ecto.Migration

  def up do
    create table(:user_read_cursors, primary_key: false) do
      # Composite primary key: one cursor per (user, conversation) pair.
      add :user_id,
          references(:users, on_delete: :delete_all, type: :binary_id),
          null: false

      add :conversation_id,
          references(:conversations, on_delete: :delete_all, type: :binary_id),
          null: false

      # The highest message_seq the user has acknowledged.
      # Starts at 0 meaning "no messages read."
      add :last_acked_seq, :bigint, null: false, default: 0

      # Track when the cursor was last updated.
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:user_read_cursors, [:user_id, :conversation_id],
             name: :user_read_cursors_user_conversation_pk
           )

    # Index for "fetch all cursors for a user" — needed to compute unread
    # counts across all conversations for a single user login.
    create index(:user_read_cursors, [:user_id])
  end

  def down do
    drop_if_exists table(:user_read_cursors)
  end
end
