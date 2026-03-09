defmodule Famichat.Chat.UserReadCursor do
  @moduledoc """
  Persists the per-user per-conversation read cursor (last acknowledged message_seq).

  Written by the channel ack handler (handle_in("message_ack")) and read by
  the conversation list endpoint to compute unread counts.

  Uses user-level cursors ("read anywhere = read everywhere") rather than
  device-level, which is the correct semantic for a family messaging app.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "user_read_cursors" do
    belongs_to :user, Famichat.Accounts.User,
      foreign_key: :user_id,
      type: :binary_id

    belongs_to :conversation, Famichat.Chat.Conversation,
      foreign_key: :conversation_id,
      type: :binary_id

    field :last_acked_seq, :integer, default: 0
    field :updated_at, :utc_datetime_usec
  end

  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(cursor, attrs) do
    cursor
    |> cast(attrs, [:user_id, :conversation_id, :last_acked_seq, :updated_at])
    |> validate_required([:user_id, :conversation_id, :last_acked_seq])
    |> validate_number(:last_acked_seq, greater_than_or_equal_to: 0)
  end
end
