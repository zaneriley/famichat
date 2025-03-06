defmodule Famichat.Chat.Conversation do
  @moduledoc """
  Schema and changeset for the `Conversation` model.

  Represents a conversation between users in Famichat. Supports
  different conversation types (letter, direct, group, self) and user associations.

  ## Type Boundaries

  Each conversation has a specific type which dictates:
    - The number of allowed participants
    - Required metadata fields
    - Validation requirements
    - Immutability (type cannot be changed after creation)

  ## Validation

  Uses different changesets depending on the operation:
    - `create_changeset/2` - For initial creation, enforces type requirements
    - `update_changeset/2` - For updates, prevents type modification
    - `validate_user_count/1` - Optional validation for participant count
  """
  use Ecto.Schema
  import Ecto.Changeset
  require Logger

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          family_id: Ecto.UUID.t(),
          conversation_type: :direct | :group | :self | :family,
          direct_key: String.t() | nil,
          metadata: map(),
          messages: [Famichat.Chat.Message.t()] | nil,
          users: [Famichat.Chat.User.t()] | nil,
          hidden_by_users: [Ecto.UUID.t()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "conversations" do
    field :family_id, :binary_id

    field :conversation_type, Ecto.Enum,
      values: [:direct, :group, :self, :family],
      default: :direct

    # For enforcing uniqueness in direct conversations
    field :direct_key, :string

    # For future metadata (e.g., group chat name, etc.)
    field :metadata, :map, default: %{}

    # For tracking users who have hidden the conversation (soft delete)
    field :hidden_by_users, {:array, :binary_id}, default: []

    has_many :messages, Famichat.Chat.Message, foreign_key: :conversation_id

    many_to_many :users, Famichat.Chat.User,
      join_through: Famichat.Chat.ConversationParticipant

    has_many :participants, Famichat.Chat.ConversationParticipant,
      foreign_key: :conversation_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for a new conversation.

  This changeset is used exclusively for creating new conversations and enforces:
  - Required fields (family_id)
  - Type-specific validation
  - Metadata validation based on type

  ## Examples

      iex> create_changeset(%Conversation{}, %{family_id: uuid, conversation_type: :direct})
      %Ecto.Changeset{...}
  """
  @spec create_changeset(t() | Ecto.Changeset.t(), any()) :: Ecto.Changeset.t()
  def create_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [
      :family_id,
      :conversation_type,
      :metadata,
      :direct_key,
      :hidden_by_users
    ])
    |> validate_required([:family_id, :conversation_type])
    |> validate_direct_key()
    |> validate_metadata()
  end

  @doc """
  Creates a changeset for updating an existing conversation.

  This changeset prevents modification of immutable fields:
  - conversation_type cannot be changed
  - Enforces field validation based on existing type

  ## Examples

      iex> update_changeset(conversation, %{metadata: %{name: "New Name"}})
      %Ecto.Changeset{...}
  """
  @spec update_changeset(t() | Ecto.Changeset.t(), any()) :: Ecto.Changeset.t()
  def update_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:metadata, :hidden_by_users])
    |> validate_metadata()
  end

  @doc false
  @spec changeset(t() | Ecto.Changeset.t(), any()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    # For backwards compatibility
    Logger.warning(
      "Using deprecated generic changeset. Use create_changeset/2 or update_changeset/2 instead"
    )

    conversation
    |> cast(attrs, [
      :family_id,
      :conversation_type,
      :metadata,
      :direct_key,
      :hidden_by_users
    ])
    |> validate_required([:family_id])
    |> validate_conversation_type()
    |> validate_direct_key()
    |> validate_metadata()
  end

  defp validate_direct_key(changeset) do
    if get_field(changeset, :conversation_type) == :direct do
      if is_nil(get_field(changeset, :direct_key)) do
        add_error(
          changeset,
          :direct_key,
          "must be set for direct conversations"
        )
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
    |> validate_type_specific_metadata()
  end

  defp validate_type_specific_metadata(changeset) do
    case get_field(changeset, :conversation_type) do
      :direct -> changeset
      :group -> validate_group_metadata(changeset)
      :self -> changeset
      :family -> changeset
      _ -> add_error(changeset, :conversation_type, "is invalid")
    end
  end

  defp validate_conversation_type(changeset) do
    changeset
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
  Validates that a conversation has the appropriate number of users for its type.
  This is an optional validation that can be used when needed, rather than during
  initial creation where users might be added in a separate step.

  It checks:
  - Direct conversations should have exactly 2 users
  - Self conversations should have exactly 1 user
  - Group conversations should have at least 1 user
  - Letter conversations follow direct conversation rules (2 users)

  Returns a changeset with appropriate error messages if validations fail.

  ## Examples

      iex> validate_user_count(changeset)
      %Ecto.Changeset{...}
  """
  def validate_user_count(changeset) do
    conversation_type = get_field(changeset, :conversation_type)
    users = get_field(changeset, :users) || []
    user_count = length(users)

    changeset
    |> validate_conversation_type_presence(conversation_type)
    |> validate_user_count_by_type(conversation_type, user_count)
  end

  defp validate_conversation_type_presence(changeset, nil),
    do:
      add_error(
        changeset,
        :conversation_type,
        "must be set for user count validation"
      )

  defp validate_conversation_type_presence(changeset, _), do: changeset

  defp validate_user_count_by_type(changeset, _, 0), do: changeset

  defp validate_user_count_by_type(changeset, :direct, 2), do: changeset

  defp validate_user_count_by_type(changeset, :direct, _),
    do:
      add_error(
        changeset,
        :users,
        "direct conversations require exactly 2 users"
      )

  defp validate_user_count_by_type(changeset, :self, 1), do: changeset

  defp validate_user_count_by_type(changeset, :self, _),
    do:
      add_error(changeset, :users, "self conversations require exactly 1 user")

  defp validate_user_count_by_type(changeset, :group, n) when n >= 3,
    do: changeset

  defp validate_user_count_by_type(changeset, :group, _),
    do:
      add_error(
        changeset,
        :users,
        "group conversations require at least 3 users"
      )

  defp validate_user_count_by_type(changeset, :family, n) when n >= 1,
    do: changeset

  defp validate_user_count_by_type(changeset, :family, _),
    do:
      add_error(
        changeset,
        :users,
        "family conversations require at least 1 user"
      )

  defp validate_user_count_by_type(changeset, _, _), do: changeset

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
