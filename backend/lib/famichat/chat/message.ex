defmodule Famichat.Chat.Message do
  @moduledoc """
  Schema and changeset for the `Message` model.

  Represents a message in a Famichat conversation. Handles different
  message types and validations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type message_type ::
          :text | :voice | :video | :image | :file | :poke | :reaction | :gif
  @type status :: :sent | :delivered | :read

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          message_type: message_type() | nil,
          content: String.t() | nil,
          media_url: String.t() | nil,
          metadata: map() | nil,
          status: status() | nil,
          sender_id: Ecto.UUID.t() | nil,
          conversation_id: Ecto.UUID.t() | nil,
          sender: Famichat.Chat.User.t() | nil,
          conversation: Famichat.Chat.Conversation.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  # Explicit primary key type if needed - defaults to UUID
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "messages" do
    # Enum for message types
    field :message_type, Ecto.Enum,
      values: [:text, :voice, :video, :image, :file, :poke, :reaction, :gif],
      default: :text

    # For text messages, maybe captions for media in future
    field :content, :string
    # URL for media (voice, video, image, file) - nullable for text messages
    field :media_url, :string
    # For message-specific metadata (e.g., voice memo duration, reaction type)
    field :metadata, :map
    # Message delivery status
    field :status, Ecto.Enum, values: [:sent, :delivered, :read], default: :sent

    # Sender of the message
    belongs_to :sender, Famichat.Chat.User, foreign_key: :sender_id
    # Conversation message belongs to
    belongs_to :conversation, Famichat.Chat.Conversation,
      foreign_key: :conversation_id

    timestamps()
  end

  @doc false
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) ::
          Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :message_type,
      :content,
      :media_url,
      :metadata,
      :status,
      :sender_id,
      :conversation_id
    ])
    |> validate_required([:message_type, :sender_id, :conversation_id])
    |> validate_inclusion(:message_type, [
      :text,
      :voice,
      :video,
      :image,
      :file,
      :poke,
      :reaction,
      :gif
    ])
    # Ensure content is present for text messages
    |> validate_required([:content], where: [message_type: :text])
    # Ensure content is not empty for text messages
    |> validate_length(:content, min: 1, where: [message_type: :text])
  end
end
