defmodule Famichat.Accounts.UserDevice do
  @moduledoc """
  Persisted device state for session management.

  Write owner: `Famichat.Auth.Sessions.DeviceStore`.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Famichat.Schema.Validations

  alias Famichat.Accounts.User

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t(),
          device_id: String.t(),
          refresh_token_hash: binary() | nil,
          previous_token_hash: binary() | nil,
          user_agent: String.t() | nil,
          ip: String.t() | nil,
          trusted_until: DateTime.t() | nil,
          last_active_at: DateTime.t() | nil,
          revoked_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_devices" do
    belongs_to :user, User
    field :device_id, :string
    field :refresh_token_hash, :binary
    field :previous_token_hash, :binary
    field :user_agent, :string
    field :ip, :string
    field :trusted_until, :utc_datetime_usec
    field :last_active_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :user_id,
      :device_id,
      :refresh_token_hash,
      :previous_token_hash,
      :user_agent,
      :ip,
      :trusted_until,
      :last_active_at,
      :revoked_at
    ])
    |> validate_required([:user_id, :device_id])
    |> validate_string_field(:user_agent, required: false, max: 512)
    |> validate_string_field(:ip, required: false, max: 45)
    |> unique_constraint(:device_id)
  end
end
