defmodule Famichat.Chat.ConversationSecurityLifecycle do
  @moduledoc """
  Chat-owned MLS lifecycle orchestration on top of durable conversation security state.

  This module enforces pending-commit and epoch semantics while keeping
  persistence ownership in `Famichat.Chat`.
  """

  alias Famichat.Chat.ConversationSecurityStateStore
  alias Famichat.Crypto.MLS

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
         request <- build_request(state, attrs),
         {:ok, payload} <- apply(MLS, operation, [request]),
         {:ok, staged_epoch} <- staged_epoch(payload, state.epoch),
         pending_commit <-
           build_pending_commit(operation, staged_epoch, payload),
         {:ok, persisted} <-
           persist_state(state, %{pending_commit: pending_commit}) do
      {:ok, persisted}
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
         {:ok, next_state, next_epoch} <-
           resolve_merge_payload(state, payload, merge_epoch),
         {:ok, persisted} <-
           persist_state(state, %{
             state: next_state,
             epoch: next_epoch,
             pending_commit: nil
           }) do
      {:ok, persisted}
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

        with {:ok, _payload} <- MLS.clear_pending_commit(request),
             {:ok, persisted} <- persist_state(state, %{pending_commit: nil}) do
          {:ok, persisted}
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

  defp pending_commit_epoch(pending_commit, fallback_epoch) do
    value =
      Map.get(pending_commit, "staged_epoch") ||
        Map.get(pending_commit, :staged_epoch)

    cond do
      is_integer(value) and value > fallback_epoch ->
        {:ok, value}

      is_integer(value) and value >= 0 ->
        {:error, :commit_rejected,
         %{
           reason: :invalid_staged_epoch,
           operation: :merge_pending_commit,
           current_epoch: fallback_epoch,
           staged_epoch: value
         }}

      true ->
        {:error, :commit_rejected,
         %{
           reason: :invalid_staged_epoch,
           operation: :merge_pending_commit,
           current_epoch: fallback_epoch,
           staged_epoch: value
         }}
    end
  end

  defp staged_epoch(payload, current_epoch) do
    case extract_epoch(payload) do
      nil ->
        {:ok, current_epoch + 1}

      value when is_integer(value) and value > current_epoch ->
        {:ok, value}

      value ->
        {:error, :commit_rejected,
         %{
           reason: :invalid_staged_epoch,
           operation: :stage_pending_commit,
           current_epoch: current_epoch,
           staged_epoch: value
         }}
    end
  end

  defp resolve_merge_payload(state, payload, merge_epoch)
       when is_map(payload) do
    with :ok <- validate_merge_epoch(payload, merge_epoch),
         :ok <- validate_snapshot_payload(payload) do
      next_state = extract_snapshot(payload) || state.state
      next_epoch = extract_epoch(payload) || merge_epoch
      {:ok, next_state, next_epoch}
    end
  end

  defp resolve_merge_payload(state, _payload, merge_epoch) do
    {:ok, state.state, merge_epoch}
  end

  defp validate_merge_epoch(payload, merge_epoch) do
    case extract_epoch(payload) do
      nil ->
        :ok

      value when is_integer(value) and value >= merge_epoch ->
        :ok

      value ->
        {:error, :commit_rejected,
         %{
           reason: :invalid_merge_epoch,
           operation: :merge_pending_commit,
           staged_epoch: merge_epoch,
           merge_epoch: value
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

  defp build_pending_commit(operation, staged_epoch, payload) do
    %{
      "operation" => Atom.to_string(operation),
      "staged_epoch" => staged_epoch,
      "staged_at" =>
        DateTime.utc_now()
        |> DateTime.truncate(:second)
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

  defp build_request(state, attrs) do
    attrs
    |> Map.put_new(:group_id, state.conversation_id)
    |> Map.put_new(:epoch, state.epoch)
    |> Map.merge(state.state)
  end

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

  defp extract_epoch(payload) when is_map(payload) do
    value = Map.get(payload, :epoch) || Map.get(payload, "epoch")

    if is_integer(value) and value >= 0 do
      value
    else
      nil
    end
  end

  defp extract_epoch(_payload), do: nil

  defp map_store_error(:stale_state), do: :storage_inconsistent
  defp map_store_error(:state_encode_failed), do: :storage_inconsistent
  defp map_store_error(:state_decode_failed), do: :storage_inconsistent
  defp map_store_error(:invalid_input), do: :storage_inconsistent
  defp map_store_error(code), do: code
end
