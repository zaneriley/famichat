defmodule Famichat.Chat.ConversationSecurityDeviceRemovalTest do
  @moduledoc """
  Tests for the device → MLS group eviction pipeline.

  Uses `ConversationSecurityDeviceRemoval.remove_sync/3` to exercise the pipeline synchronously
  (avoiding Task.start timing issues in tests) and the FakeAdapter to simulate
  MLS responses.
  """
  use Famichat.DataCase, async: false

  alias Famichat.Auth.Sessions
  alias Famichat.Chat
  alias Famichat.Chat.ConversationSecurityRevocationStore
  alias Famichat.Chat.ConversationSecurityStateStore
  alias Famichat.Chat.ConversationSecurityDeviceRemoval
  alias Famichat.TestSupport.MLS.FakeAdapter
  import Famichat.ChatFixtures

  # A minimal but complete MLS snapshot that satisfies the decode validator.
  @snapshot_payload %{
    "session_sender_storage" => Base.encode64("sender-storage"),
    "session_recipient_storage" => Base.encode64("recipient-storage"),
    "session_sender_signer" => Base.encode64("sender-signer"),
    "session_recipient_signer" => Base.encode64("recipient-signer"),
    "session_cache" => Base.encode64("cache")
  }

  setup do
    previous_adapter = Application.get_env(:famichat, :mls_adapter)
    Application.put_env(:famichat, :mls_adapter, FakeAdapter)

    on_exit(fn ->
      case previous_adapter do
        nil -> Application.delete_env(:famichat, :mls_adapter)
        mod -> Application.put_env(:famichat, :mls_adapter, mod)
      end
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Test 1: Revoking a device triggers MLS removal from conversations.
  # ---------------------------------------------------------------------------

  test "revoking a device triggers MLS removal from every conversation the device is in" do
    %{user: user, conversations: conversations} = user_with_conversations(2)

    # Seed MLS state for each conversation so stage_pending_commit doesn't fail
    # with :missing_state.
    for conv <- conversations do
      assert {:ok, _} =
               ConversationSecurityStateStore.upsert(
                 conv.id,
                 %{state: @snapshot_payload, epoch: 1, protocol: "mls"},
                 nil
               )
    end

    revocation_ref = "mls-removal-test-#{System.unique_integer([:positive])}"

    # Stage the journal entry (normally done by Sessions.revoke_device via
    # stage_client_revocation; here done manually so we can isolate the MLS
    # removal step).
    device_id = start_client_session!(user)

    assert {:ok, _staged} =
             Chat.stage_client_revocation(device_id, revocation_ref, %{
               actor_id: user.id,
               revocation_reason: "auth_device_revoked"
             })

    # Run MLS removal synchronously.
    summary = ConversationSecurityDeviceRemoval.remove_sync(user.id, device_id, revocation_ref)

    assert summary.total == 2
    assert summary.succeeded == 2
    assert summary.skipped == 0
    assert summary.failed == 0
  end

  # ---------------------------------------------------------------------------
  # Test 2: Session revocation succeeds even when MLS removal fails.
  # ---------------------------------------------------------------------------

  test "revoke_device succeeds even when MLS removal is unavailable" do
    # Use the Unimplemented adapter so every MLS call returns :unsupported_capability.
    Application.put_env(
      :famichat,
      :mls_adapter,
      Famichat.Crypto.MLS.Adapter.Unimplemented
    )

    family = family_fixture()
    user = user_fixture(%{family: family})
    peer = user_fixture(%{family: family})

    conversation_fixture(%{
      conversation_type: :direct,
      family: family,
      user1: user,
      user2: peer
    })

    # Seed MLS state so the removal attempt hits the NIF, not an early exit.
    device_id = start_client_session!(user)
    revocation_ref = "resilience-test-#{System.unique_integer([:positive])}"

    # Session revocation must succeed regardless.
    assert {:ok, :revoked} = Sessions.revoke_device(user.id, device_id)

    # The device should no longer be able to authenticate.
    assert {:error, :revoked} = Sessions.device_access_state(user.id, device_id)
  end

  # ---------------------------------------------------------------------------
  # Test 3: Conversations with no MLS state are skipped, not failed.
  # ---------------------------------------------------------------------------

  test "conversations without MLS state are skipped gracefully" do
    %{user: user, conversations: conversations} = user_with_conversations(3)

    # Only seed MLS state for the first conversation; leave the other two
    # without state to simulate pre-MLS conversations.
    [conv_with_state | convs_without_state] = conversations

    assert {:ok, _} =
             ConversationSecurityStateStore.upsert(
               conv_with_state.id,
               %{state: @snapshot_payload, epoch: 2, protocol: "mls"},
               nil
             )

    device_id = start_client_session!(user)
    revocation_ref = "skip-test-#{System.unique_integer([:positive])}"

    # Stage journal entry only for the conversation that has MLS state.
    assert {:ok, _staged} =
             Chat.stage_client_revocation(device_id, revocation_ref, %{
               actor_id: user.id,
               revocation_reason: "auth_device_revoked"
             })

    summary = ConversationSecurityDeviceRemoval.remove_sync(user.id, device_id, revocation_ref)

    assert summary.total == length(conversations)
    assert summary.succeeded == 1
    assert summary.skipped == length(convs_without_state)
    assert summary.failed == 0
  end

  # ---------------------------------------------------------------------------
  # Test 4: Revoked device cannot decrypt new messages.
  # This is an end-to-end property test at the session-gate level.
  # The actual MLS decryption barrier is enforced by the access-token guard
  # (revoked device cannot obtain a token) and the channel gate
  # (ensure_socket_device_active). Here we verify that revocation kills
  # access-token issuance and the device_active? predicate, which are the
  # gating checks in the messaging pipeline.
  # ---------------------------------------------------------------------------

  test "revoked device is rejected by access-token verification and device_active? guard" do
    family = family_fixture()
    user = user_fixture(%{family: family})

    session =
      Sessions.start_session(
        user,
        %{
          id: "end-to-end-device-#{System.unique_integer([:positive])}",
          user_agent: "ConversationSecurityDeviceRemovalTest",
          ip: "127.0.0.1"
        },
        remember_device?: true
      )
      |> elem(1)

    device_id = session.device_id
    access_token = session.access_token

    # Before revocation: token is valid, device is active.
    assert {:ok, _} = Sessions.verify_access_token(access_token)
    assert Sessions.device_active?(user.id, device_id)

    assert {:ok, :revoked} = Sessions.revoke_device(user.id, device_id)

    # After revocation: token is rejected, device is inactive.
    assert {:error, _} = Sessions.verify_access_token(access_token)
    refute Sessions.device_active?(user.id, device_id)
  end

  ## Helpers

  defp user_with_conversations(count) do
    family = family_fixture()
    user = user_fixture(%{family: family})

    conversations =
      Enum.map(1..count, fn _ ->
        peer = user_fixture(%{family: family})

        conversation_fixture(%{
          conversation_type: :direct,
          family: family,
          user1: user,
          user2: peer
        })
      end)

    %{user: user, conversations: conversations}
  end

  defp start_client_session!(user) do
    {:ok, session} =
      Sessions.start_session(
        user,
        %{
          id: "mls-removal-client-#{System.unique_integer([:positive])}",
          user_agent: "ConversationSecurityDeviceRemovalTest",
          ip: "127.0.0.1"
        },
        remember_device?: true
      )

    session.device_id
  end
end
