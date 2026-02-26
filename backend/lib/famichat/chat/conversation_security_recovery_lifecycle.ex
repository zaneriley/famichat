defmodule Famichat.Chat.ConversationSecurityRecoveryLifecycle do
  @moduledoc """
  Chat-owned recovery orchestration for rejoin/state-loss durability.

  Recovery is idempotent per `{conversation_id, recovery_ref}` and persists
  an auditable recovery journal entry.
  """

  alias Famichat.Chat.ConversationSecurityRecoveryStore
  alias Famichat.Chat.ConversationSecurityStateStore
  alias Famichat.Crypto.MLS

  @snapshot_keys [
    "session_sender_storage",
    "session_recipient_storage",
    "session_sender_signer",
    "session_recipient_signer",
    "session_cache"
  ]

  @snapshot_atom_keys Enum.map(@snapshot_keys, &String.to_atom/1)
  @max_recovery_ref_length 128
  @state_protocol "mls"

  @spec recover_conversation_security_state(
          Ecto.UUID.t(),
          String.t(),
          map()
        ) :: {:ok, map()} | {:error, atom(), map()}
  def recover_conversation_security_state(
        conversation_id,
        recovery_ref,
        attrs \\ %{}
      )

  def recover_conversation_security_state(conversation_id, recovery_ref, attrs)
      when is_binary(conversation_id) and is_binary(recovery_ref) and
             byte_size(recovery_ref) > 0 and
             byte_size(recovery_ref) <= @max_recovery_ref_length and
             is_map(attrs) do
    with :ok <- validate_recovery_input(attrs),
         {:ok, started_or_existing} <-
           ConversationSecurityRecoveryStore.start_or_load(
             conversation_id,
             recovery_ref,
             %{recovery_reason: recovery_reason(attrs)}
           ) do
      case started_or_existing do
        {:existing, recovery} ->
          handle_existing_recovery(recovery)

        {:started, recovery} ->
          continue_recovery(recovery, attrs)
      end
    end
  end

  def recover_conversation_security_state(
        _conversation_id,
        _recovery_ref,
        _attrs
      ) do
    {:error, :invalid_input,
     %{reason: :invalid_recovery_call_input, operation: :recover}}
  end

  defp continue_recovery(recovery, attrs) do
    with {:ok, state_lock_version} <-
           load_state_lock_for_recovery(recovery.conversation_id),
         request <- build_join_request(recovery.conversation_id, attrs),
         {:ok, payload} <- MLS.join_from_welcome(request),
         {:ok, snapshot} <- extract_snapshot(payload),
         {:ok, recovered_epoch} <- extract_epoch(payload),
         {:ok, _persisted} <-
           persist_recovered_state(
             recovery.conversation_id,
             snapshot,
             recovered_epoch,
             state_lock_version
           ),
         {:ok, completed} <-
           ConversationSecurityRecoveryStore.mark_completed(recovery.id, %{
             recovered_epoch: recovered_epoch,
             audit_id: fetch(payload, "audit_id"),
             group_state_ref: fetch(payload, "group_state_ref"),
             recovery_reason: recovery_reason(attrs)
           }) do
      {:ok, to_result(completed, false)}
    else
      {:error, code, details} ->
        _ =
          ConversationSecurityRecoveryStore.mark_failed(recovery.id, %{
            error_code: code,
            error_reason: summarize_reason(details),
            recovery_reason: recovery_reason(attrs)
          })

        {:error, code, details}
    end
  end

  defp handle_existing_recovery(recovery) do
    case recovery.status do
      :completed ->
        {:ok, to_result(recovery, true)}

      :in_progress ->
        {:error, :recovery_in_progress,
         %{
           reason: :recovery_already_in_progress,
           recovery_ref: recovery.recovery_ref,
           recovery_id: recovery.id
         }}

      :failed ->
        {:error, :recovery_failed,
         %{
           reason: :recovery_previously_failed,
           recovery_ref: recovery.recovery_ref,
           recovery_id: recovery.id,
           error_code: recovery.error_code,
           error_reason: recovery.error_reason
         }}
    end
  end

  defp validate_recovery_input(attrs) do
    has_token? =
      non_empty(attrs, "rejoin_token") || non_empty(attrs, "welcome")

    if has_token? do
      :ok
    else
      {:error, :invalid_input,
       %{
         reason: :missing_rejoin_material,
         operation: :recover
       }}
    end
  end

  defp load_state_lock_for_recovery(conversation_id) do
    case ConversationSecurityStateStore.load(conversation_id) do
      {:ok, state} ->
        {:ok, state.lock_version}

      {:error, :not_found, _details} ->
        {:ok, nil}

      {:error, :state_decode_failed, _details} ->
        case ConversationSecurityStateStore.delete(conversation_id) do
          :ok ->
            {:ok, nil}

          {:error, code, details} ->
            {:error, map_state_store_error(code), details}
        end

      {:error, code, details} ->
        {:error, map_state_store_error(code), details}
    end
  end

  defp build_join_request(conversation_id, attrs) do
    attrs
    |> Map.put_new(:group_id, conversation_id)
  end

  defp extract_snapshot(payload) when is_map(payload) do
    snapshot =
      @snapshot_keys
      |> Enum.zip(@snapshot_atom_keys)
      |> Enum.reduce(%{}, fn {string_key, atom_key}, acc ->
        value = Map.get(payload, string_key) || Map.get(payload, atom_key)

        cond do
          is_binary(value) ->
            if string_key == "session_cache" or value != "" do
              Map.put(acc, string_key, value)
            else
              acc
            end

          true ->
            acc
        end
      end)

    if map_size(snapshot) == length(@snapshot_keys) do
      {:ok, snapshot}
    else
      {:error, :storage_inconsistent,
       %{
         reason: :missing_recovery_snapshot,
         operation: :recover
       }}
    end
  end

  defp extract_snapshot(_payload) do
    {:error, :storage_inconsistent,
     %{reason: :missing_recovery_snapshot, operation: :recover}}
  end

  defp extract_epoch(payload) when is_map(payload) do
    value = Map.get(payload, "epoch") || Map.get(payload, :epoch)

    cond do
      is_integer(value) and value >= 0 ->
        {:ok, value}

      is_binary(value) ->
        case Integer.parse(value) do
          {epoch, ""} when epoch >= 0 ->
            {:ok, epoch}

          _ ->
            {:error, :storage_inconsistent,
             %{reason: :invalid_recovery_epoch, operation: :recover}}
        end

      true ->
        {:error, :storage_inconsistent,
         %{reason: :invalid_recovery_epoch, operation: :recover}}
    end
  end

  defp extract_epoch(_payload) do
    {:error, :storage_inconsistent,
     %{reason: :invalid_recovery_epoch, operation: :recover}}
  end

  defp persist_recovered_state(
         conversation_id,
         snapshot,
         recovered_epoch,
         expected_lock_version
       ) do
    attrs = %{
      protocol: @state_protocol,
      state: snapshot,
      epoch: recovered_epoch,
      pending_commit: nil
    }

    case ConversationSecurityStateStore.upsert(
           conversation_id,
           attrs,
           expected_lock_version
         ) do
      {:ok, persisted} ->
        {:ok, persisted}

      {:error, code, details} ->
        {:error, map_state_store_error(code), details}
    end
  end

  defp map_state_store_error(:stale_state), do: :storage_inconsistent
  defp map_state_store_error(:state_encode_failed), do: :storage_inconsistent
  defp map_state_store_error(:state_decode_failed), do: :storage_inconsistent
  defp map_state_store_error(:invalid_input), do: :storage_inconsistent
  defp map_state_store_error(code), do: code

  defp to_result(recovery, idempotent?) do
    %{
      recovery_id: recovery.id,
      recovery_ref: recovery.recovery_ref,
      conversation_id: recovery.conversation_id,
      status: recovery.status,
      recovered_epoch: recovery.recovered_epoch,
      audit_id: recovery.audit_id,
      group_state_ref: recovery.group_state_ref,
      idempotent: idempotent?
    }
  end

  defp recovery_reason(attrs) when is_map(attrs) do
    attrs
    |> non_empty("recovery_reason")
    |> case do
      nil -> "state_loss_recovery"
      value -> value
    end
  end

  defp recovery_reason(_attrs), do: "state_loss_recovery"

  defp summarize_reason(details) when is_map(details) do
    reason = Map.get(details, :reason) || Map.get(details, "reason")

    cond do
      is_atom(reason) -> Atom.to_string(reason)
      is_binary(reason) -> reason
      true -> "unspecified"
    end
  end

  defp summarize_reason(_details), do: "unspecified"

  defp fetch(payload, key) when is_map(payload) do
    Map.get(payload, key) || Map.get(payload, String.to_atom(key))
  end

  defp non_empty(payload, key) when is_map(payload) and is_binary(key) do
    value = Map.get(payload, key) || Map.get(payload, String.to_atom(key))

    case value do
      binary when is_binary(binary) and binary != "" ->
        binary

      _ ->
        nil
    end
  end

  defp non_empty(_payload, _key), do: nil
end
