defmodule Famichat.Accounts.User do
  @moduledoc """
  Primary account record for Famichat users.

  Write owner: `Famichat.Auth.Identity`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Famichat.Accounts.HouseholdMembership
  alias Famichat.Accounts.Passkey
  alias Famichat.Accounts.Types.EncryptedBinary
  alias Famichat.Accounts.UserDevice
  alias Famichat.Accounts.Username

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          community_id: Ecto.UUID.t() | nil,
          username: String.t() | nil,
          username_fingerprint: binary() | nil,
          email: binary() | nil,
          email_fingerprint: binary() | nil,
          status: :invited | :pending | :active | :locked | :deleted | nil,
          password_hash: String.t() | nil,
          confirmed_at: DateTime.t() | nil,
          last_login_at: DateTime.t() | nil,
          enrollment_required_since: DateTime.t() | nil,
          registration_token_id: Ecto.UUID.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :community_id, :binary_id, read_after_writes: true
    belongs_to :community, Famichat.Accounts.Community, define_field: false
    field :username, :string
    field :username_fingerprint, :binary
    field :email, EncryptedBinary
    field :email_fingerprint, :binary

    field :status, Ecto.Enum,
      values: [:invited, :pending, :active, :locked, :deleted],
      default: :invited

    field :registration_token_id, :binary_id

    field :password_hash, :string
    field :confirmed_at, :utc_datetime_usec
    field :last_login_at, :utc_datetime_usec
    field :enrollment_required_since, :utc_datetime_usec

    has_many :memberships, HouseholdMembership
    has_many :families, through: [:memberships, :family]
    has_many :passkeys, Passkey
    has_many :devices, UserDevice

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :username,
      :email,
      :status,
      :password_hash,
      :confirmed_at,
      :last_login_at,
      :enrollment_required_since,
      :registration_token_id
    ])
    |> sanitize_username()
    |> validate_required([:username])
    |> validate_length(:username, max: 50)
    |> normalize_email()
    |> put_email_fingerprint()
    |> put_username_fingerprint()
    |> unique_constraint(:username,
      name: :users_username_fingerprint_index
    )
    |> unique_constraint(:email_fingerprint,
      name: :users_email_fingerprint_index
    )
  end

  defp sanitize_username(changeset) do
    update_change(changeset, :username, &Username.sanitize/1)
  end

  defp normalize_email(changeset) do
    update_change(changeset, :email, fn
      nil -> nil
      "" -> nil
      email when is_binary(email) -> String.trim(email)
      value -> value
    end)
  end

  defp put_username_fingerprint(changeset) do
    username = get_field(changeset, :username)

    case Username.fingerprint(username) do
      nil -> changeset
      fingerprint -> put_change(changeset, :username_fingerprint, fingerprint)
    end
  end

  defp put_email_fingerprint(changeset) do
    email = get_change(changeset, :email)

    cond do
      is_binary(email) and byte_size(email) > 0 ->
        normalized =
          email
          |> String.trim()
          |> String.downcase()

        fingerprint = :crypto.hash(:sha256, normalized)

        changeset
        |> put_change(:email_fingerprint, fingerprint)
        |> unique_constraint(:email_fingerprint,
          name: :users_email_fingerprint_index
        )

      changeset.data.email && !get_field(changeset, :email_fingerprint) ->
        # Keep existing fingerprint when email not being updated.
        changeset

      true ->
        changeset
    end
  end
end
