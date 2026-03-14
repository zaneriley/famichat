defmodule Famichat.Repo.Migrations.CreateConversationSummaries do
  use Ecto.Migration

  def up do
    create table(:conversation_summaries, primary_key: false) do
      add :conversation_id,
          references(:conversations, on_delete: :delete_all, type: :binary_id),
          primary_key: true,
          null: false

      add :conversation_type, :string, null: false
      add :member_count, :integer, null: false, default: 0
      add :latest_message_seq, :bigint, null: false, default: 0
      add :last_message_at, :utc_datetime_usec, null: true

      timestamps(type: :utc_datetime_usec)
    end

    create index(:conversation_summaries, [:last_message_at])

    execute(trigger_function_sql(), "SELECT 1;")
    execute(trigger_sql(), "SELECT 1;")
  end

  def down do
    execute("DROP TRIGGER IF EXISTS messages_assign_seq ON messages;")
    execute("DROP FUNCTION IF EXISTS assign_message_seq();")
    drop_if_exists table(:conversation_summaries)
  end

  defp trigger_function_sql do
    """
    CREATE OR REPLACE FUNCTION assign_message_seq()
    RETURNS TRIGGER AS $$
    DECLARE
      next_seq bigint;
    BEGIN
      -- Lock the summary row and read current seq (F4: FOR UPDATE prevents lost updates)
      SELECT latest_message_seq + 1 INTO next_seq
        FROM conversation_summaries
        WHERE conversation_id = NEW.conversation_id
        FOR UPDATE;

      -- F7: If no summary row exists, create one via upsert (handles mid-migration races)
      IF NOT FOUND THEN
        INSERT INTO conversation_summaries (
          conversation_id, conversation_type, member_count,
          latest_message_seq, last_message_at, inserted_at, updated_at
        )
        VALUES (
          NEW.conversation_id, 'direct_message', 1,
          1, NEW.inserted_at, NOW(), NOW()
        )
        ON CONFLICT (conversation_id) DO UPDATE
          SET latest_message_seq = conversation_summaries.latest_message_seq + 1,
              last_message_at = EXCLUDED.last_message_at,
              updated_at = NOW()
        RETURNING latest_message_seq INTO next_seq;
      ELSE
        -- Update the counter (F1/F3: separate SELECT then UPDATE, not RETURNING INTO)
        UPDATE conversation_summaries
          SET
            latest_message_seq = next_seq,
            last_message_at    = NEW.inserted_at,
            updated_at         = NOW()
          WHERE conversation_id = NEW.conversation_id;
      END IF;

      NEW.message_seq := next_seq;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end

  defp trigger_sql do
    """
    CREATE TRIGGER messages_assign_seq
    BEFORE INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION assign_message_seq();
    """
  end
end
