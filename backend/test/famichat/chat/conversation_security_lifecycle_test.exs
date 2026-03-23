defmodule Famichat.Chat.ConversationSecurityLifecycleTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.{
    ConversationSecurityLifecycle,
    ConversationSecurityRevocationStore,
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

  test "merge_pending_commit seals active revocations with merged epoch for mls_remove operations",
       %{conversation: conversation} do
    assert {:ok, {:started, _in_progress}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-merge-in-progress",
               %{subject_type: :client, subject_id: "client-merge-1"}
             )

    assert {:ok, {:started, pending_base}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-merge-pending",
               %{subject_type: :client, subject_id: "client-merge-2"}
             )

    assert {:ok, _pending} =
             ConversationSecurityRevocationStore.mark_pending_commit(
               pending_base.id,
               %{proposal_ref: "proposal-merge-2"}
             )

    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_remove,
               %{remove_target: "recipient"}
             )

    assert staged.pending_commit["operation"] == "mls_remove"

    assert {:ok, merged} =
             ConversationSecurityLifecycle.merge_pending_commit(conversation.id)

    assert merged.epoch == 4
    assert merged.pending_commit == nil

    assert {:ok, completed_in_progress} =
             ConversationSecurityRevocationStore.load_by_ref(
               conversation.id,
               "revocation-merge-in-progress"
             )

    assert completed_in_progress.status == :completed
    assert completed_in_progress.committed_epoch == 4

    assert {:ok, completed_pending} =
             ConversationSecurityRevocationStore.load_by_ref(
               conversation.id,
               "revocation-merge-pending"
             )

    assert completed_pending.status == :completed
    assert completed_pending.committed_epoch == 4
  end

  test "merge_pending_commit rejects non-remove operations when active revocations exist",
       %{conversation: conversation} do
    assert {:ok, {:started, _in_progress}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-non-remove-in-progress",
               %{subject_type: :client, subject_id: "client-non-remove-1"}
             )

    assert {:ok, {:started, pending_base}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-non-remove-pending",
               %{subject_type: :client, subject_id: "client-non-remove-2"}
             )

    assert {:ok, _pending} =
             ConversationSecurityRevocationStore.mark_pending_commit(
               pending_base.id,
               %{proposal_ref: "proposal-non-remove-2"}
             )

    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_add
             )

    assert staged.pending_commit["operation"] == "mls_add"

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(conversation.id)

    assert details[:reason] == :operation_type_mismatch
    assert details[:pending_operation] == "mls_add"
  end

  test "concurrent merge winners seal remove revocations once",
       %{conversation: conversation} do
    assert {:ok, {:started, revocation}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-concurrent-remove",
               %{subject_type: :client, subject_id: "client-concurrent-remove"}
             )

    assert {:ok, _pending} =
             ConversationSecurityRevocationStore.mark_pending_commit(
               revocation.id,
               %{proposal_ref: "proposal-concurrent-remove"}
             )

    assert {:ok, _staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_remove,
               %{remove_target: "recipient"}
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

    assert {:ok, completed} =
             ConversationSecurityRevocationStore.load_by_ref(
               conversation.id,
               "revocation-concurrent-remove"
             )

    assert completed.status == :completed
    assert completed.committed_epoch == 4
  end

  test "merge_pending_commit rejects non-remove commit and allows subsequent remove to seal revocations",
       %{conversation: conversation} do
    assert {:ok, {:started, revocation}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-delayed-seal",
               %{subject_type: :client, subject_id: "client-delayed-seal"}
             )

    assert {:ok, _pending} =
             ConversationSecurityRevocationStore.mark_pending_commit(
               revocation.id,
               %{proposal_ref: "proposal-delayed-seal"}
             )

    assert {:ok, _staged_add} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_add
             )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(conversation.id)

    assert details[:reason] == :operation_type_mismatch

    assert {:ok, still_pending} =
             ConversationSecurityRevocationStore.load_by_ref(
               conversation.id,
               "revocation-delayed-seal"
             )

    assert still_pending.status == :pending_commit
    assert still_pending.committed_epoch == nil

    assert {:ok, _cleared} =
             ConversationSecurityLifecycle.clear_pending_commit(conversation.id)

    assert {:ok, _staged_remove} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_remove,
               %{remove_target: "recipient"}
             )

    assert {:ok, merged_remove} =
             ConversationSecurityLifecycle.merge_pending_commit(conversation.id)

    assert merged_remove.epoch == 4

    assert {:ok, completed} =
             ConversationSecurityRevocationStore.load_by_ref(
               conversation.id,
               "revocation-delayed-seal"
             )

    assert completed.status == :completed
    assert completed.committed_epoch == 4
  end

  test "clear_pending_commit is idempotent and keeps state usable",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_remove,
               %{remove_target: "recipient"}
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

    assert details[:reason] == :epoch_too_low
    assert details[:current_epoch] == 3
    assert details[:staged_epoch] == 1
  end

  test "merge_pending_commit fails closed when staged epoch is too high",
       %{conversation: conversation} do
    put_pending_commit!(
      conversation.id,
      %{"operation" => "mls_commit", "staged_epoch" => 6}
    )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(conversation.id)

    assert details[:reason] == :epoch_too_high
    assert details[:current_epoch] == 3
    assert details[:staged_epoch] == 6
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

  test "stage_pending_commit parses exact-next string epoch payload",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_update,
               %{success_payload: %{epoch: "4"}}
             )

    assert staged.pending_commit["staged_epoch"] == 4
    assert staged.pending_commit["operation"] == "mls_update"
  end

  test "stage_pending_commit fails closed when payload epoch skips ahead",
       %{conversation: conversation} do
    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_update,
               %{success_payload: %{epoch: "7"}}
             )

    assert details[:reason] == :invalid_staged_epoch
    assert details[:current_epoch] == 3
    assert details[:staged_epoch] == 7

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == nil
  end

  test "stage_pending_commit fails closed on malformed staged epoch string payload",
       %{conversation: conversation} do
    for operation <- [:mls_commit, :mls_update, :mls_add, :mls_remove] do
      assert {:error, :commit_rejected, details} =
               ConversationSecurityLifecycle.stage_pending_commit(
                 conversation.id,
                 operation,
                 %{success_payload: %{epoch: "not-an-epoch"}}
               )

      assert details[:reason] == :invalid_staged_epoch
      assert details[:current_epoch] == 3
      assert details[:staged_epoch] == "not-an-epoch"
    end

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == nil
  end

  test "stage_pending_commit fails closed on mismatched payload operation hint",
       %{conversation: conversation} do
    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_add,
               %{success_payload: %{operation: "mls_remove", epoch: 4}}
             )

    assert details[:reason] == :invalid_stage_operation_hint
    assert details[:expected_operation] == "mls_add"
    assert details[:payload_operation] == "mls_remove"

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == nil
  end

  test "stage_pending_commit fails closed on invalid staged status hint",
       %{conversation: conversation} do
    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_update,
               %{success_payload: %{staged: false, epoch: 4}}
             )

    assert details[:reason] == :invalid_staged_hint
    assert details[:field] == "staged"
    assert details[:expected] == true
    assert details[:actual] == false
  end

  test "stage_pending_commit fails closed on invalid pending_commit hint",
       %{conversation: conversation} do
    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit,
               %{success_payload: %{pending_commit: false, epoch: 4}}
             )

    assert details[:reason] == :invalid_pending_commit_hint
    assert details[:field] == "pending_commit"
    assert details[:expected] == true
    assert details[:actual] == false
  end

  test "stage_pending_commit fails closed on mismatched payload group_id",
       %{conversation: conversation} do
    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_update,
               %{success_payload: %{group_id: "other-group", epoch: 4}}
             )

    assert details[:reason] == :invalid_payload_group_id
    assert details[:expected_group_id] == conversation.id
    assert details[:payload_group_id] == "other-group"
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

  test "merge_pending_commit parses numeric string epoch payload",
       %{conversation: conversation} do
    assert {:ok, _staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    assert {:ok, merged} =
             ConversationSecurityLifecycle.merge_pending_commit(
               conversation.id,
               %{success_payload: %{epoch: "4"}}
             )

    assert merged.pending_commit == nil
    assert merged.epoch == 4
  end

  test "merge_pending_commit fails closed when payload epoch skips ahead",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(
               conversation.id,
               %{success_payload: %{epoch: 6}}
             )

    assert details[:reason] == :invalid_merge_epoch
    assert details[:staged_epoch] == 4
    assert details[:merge_epoch] == 6

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == staged.pending_commit
    assert persisted.epoch == 3
  end

  test "merge_pending_commit fails closed on malformed merge epoch string payload",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(
               conversation.id,
               %{success_payload: %{epoch: "bad-merge-epoch"}}
             )

    assert details[:reason] == :invalid_merge_epoch
    assert details[:staged_epoch] == 4
    assert details[:merge_epoch] == "bad-merge-epoch"

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == staged.pending_commit
    assert persisted.epoch == 3
  end

  test "merge_pending_commit fails closed on mismatched payload operation hint",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(
               conversation.id,
               %{success_payload: %{operation: "mls_remove", epoch: 4}}
             )

    assert details[:reason] == :invalid_merge_operation_hint
    assert details[:expected_operation] == "merge_staged_commit"
    assert details[:payload_operation] == "mls_remove"

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == staged.pending_commit
    assert persisted.epoch == 3
  end

  test "merge_pending_commit fails closed on mismatched payload group_id",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(
               conversation.id,
               %{success_payload: %{group_id: "other-group", epoch: 4}}
             )

    assert details[:reason] == :invalid_payload_group_id
    assert details[:expected_group_id] == conversation.id
    assert details[:payload_group_id] == "other-group"

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == staged.pending_commit
    assert persisted.epoch == 3
  end

  test "merge_pending_commit fails closed on invalid merged status hint",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(
               conversation.id,
               %{success_payload: %{merged: false, epoch: 4}}
             )

    assert details[:reason] == :invalid_merged_hint
    assert details[:field] == "merged"
    assert details[:expected] == true
    assert details[:actual] == false

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == staged.pending_commit
    assert persisted.epoch == 3
  end

  test "merge_pending_commit fails closed on invalid pending_commit status hint",
       %{conversation: conversation} do
    assert {:ok, staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    assert {:error, :commit_rejected, details} =
             ConversationSecurityLifecycle.merge_pending_commit(
               conversation.id,
               %{success_payload: %{pending_commit: true, epoch: 4}}
             )

    assert details[:reason] == :invalid_pending_commit_hint
    assert details[:field] == "pending_commit"
    assert details[:expected] == false
    assert details[:actual] == true

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

  test "multi-step lifecycle churn keeps deterministic epoch/state transitions",
       %{conversation: conversation} do
    assert {:ok, staged_commit} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit,
               %{success_payload: %{epoch: "4"}}
             )

    assert staged_commit.epoch == 3
    assert staged_commit.pending_commit["staged_epoch"] == 4

    assert {:ok, merged_commit} =
             ConversationSecurityLifecycle.merge_pending_commit(
               conversation.id,
               %{success_payload: %{epoch: "4"}}
             )

    assert merged_commit.epoch == 4
    assert merged_commit.pending_commit == nil

    assert {:ok, staged_add} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_add
             )

    assert staged_add.epoch == 4
    assert staged_add.pending_commit["operation"] == "mls_add"
    assert staged_add.pending_commit["staged_epoch"] == 5

    assert {:ok, cleared_add} =
             ConversationSecurityLifecycle.clear_pending_commit(conversation.id)

    assert cleared_add.epoch == 4
    assert cleared_add.pending_commit == nil

    assert {:ok, staged_remove} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_remove,
               %{success_payload: %{epoch: 5}}
             )

    assert staged_remove.pending_commit["staged_epoch"] == 5

    assert {:ok, merged_remove} =
             ConversationSecurityLifecycle.merge_pending_commit(
               conversation.id,
               %{success_payload: %{epoch: 5}}
             )

    assert merged_remove.epoch == 5
    assert merged_remove.pending_commit == nil

    assert {:ok, staged_update} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_update
             )

    assert staged_update.pending_commit["staged_epoch"] == 6

    assert {:ok, merged_update} =
             ConversationSecurityLifecycle.merge_pending_commit(conversation.id)

    assert merged_update.epoch == 6
    assert merged_update.pending_commit == nil
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

  test "concurrent mixed stage operations have a single winner and stable pending metadata",
       %{conversation: conversation} do
    operations = [:mls_commit, :mls_update, :mls_add, :mls_remove]

    results =
      1..16
      |> Task.async_stream(
        fn index ->
          operation = Enum.at(operations, rem(index, length(operations)))

          attrs =
            if operation == :mls_remove,
              do: %{remove_target: "recipient"},
              else: %{}

          {operation,
           ConversationSecurityLifecycle.stage_pending_commit(
             conversation.id,
             operation,
             attrs
           )}
        end,
        max_concurrency: 16,
        timeout: 5_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    successes =
      Enum.filter(results, fn {_operation, result} ->
        match?({:ok, _}, result)
      end)

    failures =
      Enum.filter(results, fn {_operation, result} ->
        match?({:error, _, _}, result)
      end)

    assert length(successes) == 1
    assert length(failures) == 15

    assert Enum.all?(failures, fn {_operation, {:error, code, _details}} ->
             code in [:pending_proposals, :storage_inconsistent]
           end)

    {winning_operation, {:ok, winner_state}} = hd(successes)

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert is_map(persisted.pending_commit)

    assert persisted.pending_commit["operation"] ==
             Atom.to_string(winning_operation)

    assert persisted.pending_commit["staged_epoch"] == 4

    assert winner_state.pending_commit["operation"] ==
             Atom.to_string(winning_operation)
  end

  test "concurrent clear-vs-merge race keeps lifecycle usable and fail-closed",
       %{conversation: conversation} do
    assert {:ok, _staged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_commit
             )

    actions = [:clear, :merge, :clear, :merge, :clear, :merge, :clear, :merge]

    results =
      actions
      |> Task.async_stream(
        fn action ->
          result =
            case action do
              :clear ->
                ConversationSecurityLifecycle.clear_pending_commit(
                  conversation.id
                )

              :merge ->
                ConversationSecurityLifecycle.merge_pending_commit(
                  conversation.id
                )
            end

          {action, result}
        end,
        max_concurrency: 8,
        timeout: 5_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    merge_successes =
      Enum.count(results, fn
        {:merge, {:ok, _}} -> true
        _ -> false
      end)

    assert merge_successes <= 1

    assert Enum.all?(results, fn
             {_action, {:ok, _}} ->
               true

             {_action, {:error, code, details}} ->
               code in [:commit_rejected, :storage_inconsistent] and
                 details[:reason] in [
                   :no_pending_commit,
                   :lock_version_mismatch
                 ]
           end)

    assert {:ok, persisted} =
             ConversationSecurityStateStore.load(conversation.id)

    assert persisted.pending_commit == nil
    assert persisted.epoch in [3, 4]

    assert {:ok, restaged} =
             ConversationSecurityLifecycle.stage_pending_commit(
               conversation.id,
               :mls_update
             )

    assert restaged.pending_commit["operation"] == "mls_update"
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

  describe "epoch-0 boundary (initial group state)" do
    test "stage and merge first commit on epoch-0 group succeeds with merge_epoch == 1" do
      fresh_conversation = conversation_fixture(%{conversation_type: :direct})

      assert {:ok, persisted} =
               ConversationSecurityStateStore.upsert(
                 fresh_conversation.id,
                 %{state: snapshot_payload(), epoch: 0, protocol: "mls"},
                 nil
               )

      assert persisted.epoch == 0

      assert {:ok, staged} =
               ConversationSecurityLifecycle.stage_pending_commit(
                 fresh_conversation.id,
                 :mls_commit
               )

      assert staged.epoch == 0
      assert staged.pending_commit["staged_epoch"] == 1

      assert {:ok, merged} =
               ConversationSecurityLifecycle.merge_pending_commit(
                 fresh_conversation.id
               )

      assert merged.epoch == 1
      assert merged.pending_commit == nil
    end

    test "merge_pending_commit fails on epoch-0 group when staged_epoch == 0" do
      fresh_conversation = conversation_fixture(%{conversation_type: :direct})

      assert {:ok, _persisted} =
               ConversationSecurityStateStore.upsert(
                 fresh_conversation.id,
                 %{state: snapshot_payload(), epoch: 0, protocol: "mls"},
                 nil
               )

      put_pending_commit!(
        fresh_conversation.id,
        %{"operation" => "mls_commit", "staged_epoch" => 0}
      )

      assert {:error, :commit_rejected, details} =
               ConversationSecurityLifecycle.merge_pending_commit(
                 fresh_conversation.id
               )

      assert details[:reason] == :epoch_too_low
      assert details[:current_epoch] == 0
      assert details[:staged_epoch] == 0
    end
  end

  describe "non-remove operations with no active revocations" do
    test "non-remove commit succeeds when no active revocations exist",
         %{conversation: conversation} do
      assert {:ok, staged} =
               ConversationSecurityLifecycle.stage_pending_commit(
                 conversation.id,
                 :mls_add
               )

      assert staged.pending_commit["operation"] == "mls_add"

      assert {:ok, merged} =
               ConversationSecurityLifecycle.merge_pending_commit(
                 conversation.id
               )

      assert merged.epoch == 4
      assert merged.pending_commit == nil
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
