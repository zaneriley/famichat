defmodule Famichat.Chat.ConversationSecurityStateStoreTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.{
    ConversationSecurityState,
    ConversationSecurityStateStore
  }

  alias Famichat.Repo
  import Famichat.ChatFixtures

  test "load returns not_found when state does not exist" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:error, :not_found, details} =
             ConversationSecurityStateStore.load(conversation.id)

    assert details[:reason] == :missing_state
  end

  test "upsert persists and loads durable conversation security state" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, persisted} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{state: snapshot_payload(), epoch: 7, protocol: "mls"},
               nil
             )

    assert persisted.conversation_id == conversation.id
    assert persisted.protocol == "mls"
    assert persisted.epoch == 7
    assert persisted.lock_version == 1
    assert persisted.state == snapshot_payload()

    assert {:ok, loaded} =
             ConversationSecurityStateStore.load(conversation.id)

    assert loaded == persisted
  end

  test "upsert enforces optimistic locking and returns stale_state on conflict" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, first} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{state: snapshot_payload(), epoch: 1, protocol: "mls"},
               nil
             )

    assert {:ok, second} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{state: updated_snapshot_payload(), epoch: 2, protocol: "mls"},
               first.lock_version
             )

    assert second.lock_version == first.lock_version + 1
    assert second.state == updated_snapshot_payload()
    assert second.epoch == 2

    assert {:error, :stale_state, details} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{state: snapshot_payload(), epoch: 3, protocol: "mls"},
               first.lock_version
             )

    assert details[:reason] == :lock_version_mismatch
  end

  test "load fails closed when persisted state ciphertext is tampered" do
    conversation = conversation_fixture(%{conversation_type: :direct})

    assert {:ok, persisted} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{state: snapshot_payload(), epoch: 0, protocol: "mls"},
               nil
             )

    {count, _rows} =
      Repo.update_all(
        from(s in ConversationSecurityState,
          where: s.conversation_id == ^conversation.id
        ),
        set: [state_ciphertext: <<1, 2, 3>>]
      )

    assert count == 1

    assert {:error, :state_decode_failed, details} =
             ConversationSecurityStateStore.load(conversation.id)

    assert details[:reason] == :state_decode_failed
    assert details[:operation] == :load

    assert is_integer(persisted.lock_version)
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

  defp updated_snapshot_payload do
    %{
      "session_sender_storage" => Base.encode64("sender-storage-v2"),
      "session_recipient_storage" => Base.encode64("recipient-storage-v2"),
      "session_sender_signer" => Base.encode64("sender-signer-v2"),
      "session_recipient_signer" => Base.encode64("recipient-signer-v2"),
      "session_cache" => Base.encode64("cache-v2")
    }
  end
end
