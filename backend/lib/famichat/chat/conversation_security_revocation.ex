defmodule Famichat.Chat.ConversationSecurityRevocation do
  @moduledoc """
  Durable conversation-security revocation journal entry.

  Write owner: `Famichat.Chat.ConversationSecurityRevocationStore`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Famichat.Chat.Conversation

  @statuses [:in_progress, :pending_commit, :completed, :failed]
  @subject_types [:client, :user]
  @max_revocation_ref_length 128

  @type status :: :in_progress | :pending_commit | :completed | :failed
  @type subject_type :: :client | :user

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          conversation_id: Ecto.UUID.t(),
          revocation_ref: String.t(),
          status: status(),
          subject_type: subject_type(),
          subject_id: String.t(),
          revocation_reason: String.t() | nil,
          actor_id: Ecto.UUID.t() | nil,
          error_code: String.t() | nil,
          error_reason: String.t() | nil,
          committed_epoch: non_neg_integer() | nil,
          proposal_ref: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "conversation_security_revocations" do
    belongs_to :conversation, Conversation
    field :revocation_ref, :string
    field :status, Ecto.Enum, values: @statuses, default: :in_progress
    field :subject_type, Ecto.Enum, values: @subject_types
    field :subject_id, :string
    field :revocation_reason, :string
    field :actor_id, :binary_id
    field :error_code, :string
    field :error_reason, :string
    field :committed_epoch, :integer
    field :proposal_ref, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :conversation_id,
      :revocation_ref,
      :status,
      :subject_type,
      :subject_id,
      :revocation_reason,
      :actor_id,
      :error_code,
      :error_reason,
      :committed_epoch,
      :proposal_ref
    ])
    |> validate_required([
      :conversation_id,
      :revocation_ref,
      :status,
      :subject_type,
      :subject_id
    ])
    |> validate_length(:revocation_ref,
      min: 1,
      max: @max_revocation_ref_length
    )
    |> validate_number(:committed_epoch, greater_than_or_equal_to: 0)
    |> unique_constraint(:revocation_ref,
      name: :conversation_security_revocations_conversation_ref_index
    )
  end

  @doc false
  @spec pending_commit_changeset(t() | Ecto.Changeset.t(), map()) ::
          Ecto.Changeset.t()
  def pending_commit_changeset(record, attrs) do
    record
    |> cast(attrs, [:proposal_ref, :revocation_reason])
    |> put_change(:status, :pending_commit)
    |> put_change(:error_code, nil)
    |> put_change(:error_reason, nil)
  end

  @doc false
  @spec complete_changeset(t() | Ecto.Changeset.t(), map()) ::
          Ecto.Changeset.t()
  def complete_changeset(record, attrs) do
    record
    |> cast(attrs, [:committed_epoch, :proposal_ref, :revocation_reason])
    |> put_change(:status, :completed)
    |> put_change(:error_code, nil)
    |> put_change(:error_reason, nil)
    |> validate_required([:committed_epoch])
    |> validate_number(:committed_epoch, greater_than_or_equal_to: 0)
  end

  @doc false
  @spec failed_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def failed_changeset(record, attrs) do
    record
    |> cast(attrs, [:error_code, :error_reason, :revocation_reason])
    |> put_change(:status, :failed)
    |> validate_required([:error_code])
  end
end
