defmodule Famichat.Chat.ConversationSummary do
  @moduledoc """
  Read model for conversation inbox metadata.

  Maintained by a PostgreSQL trigger on the messages table. Do not write
  to this schema directly except from migrations and the trigger function.
  The trigger in assign_message_seq() handles all updates on message insert.

  member_count is updated by ConversationService when members join or leave.
  """
  use Ecto.Schema

  @primary_key false
  schema "conversation_summaries" do
    belongs_to :conversation, Famichat.Chat.Conversation,
      foreign_key: :conversation_id,
      type: :binary_id,
      primary_key: true

    field :conversation_type, :string
    field :member_count, :integer, default: 0
    field :latest_message_seq, :integer, default: 0
    field :last_message_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
