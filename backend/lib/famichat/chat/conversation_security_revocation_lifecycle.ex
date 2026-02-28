defmodule Famichat.Chat.ConversationSecurityRevocationLifecycle do
  @moduledoc """
  Chat-owned revocation staging orchestration.

  Stage 1 only records revocation intents in the durable journal and marks
  them `:pending_commit`. Commit sealing and epoch advancement are a later stage.
  """
  import Ecto.Query, warn: false

  alias Famichat.Accounts.UserDevice
  alias Famichat.Chat.ConversationQueries
  alias Famichat.Chat.ConversationSecurityRevocationStore
  alias Famichat.Repo

  @max_revocation_ref_length 128
  @default_sync_fanout_limit 100

  @spec stage_client_revocation(String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def stage_client_revocation(client_id, revocation_ref, attrs \\ %{})

  def stage_client_revocation(client_id, revocation_ref, attrs)
      when is_binary(client_id) and is_binary(revocation_ref) and is_map(attrs) do
    with :ok <- validate_revocation_ref(revocation_ref),
         {:ok, user_id} <- user_id_for_client(client_id),
         {:ok, result} <-
           stage_subject_revocation(
             :client,
             client_id,
             user_id,
             revocation_ref,
             attrs
           ) do
      {:ok, result}
    end
  end

  def stage_client_revocation(_client_id, _revocation_ref, _attrs) do
    {:error, :invalid_input, %{reason: :invalid_stage_client_revocation_input}}
  end

  @spec stage_user_revocation(Ecto.UUID.t(), String.t(), map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def stage_user_revocation(user_id, revocation_ref, attrs \\ %{})

  def stage_user_revocation(user_id, revocation_ref, attrs)
      when is_binary(user_id) and is_binary(revocation_ref) and is_map(attrs) do
    with :ok <- validate_revocation_ref(revocation_ref),
         {:ok, result} <-
           stage_subject_revocation(
             :user,
             user_id,
             user_id,
             revocation_ref,
             attrs
           ) do
      {:ok, result}
    end
  end

  def stage_user_revocation(_user_id, _revocation_ref, _attrs) do
    {:error, :invalid_input, %{reason: :invalid_stage_user_revocation_input}}
  end

  @spec complete_conversation_revocation(Ecto.UUID.t(), String.t(), map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def complete_conversation_revocation(
        conversation_id,
        revocation_ref,
        attrs \\ %{}
      )

  def complete_conversation_revocation(conversation_id, revocation_ref, attrs)
      when is_binary(conversation_id) and is_binary(revocation_ref) and
             is_map(attrs) do
    with :ok <- validate_revocation_ref(revocation_ref),
         {:ok, record} <-
           ConversationSecurityRevocationStore.load_by_ref(
             conversation_id,
             revocation_ref
           ),
         {:ok, completed} <- complete_record(record, attrs) do
      {:ok, completed}
    end
  end

  def complete_conversation_revocation(
        _conversation_id,
        _revocation_ref,
        _attrs
      ) do
    {:error, :invalid_input, %{reason: :invalid_complete_revocation_input}}
  end

  @spec fail_conversation_revocation(Ecto.UUID.t(), String.t(), map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def fail_conversation_revocation(
        conversation_id,
        revocation_ref,
        attrs \\ %{}
      )

  def fail_conversation_revocation(conversation_id, revocation_ref, attrs)
      when is_binary(conversation_id) and is_binary(revocation_ref) and
             is_map(attrs) do
    with :ok <- validate_revocation_ref(revocation_ref),
         {:ok, record} <-
           ConversationSecurityRevocationStore.load_by_ref(
             conversation_id,
             revocation_ref
           ),
         {:ok, failed} <- fail_record(record, attrs) do
      {:ok, failed}
    end
  end

  def fail_conversation_revocation(_conversation_id, _revocation_ref, _attrs) do
    {:error, :invalid_input, %{reason: :invalid_fail_revocation_input}}
  end

  defp stage_subject_revocation(
         subject_type,
         subject_id,
         user_id,
         revocation_ref,
         attrs
       ) do
    conversation_ids = list_conversation_ids_for_user(user_id)
    conversation_count = length(conversation_ids)

    actor_id = fetch(attrs, :actor_id)
    revocation_reason = fetch(attrs, :revocation_reason)
    proposal_ref = fetch(attrs, :proposal_ref)
    sync_fanout_limit = sync_fanout_limit()

    stage_attrs = %{
      subject_type: subject_type,
      subject_id: subject_id,
      actor_id: actor_id,
      revocation_reason: revocation_reason
    }

    cond do
      conversation_count > sync_fanout_limit ->
        # TODO(mls-revocation): hand off to an async worker (for example Oban)
        # instead of failing when fanout exceeds the synchronous safety limit.
        {:error, :async_required,
         %{
           reason: :fanout_limit_exceeded,
           conversation_count: conversation_count,
           sync_fanout_limit: sync_fanout_limit
         }}

      true ->
        case Repo.transaction(fn ->
               Enum.reduce_while(
                 conversation_ids,
                 initial_summary(),
                 fn conversation_id, acc ->
                   case stage_for_conversation(
                          conversation_id,
                          revocation_ref,
                          stage_attrs,
                          proposal_ref
                        ) do
                     {:ok, summary_update} ->
                       {:cont, merge_summary(acc, summary_update)}

                     {:error, code, details} ->
                       Repo.rollback(
                         {code,
                          Map.put(details, :conversation_id, conversation_id)}
                       )
                   end
                 end
               )
             end) do
          {:ok, summary} ->
            {:ok,
             %{
               revocation_ref: revocation_ref,
               subject_type: subject_type,
               subject_id: subject_id,
               user_id: user_id,
               conversation_count: conversation_count,
               conversation_ids: conversation_ids,
               started_count: summary.started_count,
               existing_count: summary.existing_count,
               pending_commit_count: summary.pending_commit_count,
               completed_count: summary.completed_count
             }}

          {:error, {code, details}} ->
            {:error, code, details}
        end
    end
  end

  defp stage_for_conversation(
         conversation_id,
         revocation_ref,
         stage_attrs,
         proposal_ref
       ) do
    with {:ok, {insert_status, record}} <-
           ConversationSecurityRevocationStore.start_or_load(
             conversation_id,
             revocation_ref,
             stage_attrs
           ),
         {:ok, staged} <-
           ensure_pending_commit(
             record,
             proposal_ref,
             stage_attrs.revocation_reason
           ) do
      {:ok,
       %{
         started_count: if(insert_status == :started, do: 1, else: 0),
         existing_count: if(insert_status == :existing, do: 1, else: 0),
         pending_commit_count:
           if(staged.status == :pending_commit, do: 1, else: 0),
         completed_count: if(staged.status == :completed, do: 1, else: 0)
       }}
    end
  end

  defp ensure_pending_commit(record, _proposal_ref, _revocation_reason)
       when record.status == :pending_commit do
    {:ok, record}
  end

  defp ensure_pending_commit(record, _proposal_ref, _revocation_reason)
       when record.status == :completed do
    {:ok, record}
  end

  defp ensure_pending_commit(record, _proposal_ref, _revocation_reason)
       when record.status == :failed do
    {:error, :revocation_failed,
     %{
       reason: :revocation_previously_failed,
       revocation_id: record.id,
       revocation_ref: record.revocation_ref,
       error_code: record.error_code,
       error_reason: record.error_reason
     }}
  end

  defp ensure_pending_commit(record, proposal_ref, revocation_reason) do
    ConversationSecurityRevocationStore.mark_pending_commit(record.id, %{
      proposal_ref: proposal_ref,
      revocation_reason: revocation_reason
    })
  end

  defp complete_record(%{status: :completed} = record, _attrs),
    do: {:ok, record}

  defp complete_record(%{status: :failed} = record, _attrs) do
    {:error, :revocation_failed,
     %{
       reason: :revocation_previously_failed,
       revocation_id: record.id,
       revocation_ref: record.revocation_ref,
       error_code: record.error_code,
       error_reason: record.error_reason
     }}
  end

  defp complete_record(record, attrs) do
    with {:ok, committed_epoch} <- normalize_committed_epoch(attrs) do
      ConversationSecurityRevocationStore.mark_completed(record.id, %{
        committed_epoch: committed_epoch,
        proposal_ref: fetch(attrs, :proposal_ref),
        revocation_reason: fetch(attrs, :revocation_reason)
      })
    end
  end

  defp fail_record(%{status: :failed} = record, _attrs), do: {:ok, record}
  defp fail_record(%{status: :completed} = record, _attrs), do: {:ok, record}

  defp fail_record(record, attrs) do
    with {:ok, error_code} <- normalize_error_code(attrs) do
      ConversationSecurityRevocationStore.mark_failed(record.id, %{
        error_code: error_code,
        error_reason: fetch(attrs, :error_reason),
        revocation_reason: fetch(attrs, :revocation_reason)
      })
    end
  end

  defp normalize_committed_epoch(attrs) do
    value =
      fetch(attrs, :committed_epoch) || fetch(attrs, :recovered_epoch) ||
        fetch(attrs, :epoch)

    cond do
      is_integer(value) and value >= 0 ->
        {:ok, value}

      is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} when parsed >= 0 ->
            {:ok, parsed}

          _ ->
            {:error, :invalid_input, %{reason: :invalid_committed_epoch}}
        end

      is_nil(value) ->
        {:error, :invalid_input, %{reason: :missing_committed_epoch}}

      true ->
        {:error, :invalid_input, %{reason: :invalid_committed_epoch}}
    end
  end

  defp normalize_error_code(attrs) do
    value = fetch(attrs, :error_code)

    cond do
      is_binary(value) and byte_size(value) > 0 ->
        {:ok, value}

      is_nil(value) ->
        {:error, :invalid_input, %{reason: :missing_error_code}}

      is_atom(value) ->
        {:ok, Atom.to_string(value)}

      true ->
        {:error, :invalid_input, %{reason: :invalid_error_code}}
    end
  end

  defp list_conversation_ids_for_user(user_id) do
    sync_fanout_limit_value = sync_fanout_limit()
    ConversationQueries.for_user(user_id)
    |> select([c], c.id)
    |> order_by([c], asc: c.id)
    |> limit(^(sync_fanout_limit_value + 1))
    # Query limit+1 to detect when the user exceeds sync_fanout_limit
    |> Repo.all()
  end

  defp user_id_for_client(client_id) do
    case Repo.one(
           from d in UserDevice,
             where: d.device_id == ^client_id,
             select: d.user_id,
             limit: 1
         ) do
      user_id when is_binary(user_id) ->
        {:ok, user_id}

      _ ->
        {:error, :not_found,
         %{reason: :client_not_found, operation: :stage_client_revocation}}
    end
  end

  defp validate_revocation_ref(revocation_ref)
       when is_binary(revocation_ref) and byte_size(revocation_ref) > 0 and
              byte_size(revocation_ref) <= @max_revocation_ref_length do
    :ok
  end

  defp validate_revocation_ref(_revocation_ref) do
    {:error, :invalid_input, %{reason: :invalid_revocation_ref}}
  end

  defp initial_summary do
    %{
      started_count: 0,
      existing_count: 0,
      pending_commit_count: 0,
      completed_count: 0
    }
  end

  defp merge_summary(acc, update) do
    %{
      started_count: acc.started_count + update.started_count,
      existing_count: acc.existing_count + update.existing_count,
      pending_commit_count:
        acc.pending_commit_count + update.pending_commit_count,
      completed_count: acc.completed_count + update.completed_count
    }
  end

  defp fetch(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp sync_fanout_limit do
    case Application.get_env(
           :famichat,
           :conversation_security_revocation_sync_fanout_limit,
           @default_sync_fanout_limit
         ) do
      value when is_integer(value) and value >= 1 -> value
      _ -> @default_sync_fanout_limit
    end
  end
end
