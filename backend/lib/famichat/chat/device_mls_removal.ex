defmodule Famichat.Chat.DeviceMlsRemoval do
  @moduledoc """
  Best-effort MLS group removal for revoked devices.

  When a device is revoked, its session is killed synchronously. This module
  provides the async follow-up: staging an `mls_remove` proposal for every
  conversation the device's user participates in, then merging those proposals
  so the device's MLS credential is evicted from each group's epoch.

  ## Design constraints

  - Session revocation is the hard guarantee. MLS removal is best-effort.
  - Failures are logged and the conversation revocation journal is marked
    `:failed` for audit and later remediation. They do NOT bubble up to the
    caller.
  - Each conversation is processed sequentially to avoid overwhelming the NIF.
    A timeout is applied per conversation to prevent a stalled NIF from
    blocking the worker indefinitely.
  - The caller (Sessions.revoke_device) fires this work off with Task.start
    so the revoke call returns immediately.

  ## Device → MLS credential mapping

  OpenMLS removes members by leaf index, which is tracked inside the MLS group
  state stored in `ConversationSecurityStateStore`. The `stage_pending_commit`
  call for `:mls_remove` passes the `device_id` as `remove_client_id` in the
  request map; the NIF adapter is responsible for resolving the leaf index from
  that identifier within the group state.

  If no MLS state exists for a given conversation (e.g. the conversation was
  created before MLS was enabled), the removal is skipped with an info-level
  log. This is not treated as a failure.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Famichat.Chat.ConversationQueries
  alias Famichat.Chat.ConversationSecurityLifecycle
  alias Famichat.Chat.ConversationSecurityRevocationStore
  alias Famichat.Repo

  @per_conversation_timeout_ms 10_000
  @revocation_reason "mls_device_eviction"

  @doc """
  Asynchronously removes `device_id` from MLS groups for all conversations
  the user (`user_id`) is a member of.

  Returns `:ok` immediately. All work is performed in a spawned task.
  Failures are logged and recorded in the revocation journal but do not
  propagate to the caller.
  """
  @spec remove_async(Ecto.UUID.t(), String.t(), String.t()) :: :ok
  def remove_async(user_id, device_id, revocation_ref)
      when is_binary(user_id) and is_binary(device_id) and
             is_binary(revocation_ref) do
    Task.start(fn ->
      do_remove(user_id, device_id, revocation_ref, with_timeout: true)
    end)

    :ok
  end

  @doc """
  Synchronously removes `device_id` from MLS groups for all conversations
  the user (`user_id`) participates in.

  Returns a summary map with counts of conversations processed, succeeded,
  skipped (no MLS state), and failed.

  Intended for testing and operational tooling; production callers should
  use `remove_async/3`. Unlike `remove_async/3`, this function does **not**
  wrap each conversation removal in a `Task.async` timeout guard, so it
  inherits the calling process's DB sandbox connection in tests.
  """
  @spec remove_sync(Ecto.UUID.t(), String.t(), String.t()) :: map()
  def remove_sync(user_id, device_id, revocation_ref)
      when is_binary(user_id) and is_binary(device_id) and
             is_binary(revocation_ref) do
    do_remove(user_id, device_id, revocation_ref, with_timeout: false)
  end

  ## Private

  defp do_remove(user_id, device_id, revocation_ref, opts \\ []) do
    with_timeout? = Keyword.get(opts, :with_timeout, true)
    conversation_ids = list_conversation_ids(user_id)

    Logger.info(
      "[DeviceMlsRemoval] Starting MLS removal for revoked device",
      user_id: user_id,
      device_id: device_id,
      conversation_count: length(conversation_ids),
      revocation_ref: revocation_ref
    )

    summary =
      Enum.reduce(
        conversation_ids,
        %{total: 0, succeeded: 0, skipped: 0, failed: 0},
        fn conversation_id, acc ->
          result =
            if with_timeout? do
              remove_from_conversation_with_timeout(
                conversation_id,
                device_id,
                revocation_ref
              )
            else
              do_remove_from_conversation(
                conversation_id,
                device_id,
                revocation_ref
              )
            end

          acc
          |> Map.update!(:total, &(&1 + 1))
          |> update_summary(result)
        end
      )

    Logger.info(
      "[DeviceMlsRemoval] MLS removal complete for revoked device",
      user_id: user_id,
      device_id: device_id,
      summary: summary
    )

    summary
  end

  defp remove_from_conversation_with_timeout(
         conversation_id,
         device_id,
         revocation_ref
       ) do
    task =
      Task.async(fn ->
        do_remove_from_conversation(conversation_id, device_id, revocation_ref)
      end)

    case Task.yield(task, @per_conversation_timeout_ms) ||
           Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        Logger.warning(
          "[DeviceMlsRemoval] Timed out removing device from conversation",
          conversation_id: conversation_id,
          device_id: device_id,
          timeout_ms: @per_conversation_timeout_ms
        )

        mark_removal_failed(
          conversation_id,
          revocation_ref,
          "mls_remove_timeout",
          "per-conversation timeout exceeded"
        )

        :failed
    end
  end

  defp do_remove_from_conversation(conversation_id, device_id, revocation_ref) do
    with {:ok, _staged} <-
           stage_mls_remove(conversation_id, device_id, revocation_ref),
         {:ok, _merged} <- merge_mls_remove(conversation_id) do
      :succeeded
    else
      {:error, :storage_inconsistent, %{reason: :missing_state}} ->
        # No MLS state means this conversation was never enrolled in MLS.
        Logger.debug(
          "[DeviceMlsRemoval] Skipping conversation with no MLS state",
          conversation_id: conversation_id,
          device_id: device_id
        )

        :skipped

      {:error, :storage_inconsistent, details} ->
        Logger.warning(
          "[DeviceMlsRemoval] Storage inconsistency removing device from conversation",
          conversation_id: conversation_id,
          device_id: device_id,
          details: inspect(details)
        )

        mark_removal_failed(
          conversation_id,
          revocation_ref,
          "storage_inconsistent",
          inspect(details)
        )

        :failed

      {:error, code, details} ->
        Logger.warning(
          "[DeviceMlsRemoval] Failed to remove device from MLS group",
          conversation_id: conversation_id,
          device_id: device_id,
          error_code: code,
          details: inspect(details)
        )

        mark_removal_failed(
          conversation_id,
          revocation_ref,
          Atom.to_string(code),
          inspect(details)
        )

        :failed
    end
  end

  defp stage_mls_remove(conversation_id, device_id, revocation_ref) do
    # The revocation_ref is stored in the journal so failures can be audited.
    # The remove_client_id param is passed to the NIF so it can locate
    # the leaf index for the device's MLS credential within the group.
    ConversationSecurityLifecycle.stage_pending_commit(
      conversation_id,
      :mls_remove,
      %{
        remove_client_id: device_id,
        revocation_ref: revocation_ref
      }
    )
  end

  defp merge_mls_remove(conversation_id) do
    ConversationSecurityLifecycle.merge_pending_commit(conversation_id)
  end

  defp mark_removal_failed(
         conversation_id,
         revocation_ref,
         error_code,
         error_reason
       ) do
    case ConversationSecurityRevocationStore.load_by_ref(
           conversation_id,
           revocation_ref
         ) do
      {:ok, record} ->
        ConversationSecurityRevocationStore.mark_failed(record.id, %{
          error_code: error_code,
          error_reason: error_reason,
          revocation_reason: @revocation_reason
        })

      {:error, :not_found, _} ->
        # Journal entry was never created (e.g. stage_client_revocation
        # also failed). Nothing to mark failed.
        :ok

      {:error, code, details} ->
        Logger.warning(
          "[DeviceMlsRemoval] Could not load revocation record to mark failed",
          conversation_id: conversation_id,
          revocation_ref: revocation_ref,
          error_code: code,
          details: inspect(details)
        )

        :ok
    end
  end

  defp update_summary(acc, :succeeded),
    do: Map.update!(acc, :succeeded, &(&1 + 1))

  defp update_summary(acc, :skipped), do: Map.update!(acc, :skipped, &(&1 + 1))
  defp update_summary(acc, :failed), do: Map.update!(acc, :failed, &(&1 + 1))

  defp list_conversation_ids(user_id) do
    ConversationQueries.for_user(user_id)
    |> select([c], c.id)
    |> order_by([c], asc: c.id)
    |> Repo.all()
  end
end
