defmodule Famichat.Chat.Message do
  @moduledoc """
  Schema and changeset for the `Message` model.

  Represents a message in a Famichat conversation. Handles different
  message types and validations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type message_type :: :text | :voice | :video | :image | :file | :poke | :reaction | :gif
  @type status :: :sent | :delivered | :read

  @type t :: %__MODULE__{
    id: Ecto.UUID.t(),
    message_type: message_type(),
    content: String.t() | nil,
    media_url: String.t() | nil,
    metadata: map() | nil,
    status: status(),
    sender_id: Ecto.UUID.t(),
    conversation_id: Ecto.UUID.t(),
    sender: Famichat.Chat.User.t() | nil,
    conversation: Famichat.Chat.Conversation.t() | nil,
    inserted_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  @primary_key {:id, :binary_id, autogenerate: true} # Explicit primary key type if needed - defaults to UUID
  schema "messages" do
    field :message_type, Ecto.Enum, values: [:text, :voice, :video, :image, :file, :poke, :reaction, :gif], default: :text # Enum for message types
    field :content, :string # For text messages, maybe captions for media in future
    field :media_url, :string # URL for media (voice, video, image, file) - nullable for text messages
    field :metadata, :map # For message-specific metadata (e.g., voice memo duration, reaction type)
    field :status, Ecto.Enum, values: [:sent, :delivered, :read], default: :sent # Message delivery status

    belongs_to :sender, Famichat.Chat.User, foreign_key: :sender_id # Sender of the message
    belongs_to :conversation, Famichat.Chat.Conversation, foreign_key: :conversation_id # Conversation message belongs to

    timestamps()
  end

  @doc false
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t() # Changed t() to __MODULE__.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:message_type, :content, :media_url, :metadata, :status, :sender_id, :conversation_id])
    |> validate_required([:message_type, :sender_id, :conversation_id])
    |> validate_inclusion(:message_type, [:text, :voice, :video, :image, :file, :poke, :reaction, :gif])
    |> validate_required([:content], where: [message_type: :text]) # Ensure content is present for text messages
    |> validate_length(:content, min: 1, where: [message_type: :text]) # Ensure content is not empty for text messages
  end
end
