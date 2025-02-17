defmodule Famichat.Chat.Family do
  @moduledoc """
  Schema and changeset for the Family model.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          settings: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "families" do
    field :name, :string
    field :settings, :map, default: %{}

    has_many :users, Famichat.Chat.User
    has_many :conversations, Famichat.Chat.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(family, attrs) do
    family
    |> cast(attrs, [:name, :settings])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
