defmodule Famichat.Chat.ConversationSecurityRecoveryStore do
  @moduledoc """
  Chat-owned persistence boundary for conversation-security recovery journal entries.
  """
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Famichat.Chat.ConversationSecurityRecovery
  alias Famichat.Repo

  @max_recovery_ref_length 128

  @type record_payload :: %{
          id: Ecto.UUID.t(),
          conversation_id: Ecto.UUID.t(),
          recovery_ref: String.t(),
          status: ConversationSecurityRecovery.status(),
          recovery_reason: String.t() | nil,
          error_code: String.t() | nil,
          error_reason: String.t() | nil,
          recovered_epoch: non_neg_integer() | nil,
          audit_id: String.t() | nil,
          group_state_ref: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @spec load_by_ref(Ecto.UUID.t(), String.t()) ::
          {:ok, record_payload()} | {:error, atom(), map()}
  def load_by_ref(conversation_id, recovery_ref)
      when is_binary(conversation_id) and is_binary(recovery_ref) and
             byte_size(recovery_ref) > 0 and
             byte_size(recovery_ref) <= @max_recovery_ref_length do
    case Repo.one(
           from r in ConversationSecurityRecovery,
             where:
               r.conversation_id == ^conversation_id and
                 r.recovery_ref == ^recovery_ref,
             limit: 1
         ) do
      %ConversationSecurityRecovery{} = record ->
        {:ok, to_payload(record)}

      nil ->
        {:error, :not_found, %{reason: :missing_recovery}}
    end
  end

  def load_by_ref(_conversation_id, _recovery_ref) do
    {:error, :invalid_input, %{reason: :invalid_load_by_ref_input}}
  end

  @spec start_or_load(Ecto.UUID.t(), String.t(), map()) ::
          {:ok, {:started | :existing, record_payload()}}
          | {:error, atom(), map()}
  def start_or_load(conversation_id, recovery_ref, attrs \\ %{})

  def start_or_load(conversation_id, recovery_ref, attrs)
      when is_binary(conversation_id) and is_binary(recovery_ref) and
             byte_size(recovery_ref) > 0 and
             byte_size(recovery_ref) <= @max_recovery_ref_length and
             is_map(attrs) do
    insert_attrs = %{
      conversation_id: conversation_id,
      recovery_ref: recovery_ref,
      status: :in_progress,
      recovery_reason: to_optional_string(Map.get(attrs, :recovery_reason))
    }

    case %ConversationSecurityRecovery{}
         |> ConversationSecurityRecovery.create_changeset(insert_attrs)
         |> Repo.insert() do
      {:ok, record} ->
        {:ok, {:started, to_payload(record)}}

      {:error, %Changeset{} = changeset} ->
        if unique_recovery_ref_conflict?(changeset) do
          case load_by_ref(conversation_id, recovery_ref) do
            {:ok, record} -> {:ok, {:existing, record}}
            {:error, code, details} -> {:error, code, details}
          end
        else
          {:error, :invalid_input,
           %{
             reason: :invalid_recovery_record,
             operation: :start_or_load
           }}
        end
    end
  end

  def start_or_load(_conversation_id, _recovery_ref, _attrs) do
    {:error, :invalid_input, %{reason: :invalid_start_or_load_input}}
  end

  @spec mark_completed(Ecto.UUID.t(), map()) ::
          {:ok, record_payload()} | {:error, atom(), map()}
  def mark_completed(recovery_id, attrs)
      when is_binary(recovery_id) and is_map(attrs) do
    with {:ok, record} <- load_by_id(recovery_id) do
      case record.status do
        :completed ->
          {:ok, record}

        :failed ->
          {:error, :invalid_state_transition,
           %{reason: :recovery_already_failed, operation: :mark_completed}}

        :in_progress ->
          update_completed(record, attrs)
      end
    end
  end

  def mark_completed(_recovery_id, _attrs) do
    {:error, :invalid_input, %{reason: :invalid_mark_completed_input}}
  end

  @spec mark_failed(Ecto.UUID.t(), map()) ::
          {:ok, record_payload()} | {:error, atom(), map()}
  def mark_failed(recovery_id, attrs)
      when is_binary(recovery_id) and is_map(attrs) do
    with {:ok, record} <- load_by_id(recovery_id) do
      case record.status do
        :completed ->
          {:ok, record}

        :failed ->
          {:ok, record}

        :in_progress ->
          update_failed(record, attrs)
      end
    end
  end

  def mark_failed(_recovery_id, _attrs) do
    {:error, :invalid_input, %{reason: :invalid_mark_failed_input}}
  end

  @spec list_for_conversation(Ecto.UUID.t()) ::
          {:ok, [record_payload()]} | {:error, atom(), map()}
  def list_for_conversation(conversation_id)
      when is_binary(conversation_id) do
    recoveries =
      from(r in ConversationSecurityRecovery,
        where: r.conversation_id == ^conversation_id,
        order_by: [desc: r.inserted_at]
      )
      |> Repo.all()
      |> Enum.map(&to_payload/1)

    {:ok, recoveries}
  rescue
    _ ->
      {:error, :storage_inconsistent,
       %{reason: :list_recoveries_failed, operation: :list_for_conversation}}
  end

  def list_for_conversation(_conversation_id) do
    {:error, :invalid_input, %{reason: :invalid_conversation_id}}
  end

  defp load_by_id(recovery_id) do
    case Repo.get(ConversationSecurityRecovery, recovery_id) do
      %ConversationSecurityRecovery{} = record ->
        {:ok, to_payload(record)}

      nil ->
        {:error, :not_found,
         %{reason: :missing_recovery, operation: :load_by_id}}
    end
  end

  defp update_completed(record, attrs) do
    recovery_reason =
      to_optional_string(
        Map.get(attrs, :recovery_reason) || Map.get(attrs, "recovery_reason")
      )

    update_attrs =
      %{
        recovered_epoch:
          Map.get(attrs, :recovered_epoch) || Map.get(attrs, "recovered_epoch"),
        audit_id: Map.get(attrs, :audit_id) || Map.get(attrs, "audit_id"),
        group_state_ref:
          Map.get(attrs, :group_state_ref) ||
            Map.get(attrs, "group_state_ref")
      }
      |> maybe_put(:recovery_reason, recovery_reason)

    changeset =
      record
      |> from_payload()
      |> ConversationSecurityRecovery.complete_changeset(update_attrs)

    case Repo.update(changeset) do
      {:ok, updated} ->
        {:ok, to_payload(updated)}

      {:error, _changeset} ->
        {:error, :storage_inconsistent,
         %{reason: :mark_completed_failed, operation: :mark_completed}}
    end
  end

  defp update_failed(record, attrs) do
    recovery_reason =
      to_optional_string(
        Map.get(attrs, :recovery_reason) || Map.get(attrs, "recovery_reason")
      )

    update_attrs =
      %{
        error_code:
          to_optional_string(
            Map.get(attrs, :error_code) || Map.get(attrs, "error_code")
          ),
        error_reason:
          to_optional_string(
            Map.get(attrs, :error_reason) || Map.get(attrs, "error_reason")
          )
      }
      |> maybe_put(:recovery_reason, recovery_reason)

    changeset =
      record
      |> from_payload()
      |> ConversationSecurityRecovery.failed_changeset(update_attrs)

    case Repo.update(changeset) do
      {:ok, updated} ->
        {:ok, to_payload(updated)}

      {:error, _changeset} ->
        {:error, :storage_inconsistent,
         %{reason: :mark_failed_failed, operation: :mark_failed}}
    end
  end

  defp to_payload(%ConversationSecurityRecovery{} = record) do
    %{
      id: record.id,
      conversation_id: record.conversation_id,
      recovery_ref: record.recovery_ref,
      status: record.status,
      recovery_reason: record.recovery_reason,
      error_code: record.error_code,
      error_reason: record.error_reason,
      recovered_epoch: record.recovered_epoch,
      audit_id: record.audit_id,
      group_state_ref: record.group_state_ref,
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }
  end

  defp from_payload(payload) do
    %ConversationSecurityRecovery{
      id: payload.id,
      conversation_id: payload.conversation_id,
      recovery_ref: payload.recovery_ref,
      status: payload.status,
      recovery_reason: payload.recovery_reason,
      error_code: payload.error_code,
      error_reason: payload.error_reason,
      recovered_epoch: payload.recovered_epoch,
      audit_id: payload.audit_id,
      group_state_ref: payload.group_state_ref,
      inserted_at: payload.inserted_at,
      updated_at: payload.updated_at
    }
  end

  defp unique_recovery_ref_conflict?(%Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn {field, {_msg, opts}} ->
      field == :recovery_ref and
        Keyword.get(opts, :constraint) == :unique and
        Keyword.get(opts, :constraint_name) ==
          "conversation_security_recoveries_conversation_ref_index"
    end)
  end

  defp to_optional_string(nil), do: nil
  defp to_optional_string(value) when is_binary(value), do: value
  defp to_optional_string(value) when is_atom(value), do: Atom.to_string(value)

  defp to_optional_string(value) when is_integer(value),
    do: Integer.to_string(value)

  defp to_optional_string(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
