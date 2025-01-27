defmodule Famichat.Chat.Conversation do
  @moduledoc """
  Schema and changeset for the `Conversation` model.

  Represents a conversation between users in Famichat.  Supports
  different conversation types (direct, group, self) and user associations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          conversation_type: :direct | :group | :self,
          metadata: map(),
          messages: [Famichat.Chat.Message.t()] | nil,
          users: [Famichat.Chat.User.t()] | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "conversations" do
    # Enum for conversation types
    field :conversation_type, Ecto.Enum,
      values: [:direct, :group, :self],
      default: :direct

    # For future metadata (e.g., group chat name, etc.)
    field :metadata, :map

    has_many :messages, Famichat.Chat.Message, foreign_key: :conversation_id
    # Explicit many-to-many for users
    many_to_many :users, Famichat.Chat.User, join_through: "conversation_users"

    timestamps()
  end

  @doc false
  # Changed t() to __MODULE__.t()
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:conversation_type, :metadata])
    # conversation_type will always be set, but good to have
    |> validate_required([:conversation_type])
    # Ensure users association is handled correctly if needed in changeset
    |> cast_assoc(:users, with: &user_changeset/2)
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
