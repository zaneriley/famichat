defmodule Famichat.Chat.ConversationSecurityRecoveryStoreTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.ConversationSecurityRecoveryStore
  import Famichat.ChatFixtures

  test "start_or_load creates an in-progress recovery and deduplicates by recovery_ref" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, {:started, started}} =
             ConversationSecurityRecoveryStore.start_or_load(
               conversation.id,
               "recovery-ref-1",
               %{recovery_reason: "state_loss_recovery"}
             )

    assert started.status == :in_progress
    assert started.recovery_ref == "recovery-ref-1"
    assert started.recovery_reason == "state_loss_recovery"

    assert {:ok, {:existing, existing}} =
             ConversationSecurityRecoveryStore.start_or_load(
               conversation.id,
               "recovery-ref-1",
               %{}
             )

    assert existing.id == started.id
    assert existing.status == :in_progress
  end

  test "mark_completed transitions in-progress recovery to completed" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, {:started, started}} =
             ConversationSecurityRecoveryStore.start_or_load(
               conversation.id,
               "recovery-ref-2",
               %{}
             )

    assert {:ok, completed} =
             ConversationSecurityRecoveryStore.mark_completed(started.id, %{
               recovered_epoch: 9,
               audit_id: "audit:token-1",
               group_state_ref: "state:token-1"
             })

    assert completed.status == :completed
    assert completed.recovered_epoch == 9
    assert completed.audit_id == "audit:token-1"
    assert completed.group_state_ref == "state:token-1"
    assert completed.error_code == nil
  end

  test "mark_failed transitions in-progress recovery to failed" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, {:started, started}} =
             ConversationSecurityRecoveryStore.start_or_load(
               conversation.id,
               "recovery-ref-3",
               %{recovery_reason: "decode_repair"}
             )

    assert {:ok, failed} =
             ConversationSecurityRecoveryStore.mark_failed(started.id, %{
               error_code: :storage_inconsistent,
               error_reason: :missing_recovery_snapshot
             })

    assert failed.status == :failed
    assert failed.error_code == "storage_inconsistent"
    assert failed.error_reason == "missing_recovery_snapshot"
    assert failed.recovery_reason == "decode_repair"
  end
end
