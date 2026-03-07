defmodule Famichat.Auth.Passkeys.Challenge do
  @moduledoc """
  WebAuthn challenge persistence layer.

  Challenges are single-use and expire based on token TTLs:
  * Registration: #{Famichat.Auth.Tokens.Policy.default_ttl(:passkey_registration)} seconds
  * Assertion: #{Famichat.Auth.Tokens.Policy.default_ttl(:passkey_assertion)} seconds

  Consumed challenges are soft-deleted via `consumed_at`. A periodic cleanup job
  should remove expired or consumed rows to keep the table lean.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Famichat.Accounts.User

  @typedoc "Supported WebAuthn challenge types."
  @type challenge_type :: :registration | :assertion

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t(),
          type: challenge_type(),
          challenge: binary(),
          expires_at: DateTime.t(),
          consumed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "webauthn_challenges" do
    belongs_to :user, User

    field :type, Ecto.Enum,
      values: [registration: "registration", assertion: "assertion"]

    field :challenge, :binary
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(challenge, attrs) do
    challenge
    |> cast(attrs, [:user_id, :type, :challenge, :expires_at, :consumed_at])
    |> validate_required([:user_id, :type, :challenge, :expires_at])
  end

  @doc """
  Changeset for discoverable assertion challenges (no user_id required).

  WebAuthn discoverable credentials (resident keys) allow the authenticator
  to identify the user, so the challenge is not bound to a specific user.
  """
  @spec discoverable_changeset(t(), map()) :: Ecto.Changeset.t()
  def discoverable_changeset(challenge, attrs) do
    challenge
    |> cast(attrs, [:type, :challenge, :expires_at])
    |> validate_required([:type, :challenge, :expires_at])
  end
end
