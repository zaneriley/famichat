defmodule Famichat.Accounts.Passkey do
  @moduledoc """
  Stored WebAuthn credentials bound to a user.

  Write owner: `Famichat.Auth.Passkeys`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Famichat.Accounts.User

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t(),
          credential_id: binary(),
          public_key: binary(),
          sign_count: non_neg_integer(),
          aaguid: binary() | nil,
          label: String.t() | nil,
          last_used_at: DateTime.t() | nil,
          disabled_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "passkeys" do
    belongs_to :user, User
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :aaguid, :binary
    field :label, :string
    field :last_used_at, :utc_datetime_usec
    field :disabled_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [
      :user_id,
      :credential_id,
      :public_key,
      :sign_count,
      :aaguid,
      :label,
      :last_used_at,
      :disabled_at
    ])
    |> validate_required([:user_id, :credential_id, :public_key])
    |> unique_constraint(:credential_id)
  end
end
