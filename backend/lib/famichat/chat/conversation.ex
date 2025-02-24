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
          direct_key: String.t() | nil,
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

    # New field for enforcing uniqueness in direct conversations
    field :direct_key, :string

    # For future metadata (e.g., group chat name, etc.)
    field :metadata, :map, default: %{}

    has_many :messages, Famichat.Chat.Message, foreign_key: :conversation_id
    # Update the many_to_many relationship
    many_to_many :users, Famichat.Chat.User,
      join_through: Famichat.Chat.ConversationParticipant

    has_many :participants, Famichat.Chat.ConversationParticipant,
      foreign_key: :conversation_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec changeset(
          t() | Ecto.Changeset.t(),
          %{
            :family_id => binary(),
            optional(:conversation_type) => :letter | :direct | :group | :self,
            optional(:metadata) => map(),
            optional(:direct_key) => String.t()
          }
        ) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:family_id, :conversation_type, :metadata, :direct_key])
    |> validate_required([:family_id])
    |> validate_conversation_type()
    |> validate_direct_key()
    |> validate_metadata()
  end

  defp validate_direct_key(changeset) do
    if get_field(changeset, :conversation_type) == :direct do
      if is_nil(get_field(changeset, :direct_key)) do
        add_error(changeset, :direct_key, "must be set for direct conversations")
      else
        changeset
      end
    else
      changeset
    end
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

  @doc """
  Computes a unique key for direct conversations based on the sorted user IDs,
  the family ID, and a secure salt sourced from the environment.

  ## Examples

      iex> Famichat.Chat.Conversation.compute_direct_key("user1", "user2", "family123")
      "a3c4ef..."
  """
  def compute_direct_key(user1_id, user2_id, family_id) do
    salt = System.fetch_env!("UNIQUE_CONVERSATION_KEY_SALT")
    sorted_ids = Enum.sort([user1_id, user2_id])
    raw_key = Enum.join(sorted_ids, "-") <> "-" <> family_id
    :crypto.hash(:sha256, raw_key <> salt) |> Base.encode16(case: :lower)
  end
end
