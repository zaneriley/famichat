defmodule Famichat.Accounts.UserToken do
  @moduledoc """
  Ledgered authentication tokens (invite, magic link, OTP, etc.).

  Write owner: `Famichat.Auth.Tokens.Storage`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Famichat.Accounts.User

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          context: String.t(),
          kind: String.t() | nil,
          audience: String.t() | nil,
          subject_id: String.t() | nil,
          token_hash: binary(),
          payload: map(),
          expires_at: DateTime.t(),
          used_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_tokens" do
    belongs_to :user, User
    field :context, :string
    field :kind, :string
    field :audience, :string
    field :subject_id, :string
    field :token_hash, :binary
    field :payload, :map, default: %{}
    field :expires_at, :utc_datetime_usec
    field :used_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :user_id,
      :context,
      :kind,
      :audience,
      :subject_id,
      :token_hash,
      :payload,
      :expires_at,
      :used_at
    ])
    |> validate_required([:context, :token_hash, :payload, :expires_at])
    |> validate_length(:context, min: 2)
    |> unique_constraint(:context_token_hash,
      name: :user_tokens_context_token_hash_index,
      message: "token already issued"
    )
  end
end
