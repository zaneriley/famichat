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
    field :metadata, :map, default: %{}
    # Message delivery status
    field :status, Ecto.Enum, values: [:sent, :delivered, :read], default: :sent
    field :timestamp, :utc_datetime_usec

    # Sender of the message
    belongs_to :sender, Famichat.Chat.User, foreign_key: :sender_id, type: :binary_id
    # Conversation message belongs to
    belongs_to :conversation, Famichat.Chat.Conversation,
      foreign_key: :conversation_id, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec changeset(%__MODULE__{} | Ecto.Changeset.t(), map()) ::
          Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:sender_id, :conversation_id, :message_type, :content, :media_url, :metadata, :status, :timestamp])
    |> validate_required([:sender_id, :conversation_id, :message_type, :status])
    |> validate_by_type()
  end

  defp validate_by_type(changeset) do
    case get_field(changeset, :message_type) do
      :text -> validate_required(changeset, [:content])
      :image -> validate_required(changeset, [:media_url])
      :video -> validate_required(changeset, [:media_url])
      :voice -> validate_required(changeset, [:media_url])
      :file -> validate_required(changeset, [:media_url])
      _ -> changeset
    end
  end
end
