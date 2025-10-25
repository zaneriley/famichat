defmodule Famichat.Accounts.HouseholdMembership do
  @moduledoc """
  Links a user to a household with a specific role.

  Write owner: `Famichat.Auth.Households`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Famichat.Accounts.User
  alias Famichat.Chat.Family

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          family_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          role: :admin | :member,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @source "family_memberships"
  schema @source do
    belongs_to :family, Family, foreign_key: :family_id
    belongs_to :user, User
    field :role, Ecto.Enum, values: [:admin, :member], default: :member

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:family_id, :user_id, :role])
    |> validate_required([:family_id, :user_id, :role])
    |> unique_constraint(:membership_uniqueness,
      name: :family_memberships_family_id_user_id_index,
      message: "user already belongs to household"
    )
  end
end

defmodule Famichat.Accounts.FamilyMembership do
  @moduledoc "Deprecated alias for `Famichat.Accounts.HouseholdMembership`."
  @deprecated "use Famichat.Accounts.HouseholdMembership"

  alias Famichat.Accounts.HouseholdMembership, as: Target

  defdelegate changeset(membership, attrs), to: Target
end
