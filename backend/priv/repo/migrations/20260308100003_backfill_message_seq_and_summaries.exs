defmodule Famichat.Repo.Migrations.BackfillMessageSeqAndSummaries do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    backfill_conversation_summaries()
    backfill_message_seq()
    update_latest_message_seq()
    enforce_not_null()
    replace_partial_with_full_unique_index()
  end

  def down do
    revert_to_nullable()
    restore_partial_unique_index()
    clear_backfilled_data()
  end

  # Step 1: Insert conversation_summaries rows for all existing conversations.
  defp backfill_conversation_summaries do
    execute("""
    INSERT INTO conversation_summaries (
      conversation_id,
      conversation_type,
      member_count,
      latest_message_seq,
      last_message_at,
      inserted_at,
      updated_at
    )
    SELECT
      c.id,
      c.conversation_type,
      COALESCE(cu.member_count, 0),
      0,
      msg_stats.last_message_at,
      NOW(),
      NOW()
    FROM conversations c
    LEFT JOIN (
      SELECT conversation_id, COUNT(*) AS member_count
      FROM conversation_users
      GROUP BY conversation_id
    ) cu ON cu.conversation_id = c.id
    LEFT JOIN (
      SELECT conversation_id, MAX(inserted_at) AS last_message_at
      FROM messages
      GROUP BY conversation_id
    ) msg_stats ON msg_stats.conversation_id = c.id
    ON CONFLICT (conversation_id) DO NOTHING;
    """)
  end

  # Step 2: Backfill message_seq using ROW_NUMBER() window function.
  # F2: Disable trigger during backfill to prevent seq conflicts between
  # trigger-assigned and ROW_NUMBER()-assigned values.
  defp backfill_message_seq do
    execute("ALTER TABLE messages DISABLE TRIGGER messages_assign_seq;")

    execute("""
    UPDATE messages AS m
    SET message_seq = ranked.rn
    FROM (
      SELECT
        id,
        ROW_NUMBER() OVER (
          PARTITION BY conversation_id
          ORDER BY inserted_at ASC, id ASC
        ) AS rn
      FROM messages
      WHERE message_seq IS NULL
    ) ranked
    WHERE m.id = ranked.id;
    """)

    execute("ALTER TABLE messages ENABLE TRIGGER messages_assign_seq;")
  end

  # Step 3: Update conversation_summaries.latest_message_seq to reflect
  # the max assigned seq per conversation after backfill.
  defp update_latest_message_seq do
    execute("""
    UPDATE conversation_summaries cs
    SET
      latest_message_seq = agg.max_seq,
      updated_at = NOW()
    FROM (
      SELECT conversation_id, MAX(message_seq) AS max_seq
      FROM messages
      WHERE message_seq IS NOT NULL
      GROUP BY conversation_id
    ) agg
    WHERE cs.conversation_id = agg.conversation_id;
    """)
  end

  # Step 4: Add NOT NULL constraint now that all rows have a value.
  defp enforce_not_null do
    alter table(:messages) do
      modify :message_seq, :bigint, null: false
    end
  end

  # Step 5: Replace partial unique index with full unique index.
  # F5: Use single execute() to drop and create atomically, preventing a
  # window where no uniqueness constraint exists.
  defp replace_partial_with_full_unique_index do
    execute("DROP INDEX IF EXISTS messages_conversation_id_message_seq_index")

    execute("""
    CREATE UNIQUE INDEX messages_conversation_id_message_seq_index
      ON messages (conversation_id, message_seq)
    """)
  end

  defp revert_to_nullable do
    alter table(:messages) do
      modify :message_seq, :bigint, null: true
    end
  end

  defp restore_partial_unique_index do
    drop_if_exists index(:messages, [:conversation_id, :message_seq],
                     name: :messages_conversation_id_message_seq_index
                   )

    create unique_index(:messages, [:conversation_id, :message_seq],
             name: :messages_conversation_id_message_seq_index,
             where: "message_seq IS NOT NULL"
           )
  end

  defp clear_backfilled_data do
    execute("UPDATE messages SET message_seq = NULL;")
    execute("DELETE FROM conversation_summaries;")
  end
end
