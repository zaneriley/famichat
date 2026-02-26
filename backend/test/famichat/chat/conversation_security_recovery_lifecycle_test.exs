defmodule Famichat.Chat.ConversationSecurityRecoveryLifecycleTest do
  use Famichat.DataCase, async: false

  import Ecto.Query, warn: false

  alias Famichat.Chat.{
    ConversationSecurityRecoveryLifecycle,
    ConversationSecurityRecoveryStore,
    ConversationSecurityState,
    ConversationSecurityStateStore
  }

  alias Famichat.Repo
  import Famichat.ChatFixtures

  defmodule RecoverySuccessAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    def nif_version, do: {:ok, %{}}
    def nif_health, do: {:ok, %{status: "ok"}}
    def create_key_package(_params), do: {:ok, %{}}
    def create_group(_params), do: {:ok, %{}}
    def process_incoming(_params), do: {:ok, %{plaintext: "ok"}}
    def commit_to_pending(_params), do: {:ok, %{}}
    def mls_commit(_params), do: {:ok, %{}}
    def mls_update(_params), do: {:ok, %{}}
    def mls_add(_params), do: {:ok, %{}}
    def mls_remove(_params), do: {:ok, %{}}
    def merge_staged_commit(_params), do: {:ok, %{}}
    def clear_pending_commit(_params), do: {:ok, %{}}
    def create_application_message(_params), do: {:ok, %{ciphertext: "c"}}
    def export_group_info(_params), do: {:ok, %{}}
    def export_ratchet_tree(_params), do: {:ok, %{}}

    def join_from_welcome(params) do
      calls = Process.get(:rejoin_calls, 0)
      Process.put(:rejoin_calls, calls + 1)

      token = Map.get(params, :rejoin_token) || Map.get(params, "rejoin_token")
      group_id = Map.get(params, :group_id) || Map.get(params, "group_id")

      {:ok,
       %{
         group_id: group_id,
         group_state_ref: "state:#{token}",
         audit_id: "audit:#{token}",
         epoch: 7,
         session_sender_storage: Base.encode64("sender-storage:#{token}"),
         session_recipient_storage: Base.encode64("recipient-storage:#{token}"),
         session_sender_signer: Base.encode64("sender-signer:#{token}"),
         session_recipient_signer: Base.encode64("recipient-signer:#{token}"),
         session_cache: ""
       }}
    end
  end

  defmodule RecoveryMissingSnapshotAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    def nif_version, do: {:ok, %{}}
    def nif_health, do: {:ok, %{status: "ok"}}
    def create_key_package(_params), do: {:ok, %{}}
    def create_group(_params), do: {:ok, %{}}
    def process_incoming(_params), do: {:ok, %{plaintext: "ok"}}
    def commit_to_pending(_params), do: {:ok, %{}}
    def mls_commit(_params), do: {:ok, %{}}
    def mls_update(_params), do: {:ok, %{}}
    def mls_add(_params), do: {:ok, %{}}
    def mls_remove(_params), do: {:ok, %{}}
    def merge_staged_commit(_params), do: {:ok, %{}}
    def clear_pending_commit(_params), do: {:ok, %{}}
    def create_application_message(_params), do: {:ok, %{ciphertext: "c"}}
    def export_group_info(_params), do: {:ok, %{}}
    def export_ratchet_tree(_params), do: {:ok, %{}}

    def join_from_welcome(_params) do
      {:ok, %{group_state_ref: "state:x", audit_id: "audit:x", epoch: 1}}
    end
  end

  setup do
    previous_adapter = Application.get_env(:famichat, :mls_adapter)

    on_exit(fn ->
      restore_env(:mls_adapter, previous_adapter)
      Process.delete(:rejoin_calls)
    end)

    conversation = conversation_fixture(%{conversation_type: :direct})
    {:ok, conversation: conversation}
  end

  test "recover persists state and marks journal entry completed",
       %{conversation: conversation} do
    Application.put_env(:famichat, :mls_adapter, RecoverySuccessAdapter)

    assert {:error, :not_found, _details} =
             ConversationSecurityStateStore.load(conversation.id)

    assert {:ok, result} =
             ConversationSecurityRecoveryLifecycle.recover_conversation_security_state(
               conversation.id,
               "recovery-ref-1",
               %{
                 rejoin_token: "token-1",
                 recovery_reason: "state_loss_recovery"
               }
             )

    assert result.status == :completed
    assert result.idempotent == false
    assert result.recovered_epoch == 7
    assert result.audit_id == "audit:token-1"
    assert result.group_state_ref == "state:token-1"

    assert {:ok, state} = ConversationSecurityStateStore.load(conversation.id)
    assert state.epoch == 7
    assert state.pending_commit == nil

    assert {:ok, recovery} =
             ConversationSecurityRecoveryStore.load_by_ref(
               conversation.id,
               "recovery-ref-1"
             )

    assert recovery.status == :completed
    assert recovery.recovery_reason == "state_loss_recovery"
    assert recovery.recovered_epoch == 7
  end

  test "recovery is idempotent for duplicate recovery_ref",
       %{conversation: conversation} do
    Application.put_env(:famichat, :mls_adapter, RecoverySuccessAdapter)
    Process.put(:rejoin_calls, 0)

    assert {:ok, first} =
             ConversationSecurityRecoveryLifecycle.recover_conversation_security_state(
               conversation.id,
               "recovery-ref-2",
               %{rejoin_token: "token-2"}
             )

    assert first.idempotent == false
    assert Process.get(:rejoin_calls) == 1

    assert {:ok, second} =
             ConversationSecurityRecoveryLifecycle.recover_conversation_security_state(
               conversation.id,
               "recovery-ref-2",
               %{rejoin_token: "token-2"}
             )

    assert second.idempotent == true
    assert second.recovery_id == first.recovery_id
    assert Process.get(:rejoin_calls) == 1
  end

  test "existing in-progress recovery returns recovery_in_progress",
       %{conversation: conversation} do
    Application.put_env(:famichat, :mls_adapter, RecoverySuccessAdapter)

    assert {:ok, {:started, started}} =
             ConversationSecurityRecoveryStore.start_or_load(
               conversation.id,
               "recovery-ref-3",
               %{}
             )

    assert {:error, :recovery_in_progress, details} =
             ConversationSecurityRecoveryLifecycle.recover_conversation_security_state(
               conversation.id,
               "recovery-ref-3",
               %{rejoin_token: "token-3"}
             )

    assert details[:recovery_id] == started.id
    assert details[:reason] == :recovery_already_in_progress
  end

  test "failed recovery is persisted and replayed as recovery_failed",
       %{conversation: conversation} do
    Application.put_env(
      :famichat,
      :mls_adapter,
      RecoveryMissingSnapshotAdapter
    )

    assert {:error, :storage_inconsistent, details} =
             ConversationSecurityRecoveryLifecycle.recover_conversation_security_state(
               conversation.id,
               "recovery-ref-4",
               %{rejoin_token: "token-4"}
             )

    assert details[:reason] == :missing_recovery_snapshot

    assert {:ok, failed} =
             ConversationSecurityRecoveryStore.load_by_ref(
               conversation.id,
               "recovery-ref-4"
             )

    assert failed.status == :failed
    assert failed.error_code == "storage_inconsistent"
    assert failed.error_reason == "missing_recovery_snapshot"

    assert {:error, :recovery_failed, replayed_details} =
             ConversationSecurityRecoveryLifecycle.recover_conversation_security_state(
               conversation.id,
               "recovery-ref-4",
               %{rejoin_token: "token-4"}
             )

    assert replayed_details[:reason] == :recovery_previously_failed
    assert replayed_details[:error_code] == "storage_inconsistent"
  end

  test "recovery replaces tampered persisted state and restores usability",
       %{conversation: conversation} do
    Application.put_env(:famichat, :mls_adapter, RecoverySuccessAdapter)

    assert {:ok, _persisted} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{state: snapshot_payload(), epoch: 2, protocol: "mls"},
               nil
             )

    {count, _rows} =
      Repo.update_all(
        from(s in ConversationSecurityState,
          where: s.conversation_id == ^conversation.id
        ),
        set: [state_ciphertext: <<9, 9, 9, 9>>]
      )

    assert count == 1

    assert {:error, :state_decode_failed, _details} =
             ConversationSecurityStateStore.load(conversation.id)

    assert {:ok, _result} =
             ConversationSecurityRecoveryLifecycle.recover_conversation_security_state(
               conversation.id,
               "recovery-ref-5",
               %{rejoin_token: "token-5"}
             )

    assert {:ok, repaired_state} =
             ConversationSecurityStateStore.load(conversation.id)

    assert repaired_state.epoch == 7
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

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
