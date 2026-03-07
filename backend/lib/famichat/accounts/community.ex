defmodule Famichat.Accounts.Community do
  @moduledoc """
  Hidden root scope for a single operator-owned deployment.

  This schema currently supports only the singleton seeded community used for
  one-community-per-deployment dogfood.
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

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "communities" do
    field :name, :string
    field :settings, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(community, attrs) do
    community
    |> cast(attrs, [:id, :name, :settings])
    |> validate_required([:id, :name])
  end
end
