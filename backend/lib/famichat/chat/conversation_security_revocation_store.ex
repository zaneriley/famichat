defmodule Famichat.Chat.ConversationSecurityRevocationStore do
  @moduledoc """
  Chat-owned persistence boundary for conversation-security revocation journal entries.
  """
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Famichat.Chat.ConversationSecurityRevocation
  alias Famichat.Repo

  @max_revocation_ref_length 128

  @type record_payload :: %{
          id: Ecto.UUID.t(),
          conversation_id: Ecto.UUID.t(),
          revocation_ref: String.t(),
          status: ConversationSecurityRevocation.status(),
          subject_type: ConversationSecurityRevocation.subject_type(),
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

  @spec load_by_ref(Ecto.UUID.t(), String.t()) ::
          {:ok, record_payload()} | {:error, atom(), map()}
  def load_by_ref(conversation_id, revocation_ref)
      when is_binary(conversation_id) and is_binary(revocation_ref) and
             byte_size(revocation_ref) > 0 and
             byte_size(revocation_ref) <= @max_revocation_ref_length do
    case Repo.one(
           from r in ConversationSecurityRevocation,
             where:
               r.conversation_id == ^conversation_id and
                 r.revocation_ref == ^revocation_ref,
             limit: 1
         ) do
      %ConversationSecurityRevocation{} = record ->
        {:ok, to_payload(record)}

      nil ->
        {:error, :not_found, %{reason: :missing_revocation}}
    end
  end

  def load_by_ref(_conversation_id, _revocation_ref) do
    {:error, :invalid_input, %{reason: :invalid_load_by_ref_input}}
  end

  @spec start_or_load(Ecto.UUID.t(), String.t(), map()) ::
          {:ok, {:started | :existing, record_payload()}}
          | {:error, atom(), map()}
  def start_or_load(conversation_id, revocation_ref, attrs \\ %{})

  def start_or_load(conversation_id, revocation_ref, attrs)
      when is_binary(conversation_id) and is_binary(revocation_ref) and
             byte_size(revocation_ref) > 0 and
             byte_size(revocation_ref) <= @max_revocation_ref_length and
             is_map(attrs) do
    with {:ok, subject_type} <- normalize_subject_type(attrs),
         {:ok, subject_id} <- normalize_subject_id(attrs) do
      insert_attrs = %{
        conversation_id: conversation_id,
        revocation_ref: revocation_ref,
        status: :in_progress,
        subject_type: subject_type,
        subject_id: subject_id,
        revocation_reason: to_optional_string(fetch(attrs, :revocation_reason)),
        actor_id: fetch(attrs, :actor_id)
      }

      case %ConversationSecurityRevocation{}
           |> ConversationSecurityRevocation.create_changeset(insert_attrs)
           |> Repo.insert(mode: :savepoint) do
        {:ok, record} ->
          {:ok, {:started, to_payload(record)}}

        {:error, %Changeset{} = changeset} ->
          if unique_revocation_ref_conflict?(changeset) do
            case load_by_ref(conversation_id, revocation_ref) do
              {:ok, record} ->
                with :ok <-
                       ensure_subject_consistency(
                         record,
                         subject_type,
                         subject_id
                       ) do
                  {:ok, {:existing, record}}
                end

              {:error, code, details} ->
                {:error, code, details}
            end
          else
            {:error, :invalid_input,
             %{
               reason: :invalid_revocation_record,
               operation: :start_or_load
             }}
          end
      end
    end
  end

  def start_or_load(_conversation_id, _revocation_ref, _attrs) do
    {:error, :invalid_input, %{reason: :invalid_start_or_load_input}}
  end

  @spec mark_pending_commit(Ecto.UUID.t(), map()) ::
          {:ok, record_payload()} | {:error, atom(), map()}
  def mark_pending_commit(revocation_id, attrs \\ %{})

  def mark_pending_commit(revocation_id, attrs)
      when is_binary(revocation_id) and is_map(attrs) do
    with {:ok, record} <- load_record_by_id(revocation_id) do
      case record.status do
        :pending_commit ->
          {:ok, to_payload(record)}

        :completed ->
          {:ok, to_payload(record)}

        :failed ->
          {:error, :invalid_state_transition,
           %{
             reason: :revocation_already_failed,
             operation: :mark_pending_commit
           }}

        :in_progress ->
          update_pending_commit(record, attrs)
      end
    end
  end

  def mark_pending_commit(_revocation_id, _attrs) do
    {:error, :invalid_input, %{reason: :invalid_mark_pending_commit_input}}
  end

  @spec mark_completed(Ecto.UUID.t(), map()) ::
          {:ok, record_payload()} | {:error, atom(), map()}
  def mark_completed(revocation_id, attrs)
      when is_binary(revocation_id) and is_map(attrs) do
    with {:ok, record} <- load_record_by_id(revocation_id) do
      case record.status do
        :completed ->
          {:ok, to_payload(record)}

        :failed ->
          {:error, :invalid_state_transition,
           %{reason: :revocation_already_failed, operation: :mark_completed}}

        :in_progress ->
          update_completed(record, attrs)

        :pending_commit ->
          update_completed(record, attrs)
      end
    end
  end

  def mark_completed(_revocation_id, _attrs) do
    {:error, :invalid_input, %{reason: :invalid_mark_completed_input}}
  end

  @spec mark_failed(Ecto.UUID.t(), map()) ::
          {:ok, record_payload()} | {:error, atom(), map()}
  def mark_failed(revocation_id, attrs)
      when is_binary(revocation_id) and is_map(attrs) do
    with {:ok, record} <- load_record_by_id(revocation_id) do
      case record.status do
        :completed ->
          {:ok, to_payload(record)}

        :failed ->
          {:ok, to_payload(record)}

        :in_progress ->
          update_failed(record, attrs)

        :pending_commit ->
          update_failed(record, attrs)
      end
    end
  end

  def mark_failed(_revocation_id, _attrs) do
    {:error, :invalid_input, %{reason: :invalid_mark_failed_input}}
  end

  @spec list_for_conversation(Ecto.UUID.t()) ::
          {:ok, [record_payload()]} | {:error, atom(), map()}
  def list_for_conversation(conversation_id)
      when is_binary(conversation_id) do
    revocations =
      from(r in ConversationSecurityRevocation,
        where: r.conversation_id == ^conversation_id,
        order_by: [desc: r.inserted_at]
      )
      |> Repo.all()
      |> Enum.map(&to_payload/1)

    {:ok, revocations}
  rescue
    _ ->
      {:error, :storage_inconsistent,
       %{reason: :list_revocations_failed, operation: :list_for_conversation}}
  end

  def list_for_conversation(_conversation_id) do
    {:error, :invalid_input, %{reason: :invalid_conversation_id}}
  end

  @spec list_active_for_conversation(Ecto.UUID.t()) ::
          {:ok, [record_payload()]} | {:error, atom(), map()}
  def list_active_for_conversation(conversation_id)
      when is_binary(conversation_id) do
    revocations =
      from(r in ConversationSecurityRevocation,
        where:
          r.conversation_id == ^conversation_id and
            r.status in [:in_progress, :pending_commit],
        order_by: [asc: r.inserted_at]
      )
      |> Repo.all()
      |> Enum.map(&to_payload/1)

    {:ok, revocations}
  rescue
    _ ->
      {:error, :storage_inconsistent,
       %{
         reason: :list_active_revocations_failed,
         operation: :list_active_for_conversation
       }}
  end

  def list_active_for_conversation(_conversation_id) do
    {:error, :invalid_input, %{reason: :invalid_conversation_id}}
  end

  defp load_record_by_id(revocation_id) do
    case Repo.get(ConversationSecurityRevocation, revocation_id) do
      %ConversationSecurityRevocation{} = record ->
        {:ok, record}

      nil ->
        {:error, :not_found,
         %{reason: :missing_revocation, operation: :load_by_id}}
    end
  end

  defp update_pending_commit(record, attrs) do
    update_attrs = %{
      proposal_ref: to_optional_string(fetch(attrs, :proposal_ref)),
      revocation_reason: to_optional_string(fetch(attrs, :revocation_reason))
    }

    changeset =
      ConversationSecurityRevocation.pending_commit_changeset(
        record,
        update_attrs
      )

    case Repo.update(changeset) do
      {:ok, updated} ->
        {:ok, to_payload(updated)}

      {:error, _changeset} ->
        {:error, :storage_inconsistent,
         %{reason: :mark_pending_commit_failed, operation: :mark_pending_commit}}
    end
  end

  defp update_completed(record, attrs) do
    update_attrs = %{
      committed_epoch:
        fetch(attrs, :committed_epoch) || fetch(attrs, :recovered_epoch),
      proposal_ref: to_optional_string(fetch(attrs, :proposal_ref)),
      revocation_reason: to_optional_string(fetch(attrs, :revocation_reason))
    }

    changeset =
      ConversationSecurityRevocation.complete_changeset(record, update_attrs)

    case Repo.update(changeset) do
      {:ok, updated} ->
        {:ok, to_payload(updated)}

      {:error, _changeset} ->
        {:error, :storage_inconsistent,
         %{reason: :mark_completed_failed, operation: :mark_completed}}
    end
  end

  defp update_failed(record, attrs) do
    update_attrs = %{
      error_code: to_optional_string(fetch(attrs, :error_code)),
      error_reason: to_optional_string(fetch(attrs, :error_reason)),
      revocation_reason: to_optional_string(fetch(attrs, :revocation_reason))
    }

    changeset =
      ConversationSecurityRevocation.failed_changeset(record, update_attrs)

    case Repo.update(changeset) do
      {:ok, updated} ->
        {:ok, to_payload(updated)}

      {:error, _changeset} ->
        {:error, :storage_inconsistent,
         %{reason: :mark_failed_failed, operation: :mark_failed}}
    end
  end

  defp normalize_subject_type(attrs) do
    case fetch(attrs, :subject_type) do
      :client -> {:ok, :client}
      "client" -> {:ok, :client}
      :user -> {:ok, :user}
      "user" -> {:ok, :user}
      _ -> {:error, :invalid_input, %{reason: :invalid_subject_type}}
    end
  end

  defp normalize_subject_id(attrs) do
    case fetch(attrs, :subject_id) do
      value when is_binary(value) and byte_size(value) > 0 ->
        {:ok, value}

      _ ->
        {:error, :invalid_input, %{reason: :invalid_subject_id}}
    end
  end

  defp fetch(attrs, key) when is_atom(key) and is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp to_payload(%ConversationSecurityRevocation{} = record) do
    %{
      id: record.id,
      conversation_id: record.conversation_id,
      revocation_ref: record.revocation_ref,
      status: record.status,
      subject_type: record.subject_type,
      subject_id: record.subject_id,
      revocation_reason: record.revocation_reason,
      actor_id: record.actor_id,
      error_code: record.error_code,
      error_reason: record.error_reason,
      committed_epoch: record.committed_epoch,
      proposal_ref: record.proposal_ref,
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }
  end

  defp unique_revocation_ref_conflict?(%Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn {field, {_msg, opts}} ->
      field == :revocation_ref and
        Keyword.get(opts, :constraint) == :unique and
        Keyword.get(opts, :constraint_name) ==
          "conversation_security_revocations_conversation_ref_index"
    end)
  end

  defp ensure_subject_consistency(record, subject_type, subject_id) do
    if record.subject_type == subject_type and record.subject_id == subject_id do
      :ok
    else
      {:error, :idempotency_conflict,
       %{
         reason: :revocation_ref_subject_mismatch,
         expected_subject_type: record.subject_type,
         expected_subject_id: record.subject_id,
         received_subject_type: subject_type,
         received_subject_id: subject_id
       }}
    end
  end

  defp to_optional_string(nil), do: nil
  defp to_optional_string(value) when is_binary(value), do: value
  defp to_optional_string(value) when is_atom(value), do: Atom.to_string(value)

  defp to_optional_string(value) when is_integer(value),
    do: Integer.to_string(value)

  defp to_optional_string(_value), do: nil
end
