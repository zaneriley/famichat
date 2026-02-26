defmodule Famichat.Chat.ConversationSecurityRecovery do
  @moduledoc """
  Durable conversation-security recovery journal entry.

  Write owner: `Famichat.Chat.ConversationSecurityRecoveryStore`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Famichat.Chat.Conversation

  @statuses [:in_progress, :completed, :failed]
  @max_recovery_ref_length 128

  @type status :: :in_progress | :completed | :failed

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          conversation_id: Ecto.UUID.t(),
          recovery_ref: String.t(),
          status: status(),
          recovery_reason: String.t() | nil,
          error_code: String.t() | nil,
          error_reason: String.t() | nil,
          recovered_epoch: non_neg_integer() | nil,
          audit_id: String.t() | nil,
          group_state_ref: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "conversation_security_recoveries" do
    belongs_to :conversation, Conversation
    field :recovery_ref, :string
    field :status, Ecto.Enum, values: @statuses, default: :in_progress
    field :recovery_reason, :string
    field :error_code, :string
    field :error_reason, :string
    field :recovered_epoch, :integer
    field :audit_id, :string
    field :group_state_ref, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :conversation_id,
      :recovery_ref,
      :status,
      :recovery_reason,
      :error_code,
      :error_reason,
      :recovered_epoch,
      :audit_id,
      :group_state_ref
    ])
    |> validate_required([:conversation_id, :recovery_ref, :status])
    |> validate_length(:recovery_ref,
      min: 1,
      max: @max_recovery_ref_length
    )
    |> validate_number(:recovered_epoch, greater_than_or_equal_to: 0)
    |> unique_constraint(:recovery_ref,
      name: :conversation_security_recoveries_conversation_ref_index
    )
  end

  @doc false
  @spec complete_changeset(t() | Ecto.Changeset.t(), map()) ::
          Ecto.Changeset.t()
  def complete_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :recovered_epoch,
      :audit_id,
      :group_state_ref,
      :recovery_reason
    ])
    |> put_change(:status, :completed)
    |> put_change(:error_code, nil)
    |> put_change(:error_reason, nil)
    |> validate_required([:recovered_epoch])
    |> validate_number(:recovered_epoch, greater_than_or_equal_to: 0)
  end

  @doc false
  @spec failed_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def failed_changeset(record, attrs) do
    record
    |> cast(attrs, [:error_code, :error_reason, :recovery_reason])
    |> put_change(:status, :failed)
    |> validate_required([:error_code])
  end
end
