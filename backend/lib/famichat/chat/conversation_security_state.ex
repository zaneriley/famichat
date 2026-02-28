defmodule Famichat.Chat.ConversationSecurityState do
  @moduledoc """
  Durable conversation security state record.

  Write owner: `Famichat.Chat.ConversationSecurityStateStore`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Famichat.Chat.Conversation

  @type t :: %__MODULE__{
          conversation_id: Ecto.UUID.t(),
          protocol: String.t(),
          state_ciphertext: binary(),
          state_format: String.t(),
          epoch: non_neg_integer(),
          pending_commit_ciphertext: binary() | nil,
          pending_commit_format: String.t() | nil,
          snapshot_mac: String.t() | nil,
          lock_version: pos_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key false
  @foreign_key_type :binary_id
  schema "conversation_security_states" do
    belongs_to :conversation, Conversation, primary_key: true
    field :protocol, :string, default: "mls"
    field :state_ciphertext, :binary
    field :state_format, :string, default: "vault_term_v1"
    field :epoch, :integer, default: 0
    field :pending_commit_ciphertext, :binary
    field :pending_commit_format, :string
    field :snapshot_mac, :string
    field :lock_version, :integer, default: 1

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :conversation_id,
      :protocol,
      :state_ciphertext,
      :state_format,
      :epoch,
      :pending_commit_ciphertext,
      :pending_commit_format,
      :lock_version
    ])
    |> validate_required([
      :conversation_id,
      :protocol,
      :state_ciphertext,
      :state_format,
      :epoch,
      :lock_version
    ])
    |> validate_number(:epoch, greater_than_or_equal_to: 0)
    |> validate_number(:lock_version, greater_than_or_equal_to: 1)
  end
end
