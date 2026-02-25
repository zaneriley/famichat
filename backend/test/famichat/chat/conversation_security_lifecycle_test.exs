defmodule Famichat.Chat.ConversationSecurityLifecycleTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.{
    ConversationSecurityLifecycle,
    ConversationSecurityStateStore
  }

  alias Famichat.TestSupport.MLS.FakeAdapter
  import Famichat.ChatFixtures

  setup do
    previous_adapter = Application.get_env(:famichat, :mls_adapter)
    Application.put_env(:famichat, :mls_adapter, FakeAdapter)

    on_exit(fn ->
      restore_env(:mls_adapter, previous_adapter)
    end)

    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, persisted} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{state: snapshot_payload(), epoch: 3, protocol: "mls"},
               nil
             )

    {:ok, conversation: conversation, persisted: persisted}
  end

  test "stage_pending_commit persists pending metadata and blocks re-stage",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    assert staged.epoch == 3
    assert staged.pending_commit["operation"] == "mls_commit"
    assert staged.pending_commit["staged_epoch"] == 4
    assert is_binary(staged.pending_commit["staged_at"])

    assert {:error, :pending_proposals, details} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_update
             )

    assert details[:reason] == :pending_commit_already_staged
  end

  test "merge_pending_commit requires staged commit and clears pending on success",
       %{conversation: conversation} do
    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(conversation.id)

    assert details[:reason] == :no_pending_commit

    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_add
             )

    assert staged.pending_commit["operation"] == "mls_add"

    assert {:ok, merged} =
             ConversationSecurityLifecycle.merge_pending_commit(conversation.id)

    assert merged.pending_commit == nil
    assert merged.epoch == 4
    assert merged.lock_version > staged.lock_version
    assert merged.state == snapshot_payload()
  end

  test "clear_pending_commit is idempotent and keeps state usable",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_remove
             )

    assert is_map(staged.pending_commit)

    assert {:ok, cleared} =
             ConversationSecurityLifecycle.clear_pending_commit(conversation.id)

    assert cleared.pending_commit == nil
    assert cleared.epoch == 3

    assert {:ok, idempotent_clear} =
             ConversationSecurityLifecycle.clear_pending_commit(conversation.id)

    assert idempotent_clear.pending_commit == nil
    assert idempotent_clear.epoch == 3

    assert {:ok, restaged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_update
             )

    assert restaged.pending_commit["operation"] == "mls_update"
  end

  test "merge_pending_commit fails after clear (out-of-order merge/clear)",
       %{conversation: conversation} do
    assert {:ok, _staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    assert {:ok, cleared} =
             ConversationSecurityLifecycle.clear_pending_commit(conversation.id)

    assert cleared.pending_commit == nil

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(conversation.id)

    assert details[:reason] == :no_pending_commit
  end

  test "merge_pending_commit fails closed on tampered staged epoch",
       %{conversation: conversation} do
    put_pending_commit!(
      conversation.id,
      %{"operation" => "mls_commit", "staged_epoch" => 1}
    )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(conversation.id)

    assert details[:reason] == :invalid_staged_epoch
    assert details[:current_epoch] == 3
    assert details[:staged_epoch] == 1
  end

  test "merge_pending_commit fails closed on tampered pending operation",
       %{conversation: conversation} do
    put_pending_commit!(
      conversation.id,
      %{"operation" => "mls_drop_all", "staged_epoch" => 4}
    )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(conversation.id)

    assert details[:reason] == :invalid_pending_operation
    assert details[:pending_operation] == "mls_drop_all"
  end

  test "stage_pending_commit fails closed on regressive staged epoch payload",
       %{conversation: conversation} do
    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit,
               %{success_payload: %{epoch: 2}}
             )

    assert details[:reason] == :invalid_staged_epoch
    assert details[:current_epoch] == 3
    assert details[:staged_epoch] == 2

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == nil
  end

  test "all stage operations fail closed on non-advancing staged epoch payload",
       %{conversation: conversation} do
    for operation <- [:mls_commit, :mls_update, :mls_add, :mls_remove] do
      assert {:error, :commit_rejected, details} =
               ConversationSecurityLifecycle.stage_pending_commit(
                 conversation.id,
                 operation,
                 %{success_payload: %{epoch: 3}}
               )

      assert details[:reason] == :invalid_staged_epoch
      assert details[:current_epoch] == 3
      assert details[:staged_epoch] == 3
    end

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == nil
  end

  test "merge_pending_commit fails closed on regressive merge epoch payload",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(
               conversation.id,
               %{success_payload: %{epoch: 2}}
             )

    assert details[:reason] == :invalid_merge_epoch
    assert details[:staged_epoch] == 4
    assert details[:merge_epoch] == 2

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == staged.pending_commit
    assert persisted.epoch == 3
  end

  test "concurrent merge_pending_commit attempts have a single winner",
       %{conversation: conversation} do
    assert {:ok, _staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    results =
      1..8
      |> Task.async_stream(
        fn _ ->
          ConversationSecurityLifecycle.merge_pending_commit(conversation.id)
        end,
        max_concurrency: 8,
        timeout: 5_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    successes = Enum.filter(results, &match?({:ok, _}, &1))
    failures = Enum.filter(results, &match?({:error, _, _}, &1))

    assert length(successes) == 1
    assert length(failures) == 7

    assert Enum.all?(failures, fn {:error, code, details} ->
             code in [:commit_rejected, :storage_inconsistent] and
               details[:reason] in [:no_pending_commit, :lock_version_mismatch]
           end)

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == nil
    assert persisted.epoch == 4
  end

  test "merge_pending_commit fails closed on partial snapshot payload tampering",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(
               conversation.id,
               %{
                 success_payload: %{
                   "session_sender_storage" => Base.encode64("tampered")
                 }
               }
             )

    assert details[:reason] == :invalid_snapshot_payload
    assert details[:snapshot_fragment_keys] == ["session_sender_storage"]

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == staged.pending_commit
    assert persisted.epoch == 3
  end

  test "concurrent stage_pending_commit attempts have a single winner",
       %{conversation: conversation} do
    results =
      1..8
      |> Task.async_stream(
        fn _ ->
          ConversationSecurityLifecycle.stage_pending_commit(
            conversation.id,
            :mls_update
          )
        end,
        max_concurrency: 8,
        timeout: 5_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    successes = Enum.filter(results, &match?({:ok, _}, &1))
    failures = Enum.filter(results, &match?({:error, _, _}, &1))

    assert length(successes) == 1
    assert length(failures) == 7

    assert Enum.all?(failures, fn {:error, code, _details} ->
             code in [:pending_proposals, :storage_inconsistent]
           end)

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert is_map(persisted.pending_commit)
  end

  test "lifecycle calls fail closed when durable state is missing" do
    missing_conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:error, :storage_inconsistent, details} =
             ConversationSecurityLifecycle.stage_pending_commit(
               missing_conversation.id,
               :mls_commit
             )

    assert details[:reason] == :missing_state
  end

  defp snapshot_payload do
    %{
      "session_sender_storage" => Base.encode64("sender-storage"),
      "session_recipient_storage" => Base.encode64("recipient-storage"),
      "session_sender_signer" => Base.encode64("sender-signer"),
      "session_recipient_signer" => Base.encode64("recipient-signer"),
      "session_cache" => Base.encode64("cache")
    }
  end

  defp put_pending_commit!(conversation_id, pending_commit) do
    assert {:ok, state} = ConversationSecurityStateStore.load(conversation_id)

    attrs = %{
      protocol: state.protocol,
      state: state.state,
      epoch: state.epoch,
      pending_commit: pending_commit
    }

    assert {:ok, _persisted} =
             ConversationSecurityStateStore.upsert(
               conversation_id,
               attrs,
               state.lock_version
             )
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
