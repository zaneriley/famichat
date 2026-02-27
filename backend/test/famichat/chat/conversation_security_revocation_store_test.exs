defmodule Famichat.Chat.ConversationSecurityRevocationStoreTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.ConversationSecurityRevocationStore
  import Famichat.ChatFixtures

  test "start_or_load creates an in-progress revocation and deduplicates by revocation_ref" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, {:started, started}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-ref-1",
               %{
                 subject_type: :client,
                 subject_id: "client-1",
                 revocation_reason: "device_revoked"
               }
             )

    assert started.status == :in_progress
    assert started.subject_type == :client
    assert started.subject_id == "client-1"
    assert started.revocation_reason == "device_revoked"

    assert {:ok, {:existing, existing}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-ref-1",
               %{subject_type: :client, subject_id: "client-1"}
             )

    assert existing.id == started.id
    assert existing.status == :in_progress
  end

  test "start_or_load rejects idempotency replay with mismatched subject identity" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, {:started, started}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-ref-identity-mismatch",
               %{subject_type: :client, subject_id: "client-identity-1"}
             )

    assert {:error, :idempotency_conflict, details} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-ref-identity-mismatch",
               %{subject_type: :client, subject_id: "client-identity-2"}
             )

    assert details[:reason] == :revocation_ref_subject_mismatch
    assert details[:expected_subject_type] == :client
    assert details[:expected_subject_id] == "client-identity-1"
    assert details[:received_subject_type] == :client
    assert details[:received_subject_id] == "client-identity-2"

    assert {:ok, {:existing, replay}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-ref-identity-mismatch",
               %{subject_type: :client, subject_id: "client-identity-1"}
             )

    assert replay.id == started.id
  end

  test "mark_pending_commit transitions in-progress revocation and is idempotent" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, {:started, started}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-ref-2",
               %{subject_type: :user, subject_id: "user-123"}
             )

    assert {:ok, pending} =
             ConversationSecurityRevocationStore.mark_pending_commit(
               started.id,
               %{proposal_ref: "proposal-1"}
             )

    assert pending.status == :pending_commit
    assert pending.proposal_ref == "proposal-1"

    assert {:ok, idempotent} =
             ConversationSecurityRevocationStore.mark_pending_commit(
               started.id,
               %{}
             )

    assert idempotent.id == pending.id
    assert idempotent.status == :pending_commit
    assert idempotent.proposal_ref == "proposal-1"
  end

  test "mark_pending_commit rejects transition from failed revocation" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, {:started, started}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-ref-3",
               %{subject_type: :client, subject_id: "client-3"}
             )

    assert {:ok, failed} =
             ConversationSecurityRevocationStore.mark_failed(started.id, %{
               error_code: :storage_inconsistent,
               error_reason: :pending_commit_stage_failed
             })

    assert failed.status == :failed

    assert {:error, :invalid_state_transition, details} =
             ConversationSecurityRevocationStore.mark_pending_commit(
               started.id,
               %{}
             )

    assert details[:reason] == :revocation_already_failed
  end

  test "concurrent start_or_load has exactly one started record and deterministic existing replays" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    results =
      1..8
      |> Task.async_stream(
        fn _ ->
          ConversationSecurityRevocationStore.start_or_load(
            conversation.id,
            "revocation-ref-concurrent",
            %{subject_type: :client, subject_id: "client-concurrent"}
          )
        end,
        max_concurrency: 8,
        timeout: 5_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    started =
      Enum.filter(results, fn
        {:ok, {:started, _record}} -> true
        _ -> false
      end)

    existing =
      Enum.filter(results, fn
        {:ok, {:existing, _record}} -> true
        _ -> false
      end)

    assert length(started) == 1
    assert length(existing) == 7

    assert {:ok, revocations} =
             ConversationSecurityRevocationStore.list_for_conversation(
               conversation.id
             )

    matching =
      Enum.filter(revocations, fn record ->
        record.revocation_ref == "revocation-ref-concurrent" and
          record.subject_type == :client and
          record.subject_id == "client-concurrent"
      end)

    assert length(matching) == 1
  end

  test "list_active_for_conversation returns only in-progress and pending records" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, {:started, in_progress}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-active-in-progress",
               %{subject_type: :client, subject_id: "client-active-1"}
             )

    assert {:ok, {:started, pending_base}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-active-pending",
               %{subject_type: :client, subject_id: "client-active-2"}
             )

    assert {:ok, _pending} =
             ConversationSecurityRevocationStore.mark_pending_commit(
               pending_base.id,
               %{proposal_ref: "proposal-active-2"}
             )

    assert {:ok, {:started, completed_base}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-inactive-completed",
               %{subject_type: :user, subject_id: "user-inactive-1"}
             )

    assert {:ok, _completed} =
             ConversationSecurityRevocationStore.mark_completed(
               completed_base.id,
               %{committed_epoch: 9}
             )

    assert {:ok, {:started, failed_base}} =
             ConversationSecurityRevocationStore.start_or_load(
               conversation.id,
               "revocation-inactive-failed",
               %{subject_type: :user, subject_id: "user-inactive-2"}
             )

    assert {:ok, _failed} =
             ConversationSecurityRevocationStore.mark_failed(failed_base.id, %{
               error_code: :intent_generation_failed
             })

    assert {:ok, active} =
             ConversationSecurityRevocationStore.list_active_for_conversation(
               conversation.id
             )

    assert Enum.map(active, & &1.id) |> Enum.sort() ==
             Enum.sort([in_progress.id, pending_base.id])
  end
end
