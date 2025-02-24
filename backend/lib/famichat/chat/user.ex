defmodule Famichat.Chat.User do
  @moduledoc """
  Schema and changeset for the `User` model.

  Represents a user in the Famichat application.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          username: String.t() | nil,
          email: String.t() | nil,
          role: :admin | :member,
          family_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :username, :string
    field :email, :string
    field :role, Ecto.Enum, values: [:admin, :member], default: :member
    field :family_id, :binary_id

    many_to_many :conversations, Famichat.Chat.Conversation,
      join_through: Famichat.Chat.ConversationParticipant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :role, :family_id])
    |> validate_required([:username, :email, :role, :family_id])
    |> unique_constraint(:username)
    |> unique_constraint(:email)
  end
end
