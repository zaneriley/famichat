# Create a new schema file: backend/lib/famichat/chat/conversation_participant.ex
defmodule Famichat.Chat.ConversationParticipant do
  @moduledoc """
  Schema for tracking user participation in conversations.

  This schema manages the many-to-many relationship between users and conversations,
  allowing for future extension with participant-specific metadata like roles or
  last_seen timestamps.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          conversation_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key false
  @foreign_key_type :binary_id
  schema "conversation_users" do
    field :conversation_id, :binary_id, primary_key: true
    field :user_id, :binary_id, primary_key: true

    belongs_to :conversation, Famichat.Chat.Conversation, define_field: false
    belongs_to :user, Famichat.Chat.User, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for a conversation participant.

  ## Parameters
    * `participant` - The current participant struct
    * `attrs` - The attributes to validate
  """
  @spec changeset(t() | Ecto.Changeset.t(), any()) :: Ecto.Changeset.t()
  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:conversation_id, :user_id])
    |> validate_required([:conversation_id, :user_id])
    |> unique_constraint([:conversation_id, :user_id],
      name: :conversation_users_conversation_id_user_id_index
    )
  end
end
