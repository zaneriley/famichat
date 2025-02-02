defmodule Famichat.Chat.Conversation do
  @moduledoc """
  Schema and changeset for the `Conversation` model.

  Represents a conversation between users in Famichat. Supports
  different conversation types (letter, direct, group, self) and user associations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          family_id: Ecto.UUID.t(),
          conversation_type: :letter | :direct | :group | :self,
          metadata: map(),
          messages: [Famichat.Chat.Message.t()] | nil,
          users: [Famichat.Chat.User.t()] | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "conversations" do
    field :family_id, :binary_id
    field :conversation_type, Ecto.Enum,
      values: [:letter, :direct, :group, :self],
      default: :direct

    # For future metadata (e.g., group chat name, etc.)
    field :metadata, :map, default: %{}

    has_many :messages, Famichat.Chat.Message, foreign_key: :conversation_id
    # Update the many_to_many relationship
    many_to_many :users, Famichat.Chat.User,
      join_through: Famichat.Chat.ConversationParticipant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:conversation_type, :metadata, :family_id])
    |> validate_required([:conversation_type, :family_id])
    |> validate_metadata()
    |> validate_conversation_type()
  end

  defp validate_metadata(changeset) do
    case get_field(changeset, :metadata) do
      nil -> put_change(changeset, :metadata, %{})
      _ -> changeset
    end
  end

  defp validate_conversation_type(changeset) do
    case get_field(changeset, :conversation_type) do
      :letter -> validate_letter_metadata(changeset)
      :direct -> changeset
      :group -> validate_group_metadata(changeset)
      :self -> changeset
      _ -> add_error(changeset, :conversation_type, "is invalid")
    end
  end

  defp validate_letter_metadata(changeset) do
    metadata = get_field(changeset, :metadata)
    if is_map(metadata) && Map.has_key?(metadata, "subject") do
      changeset
    else
      add_error(changeset, :metadata, "letters require a subject")
    end
  end

  defp validate_group_metadata(changeset) do
    metadata = get_field(changeset, :metadata)
    if is_map(metadata) && Map.has_key?(metadata, "name") do
      changeset
    else
      add_error(changeset, :metadata, "group conversations require a name")
    end
  end

  @doc false
  @spec user_changeset(Famichat.Chat.User.t(), map()) :: Ecto.Changeset.t()
  # Dummy user changeset, adapt if needed for associations
  defp user_changeset(user, attrs) do
    user
    # assuming User has its own changeset
    |> Famichat.Chat.User.changeset(attrs)
  end
end
