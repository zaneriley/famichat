defmodule Famichat.Chat.Family do
  @moduledoc """
  Schema and changeset for the Family model.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Famichat.Schema.Validations

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          community_id: Ecto.UUID.t() | nil,
          name: String.t(),
          settings: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "families" do
    field :community_id, :binary_id, read_after_writes: true
    belongs_to :community, Famichat.Accounts.Community, define_field: false
    field :name, :string
    field :settings, :map, default: %{}

    has_many :memberships, Famichat.Accounts.HouseholdMembership
    has_many :users, through: [:memberships, :user]
    has_many :conversations, Famichat.Chat.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(family, attrs) do
    family
    |> cast(attrs, [:name, :settings, :community_id])
    |> validate_string_field(:name, max: 100)
    |> unique_constraint(:name)
    |> foreign_key_constraint(:community_id)
  end
end
