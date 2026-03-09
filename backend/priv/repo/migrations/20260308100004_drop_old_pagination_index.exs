defmodule Famichat.Repo.Migrations.DropOldPaginationIndex do
  use Ecto.Migration

  @doc """
  Drops the old (conversation_id, inserted_at, id) composite index that was
  used for the previous (inserted_at, id) cursor pagination. The new cursor
  uses message_seq with a dedicated unique index on (conversation_id, message_seq)
  created in 20260308100000. The old index is never hit by the new ORDER BY
  but still incurs write amplification on every INSERT.
  """

  def up do
    drop_if_exists index(:messages, [:conversation_id, :inserted_at, :id],
      name: :messages_conversation_id_inserted_at_id
    )
  end

  def down do
    create index(:messages, [:conversation_id, :inserted_at, :id],
      name: :messages_conversation_id_inserted_at_id
    )
  end
end
