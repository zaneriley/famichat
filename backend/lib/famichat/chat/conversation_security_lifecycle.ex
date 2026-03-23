defmodule Famichat.Chat.ConversationSecurityLifecycle do
  @moduledoc """
  Chat-owned MLS lifecycle orchestration on top of durable conversation security state.

  This module enforces pending-commit and epoch semantics while keeping
  persistence ownership in `Famichat.Chat`.
  """

  alias Famichat.Chat.ConversationSecurityRevocationStore
  alias Famichat.Chat.ConversationSecurityStateStore
  alias Famichat.Crypto.MLS
  alias Famichat.Repo

  @supported_stage_operations [:mls_commit, :mls_update, :mls_add, :mls_remove]
  @snapshot_keys [
    "session_sender_storage",
    "session_recipient_storage",
    "session_sender_signer",
    "session_recipient_signer",
    "session_cache"
  ]
  @snapshot_atom_keys Enum.map(@snapshot_keys, &String.to_atom/1)
  @supported_stage_operation_strings Enum.map(
                                       @supported_stage_operations,
                                       &Atom.to_string/1
                                     )

  @spec stage_pending_commit(Ecto.UUID.t(), atom(), map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def stage_pending_commit(conversation_id, operation, attrs \\ %{})

  def stage_pending_commit(conversation_id, operation, attrs)
      when operation in @supported_stage_operations and
             is_binary(conversation_id) and is_map(attrs) do
    with {:ok, state} <- load_state(conversation_id, :stage_pending_commit),
         :ok <- ensure_no_pending_commit(state, operation),
         {:ok, attrs} <- maybe_resolve_remove_target(operation, state, attrs),
         request <- build_request(state, attrs),
         {:ok, payload} <- apply(MLS, operation, [request]),
         :ok <- validate_stage_payload(payload, conversation_id, operation),
         {:ok, staged_epoch} <- staged_epoch(payload, state.epoch),
         pending_commit <-
           build_pending_commit(operation, staged_epoch, payload) do
      persist_state(state, %{pending_commit: pending_commit})
    end
  end

  def stage_pending_commit(_conversation_id, _operation, _attrs) do
    {:error, :invalid_input,
     %{reason: :unsupported_stage_operation, operation: :stage_pending_commit}}
  end

  @spec merge_pending_commit(Ecto.UUID.t(), map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def merge_pending_commit(conversation_id, attrs \\ %{})

  def merge_pending_commit(conversation_id, attrs)
      when is_binary(conversation_id) and is_map(attrs) do
    with {:ok, state} <- load_state(conversation_id, :merge_pending_commit),
         {:ok, pending_commit} <- pending_commit_from_state(state),
         :ok <- validate_pending_operation(pending_commit),
         :ok <-
           validate_operation_matches_active_revocations(
             conversation_id,
             pending_commit
           ),
         {:ok, merge_epoch} <-
           pending_commit_epoch(pending_commit, state.epoch),
         request <-
           build_request(
             state,
             attrs
             |> Map.put_new(:staged_commit_validated, true)
             |> Map.put_new(:epoch, merge_epoch)
           ),
         {:ok, payload} <- MLS.merge_staged_commit(request),
         :ok <- validate_merge_payload(payload, conversation_id),
         {:ok, next_state, next_epoch} <-
           resolve_merge_payload(state, payload, merge_epoch),
         seal_active_revocations? = pending_remove_operation?(pending_commit) do
      persist_merged_state_and_complete_revocations(
        state,
        next_state,
        next_epoch,
        seal_active_revocations?
      )
    end
  end

  def merge_pending_commit(_conversation_id, _attrs) do
    {:error, :invalid_input,
     %{reason: :invalid_input, operation: :merge_pending_commit}}
  end

  @spec clear_pending_commit(Ecto.UUID.t(), map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def clear_pending_commit(conversation_id, attrs \\ %{})

  def clear_pending_commit(conversation_id, attrs)
      when is_binary(conversation_id) and is_map(attrs) do
    with {:ok, state} <- load_state(conversation_id, :clear_pending_commit) do
      if is_map(state.pending_commit) do
        request = build_request(state, attrs)

        with {:ok, _payload} <- MLS.clear_pending_commit(request) do
          persist_state(state, %{pending_commit: nil})
        end
      else
        {:ok, state}
      end
    end
  end

  def clear_pending_commit(_conversation_id, _attrs) do
    {:error, :invalid_input,
     %{reason: :invalid_input, operation: :clear_pending_commit}}
  end

  defp load_state(conversation_id, operation) do
    case ConversationSecurityStateStore.load(conversation_id) do
      {:ok, state} ->
        {:ok, state}

      {:error, :not_found, _details} ->
        {:error, :storage_inconsistent,
         %{reason: :missing_state, operation: operation}}

      {:error, code, details} ->
        {:error, map_store_error(code),
         Map.put_new(details, :operation, operation)}
    end
  end

  defp ensure_no_pending_commit(%{pending_commit: %{}}, operation) do
    {:error, :pending_proposals,
     %{reason: :pending_commit_already_staged, operation: operation}}
  end

  defp ensure_no_pending_commit(_state, _operation), do: :ok

  defp pending_commit_from_state(%{pending_commit: %{} = pending_commit}) do
    {:ok, pending_commit}
  end

  defp pending_commit_from_state(_state) do
    {:error, :commit_rejected,
     %{reason: :no_pending_commit, operation: :merge_pending_commit}}
  end

  defp pending_commit_epoch(pending_commit, current_epoch) do
    value =
      Map.get(pending_commit, "staged_epoch") ||
        Map.get(pending_commit, :staged_epoch)

    cond do
      is_integer(value) and value == current_epoch + 1 ->
        {:ok, value}

      is_integer(value) and value <= current_epoch ->
        {:error, :commit_rejected,
         %{
           reason: :epoch_too_low,
           operation: :merge_pending_commit,
           current_epoch: current_epoch,
           staged_epoch: value
         }}

      is_integer(value) ->
        {:error, :commit_rejected,
         %{
           reason: :epoch_too_high,
           operation: :merge_pending_commit,
           current_epoch: current_epoch,
           staged_epoch: value
         }}

      true ->
        {:error, :commit_rejected,
         %{
           reason: :epoch_malformed,
           operation: :merge_pending_commit,
           current_epoch: current_epoch,
           staged_epoch: value
         }}
    end
  end

  defp staged_epoch(payload, current_epoch) do
    case extract_epoch(payload) do
      :missing ->
        {:ok, current_epoch + 1}

      {:ok, value} when value == current_epoch + 1 ->
        {:ok, value}

      value ->
        staged_epoch =
          case value do
            {:ok, parsed} -> parsed
            {:invalid, raw} -> raw
            other -> other
          end

        {:error, :commit_rejected,
         %{
           reason: :invalid_staged_epoch,
           operation: :stage_pending_commit,
           current_epoch: current_epoch,
           staged_epoch: staged_epoch
         }}
    end
  end

  defp resolve_merge_payload(state, payload, merge_epoch)
       when is_map(payload) do
    with :ok <- validate_merge_epoch(payload, merge_epoch),
         :ok <- validate_snapshot_payload(payload) do
      next_state = extract_snapshot(payload) || state.state
      next_epoch = merged_epoch_from_payload(payload, merge_epoch)
      {:ok, next_state, next_epoch}
    end
  end

  defp resolve_merge_payload(state, _payload, merge_epoch) do
    {:ok, state.state, merge_epoch}
  end

  defp validate_merge_epoch(payload, merge_epoch) do
    case extract_epoch(payload) do
      :missing ->
        :ok

      {:ok, value} when value == merge_epoch ->
        :ok

      value ->
        merge_payload_epoch =
          case value do
            {:ok, parsed} -> parsed
            {:invalid, raw} -> raw
            other -> other
          end

        {:error, :commit_rejected,
         %{
           reason: :invalid_merge_epoch,
           operation: :merge_pending_commit,
           staged_epoch: merge_epoch,
           merge_epoch: merge_payload_epoch
         }}
    end
  end

  defp validate_snapshot_payload(payload) do
    fragment_keys = snapshot_fragment_keys(payload)
    extracted = extract_snapshot(payload)

    if fragment_keys != [] and is_nil(extracted) do
      {:error, :commit_rejected,
       %{
         reason: :invalid_snapshot_payload,
         operation: :merge_pending_commit,
         snapshot_fragment_keys: fragment_keys
       }}
    else
      :ok
    end
  end

  defp snapshot_fragment_keys(payload) when is_map(payload) do
    @snapshot_keys
    |> Enum.zip(@snapshot_atom_keys)
    |> Enum.reduce([], fn {string_key, atom_key}, acc ->
      if Map.has_key?(payload, string_key) or Map.has_key?(payload, atom_key) do
        [string_key | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp snapshot_fragment_keys(_payload), do: []

  defp validate_pending_operation(pending_commit) do
    operation =
      Map.get(pending_commit, "operation") ||
        Map.get(pending_commit, :operation)

    cond do
      is_atom(operation) and operation in @supported_stage_operations ->
        :ok

      is_binary(operation) and operation in @supported_stage_operation_strings ->
        :ok

      true ->
        {:error, :commit_rejected,
         %{
           reason: :invalid_pending_operation,
           operation: :merge_pending_commit,
           pending_operation: operation
         }}
    end
  end

  defp validate_operation_matches_active_revocations(
         conversation_id,
         pending_commit
       ) do
    with {:ok, active_revocations} <-
           ConversationSecurityRevocationStore.list_active_for_conversation(
             conversation_id
           ) do
      if active_revocations == [] or pending_remove_operation?(pending_commit) do
        :ok
      else
        {:error, :commit_rejected,
         %{
           reason: :operation_type_mismatch,
           operation: :merge_pending_commit,
           pending_operation:
             Map.get(pending_commit, "operation") ||
               Map.get(pending_commit, :operation)
         }}
      end
    end
  end

  defp build_pending_commit(operation, staged_epoch, payload) do
    %{
      "operation" => Atom.to_string(operation),
      "staged_epoch" => staged_epoch,
      "staged_at" =>
        DateTime.utc_now(:second)
        |> DateTime.to_iso8601(),
      "merge_hint" => extract_merge_hint(payload)
    }
  end

  defp extract_merge_hint(payload) when is_map(payload) do
    Map.get(payload, :group_info_ref) ||
      Map.get(payload, "group_info_ref") ||
      Map.get(payload, :commit_ref) ||
      Map.get(payload, "commit_ref")
  end

  defp extract_merge_hint(_payload), do: nil

  defp persist_state(state, changes) do
    attrs = %{
      protocol: state.protocol,
      state: Map.get(changes, :state, state.state),
      epoch: Map.get(changes, :epoch, state.epoch),
      pending_commit: Map.get(changes, :pending_commit, state.pending_commit)
    }

    case ConversationSecurityStateStore.upsert(
           state.conversation_id,
           attrs,
           state.lock_version
         ) do
      {:ok, persisted} ->
        {:ok, persisted}

      {:error, code, details} ->
        {:error, map_store_error(code), details}
    end
  end

  defp persist_merged_state_and_complete_revocations(
         state,
         next_state,
         next_epoch,
         seal_active_revocations?
       ) do
    attrs = %{
      protocol: state.protocol,
      state: next_state,
      epoch: next_epoch,
      pending_commit: nil
    }

    case Repo.transaction(fn ->
           with {:ok, persisted} <- persist_state_attrs(state, attrs),
                :ok <-
                  maybe_complete_active_revocations(
                    persisted.conversation_id,
                    persisted.epoch,
                    seal_active_revocations?
                  ) do
             persisted
           else
             {:error, code, details} ->
               Repo.rollback({code, details})
           end
         end) do
      {:ok, persisted} ->
        {:ok, persisted}

      {:error, {code, details}} ->
        {:error, code, details}
    end
  end

  defp persist_state_attrs(state, attrs) do
    case ConversationSecurityStateStore.upsert(
           state.conversation_id,
           attrs,
           state.lock_version
         ) do
      {:ok, persisted} ->
        {:ok, persisted}

      {:error, code, details} ->
        {:error, map_store_error(code), details}
    end
  end

  defp complete_active_revocations(conversation_id, committed_epoch) do
    with {:ok, revocations} <-
           ConversationSecurityRevocationStore.list_active_for_conversation(
             conversation_id
           ) do
      Enum.reduce_while(revocations, :ok, fn revocation, :ok ->
        case ConversationSecurityRevocationStore.mark_completed(
               revocation.id,
               %{committed_epoch: committed_epoch}
             ) do
          {:ok, _updated} ->
            {:cont, :ok}

          {:error, code, details} ->
            {:halt, {:error, map_store_error(code), details}}
        end
      end)
    end
  end

  defp maybe_complete_active_revocations(
         _conversation_id,
         _committed_epoch,
         false
       ),
       do: :ok

  defp maybe_complete_active_revocations(
         conversation_id,
         committed_epoch,
         true
       ) do
    complete_active_revocations(conversation_id, committed_epoch)
  end

  defp pending_remove_operation?(pending_commit) do
    operation =
      Map.get(pending_commit, "operation") ||
        Map.get(pending_commit, :operation)

    operation in [:mls_remove, "mls_remove"]
  end

  defp maybe_resolve_remove_target(
         :mls_remove,
         state,
         %{remove_client_id: device_id} = attrs
       )
       when is_binary(device_id) do
    group_params =
      %{group_id: state.conversation_id, epoch: state.epoch}
      |> Map.merge(state.state)

    case MLS.resolve_leaf_index(group_params, device_id) do
      {:ok, leaf_index} ->
        {:ok,
         attrs
         |> Map.delete(:remove_client_id)
         |> Map.put(:leaf_index, leaf_index)}

      {:error, _code, _details} = error ->
        error
    end
  end

  defp maybe_resolve_remove_target(_operation, _state, attrs), do: {:ok, attrs}

  defp build_request(state, attrs) do
    attrs
    |> Map.put_new(:group_id, state.conversation_id)
    |> Map.put_new(:epoch, state.epoch)
    |> Map.merge(state.state)
  end

  defp validate_stage_payload(payload, conversation_id, operation)
       when is_map(payload) and is_binary(conversation_id) and
              operation in @supported_stage_operations do
    with :ok <-
           validate_payload_group_id(
             payload,
             conversation_id,
             :stage_pending_commit
           ),
         :ok <-
           validate_operation_hint(
             payload,
             Atom.to_string(operation),
             :stage_pending_commit,
             :invalid_stage_operation_hint
           ) do
      validate_stage_status_hint(payload, operation)
    end
  end

  defp validate_stage_payload(_payload, _conversation_id, _operation) do
    {:error, :commit_rejected,
     %{reason: :invalid_stage_payload, operation: :stage_pending_commit}}
  end

  defp validate_stage_status_hint(payload, :mls_commit) do
    validate_optional_boolean(
      payload,
      :pending_commit,
      true,
      :stage_pending_commit,
      :invalid_pending_commit_hint
    )
  end

  defp validate_stage_status_hint(payload, operation)
       when operation in [:mls_update, :mls_add, :mls_remove] do
    validate_optional_boolean(
      payload,
      :staged,
      true,
      :stage_pending_commit,
      :invalid_staged_hint
    )
  end

  defp validate_merge_payload(payload, conversation_id)
       when is_map(payload) and is_binary(conversation_id) do
    with :ok <-
           validate_payload_group_id(
             payload,
             conversation_id,
             :merge_pending_commit
           ),
         :ok <-
           validate_operation_hint(
             payload,
             "merge_staged_commit",
             :merge_pending_commit,
             :invalid_merge_operation_hint
           ),
         :ok <-
           validate_optional_boolean(
             payload,
             :pending_commit,
             false,
             :merge_pending_commit,
             :invalid_pending_commit_hint
           ) do
      validate_optional_boolean(
        payload,
        :merged,
        true,
        :merge_pending_commit,
        :invalid_merged_hint
      )
    end
  end

  defp validate_merge_payload(_payload, _conversation_id) do
    {:error, :commit_rejected,
     %{reason: :invalid_merge_payload, operation: :merge_pending_commit}}
  end

  defp validate_payload_group_id(payload, expected_group_id, operation) do
    case fetch_payload_value(payload, :group_id) do
      :missing ->
        :ok

      {:present, value} when is_binary(value) and value == expected_group_id ->
        :ok

      {:present, value} ->
        {:error, :commit_rejected,
         %{
           reason: :invalid_payload_group_id,
           operation: operation,
           expected_group_id: expected_group_id,
           payload_group_id: value
         }}
    end
  end

  defp validate_operation_hint(payload, expected_operation, operation, reason) do
    case fetch_payload_value(payload, :operation) do
      :missing ->
        :ok

      {:present, value} ->
        case normalize_operation_hint(value) do
          {:ok, ^expected_operation} ->
            :ok

          {:ok, normalized} ->
            {:error, :commit_rejected,
             %{
               reason: reason,
               operation: operation,
               expected_operation: expected_operation,
               payload_operation: normalized
             }}

          :error ->
            {:error, :commit_rejected,
             %{
               reason: reason,
               operation: operation,
               expected_operation: expected_operation,
               payload_operation: value
             }}
        end
    end
  end

  defp validate_optional_boolean(
         payload,
         key,
         expected,
         operation,
         reason
       )
       when is_boolean(expected) do
    case fetch_payload_value(payload, key) do
      :missing ->
        :ok

      {:present, value} ->
        case parse_boolean(value) do
          {:ok, ^expected} ->
            :ok

          {:ok, actual} ->
            {:error, :commit_rejected,
             %{
               reason: reason,
               operation: operation,
               expected: expected,
               actual: actual,
               field: Atom.to_string(key)
             }}

          :error ->
            {:error, :commit_rejected,
             %{
               reason: reason,
               operation: operation,
               expected: expected,
               actual: value,
               field: Atom.to_string(key)
             }}
        end
    end
  end

  defp fetch_payload_value(payload, key)
       when is_map(payload) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(payload, key) ->
        {:present, Map.get(payload, key)}

      Map.has_key?(payload, string_key) ->
        {:present, Map.get(payload, string_key)}

      true ->
        :missing
    end
  end

  defp fetch_payload_value(_payload, _key), do: :missing

  defp normalize_operation_hint(value) when is_binary(value), do: {:ok, value}

  defp normalize_operation_hint(value) when is_atom(value),
    do: {:ok, Atom.to_string(value)}

  defp normalize_operation_hint(_value), do: :error

  defp parse_boolean(value) when is_boolean(value), do: {:ok, value}
  defp parse_boolean(value) when value in ["true", "1"], do: {:ok, true}
  defp parse_boolean(value) when value in ["false", "0"], do: {:ok, false}
  defp parse_boolean(_value), do: :error

  defp extract_snapshot(payload) when is_map(payload) do
    snapshot =
      Enum.reduce(
        [
          "session_sender_storage",
          "session_recipient_storage",
          "session_sender_signer",
          "session_recipient_signer",
          "session_cache"
        ],
        %{},
        fn key, acc ->
          value =
            case key do
              "session_sender_storage" ->
                Map.get(payload, "session_sender_storage") ||
                  Map.get(payload, :session_sender_storage)

              "session_recipient_storage" ->
                Map.get(payload, "session_recipient_storage") ||
                  Map.get(payload, :session_recipient_storage)

              "session_sender_signer" ->
                Map.get(payload, "session_sender_signer") ||
                  Map.get(payload, :session_sender_signer)

              "session_recipient_signer" ->
                Map.get(payload, "session_recipient_signer") ||
                  Map.get(payload, :session_recipient_signer)

              "session_cache" ->
                Map.get(payload, "session_cache") ||
                  Map.get(payload, :session_cache)

              _ ->
                nil
            end

          if is_binary(value) do
            Map.put(acc, key, value)
          else
            acc
          end
        end
      )

    if map_size(snapshot) == 5 do
      snapshot
    else
      nil
    end
  end

  defp extract_snapshot(_payload), do: nil

  defp merged_epoch_from_payload(payload, fallback_epoch) do
    case extract_epoch(payload) do
      {:ok, value} -> value
      _ -> fallback_epoch
    end
  end

  defp extract_epoch(payload) when is_map(payload) do
    case epoch_value(payload) do
      :missing ->
        :missing

      {:present, value} ->
        case parse_epoch(value) do
          {:ok, epoch} -> {:ok, epoch}
          :error -> {:invalid, value}
        end
    end
  end

  defp extract_epoch(_payload), do: :missing

  defp epoch_value(payload) when is_map(payload) do
    cond do
      Map.has_key?(payload, :epoch) ->
        {:present, Map.get(payload, :epoch)}

      Map.has_key?(payload, "epoch") ->
        {:present, Map.get(payload, "epoch")}

      true ->
        :missing
    end
  end

  defp epoch_value(_payload), do: :missing

  defp parse_epoch(value) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp parse_epoch(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_epoch(_value), do: :error

  defp map_store_error(:stale_state), do: :storage_inconsistent
  defp map_store_error(:state_encode_failed), do: :storage_inconsistent
  defp map_store_error(:state_decode_failed), do: :storage_inconsistent
  defp map_store_error(:invalid_input), do: :storage_inconsistent
  defp map_store_error(code), do: code
end
