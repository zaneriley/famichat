defmodule Famichat.Repo.Migrations.AddMessageSeqToMessages do
  use Ecto.Migration

  def up do
    # Add message_seq column as nullable initially to allow backfill.
    # The trigger and NOT NULL constraint are added after backfill.
    alter table(:messages) do
      add :message_seq, :bigint, null: true
    end

    # Partial unique index to catch duplicate-seq bugs during development
    # before we enforce NOT NULL. conversation_id + message_seq must be
    # unique per the spec's monotonic guarantee.
    create unique_index(:messages, [:conversation_id, :message_seq],
      name: :messages_conversation_id_message_seq_index,
      where: "message_seq IS NOT NULL"
    )
  end

  def down do
    drop_if_exists index(:messages, [:conversation_id, :message_seq],
      name: :messages_conversation_id_message_seq_index
    )

    alter table(:messages) do
      remove :message_seq
    end
  end
end
