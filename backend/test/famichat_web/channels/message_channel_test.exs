defmodule FamichatWeb.MessageChannelTest do
  use FamichatWeb.ChannelCase
  import Phoenix.ChannelTest
  require Logger

  alias Famichat.Accounts.{HouseholdMembership, User, UserDevice}
  alias Famichat.Auth.Sessions

  alias Famichat.Chat.{
    Conversation,
    ConversationParticipant,
    Message,
    MessageRateLimiter
  }

  alias Famichat.ChatFixtures
  alias Famichat.Repo
  alias Famichat.TestSupport.MLS.RecoveryGateAdapter
  alias FamichatWeb.MessageChannel
  alias FamichatWeb.UserSocket

  @endpoint FamichatWeb.Endpoint
  @access_salt "user_access_v1"
  @valid_user_id "123e4567-e89b-12d3-a456-426614174000"
  @second_user_id "223e4567-e89b-12d3-a456-426614174001"
  @third_user_id "323e4567-e89b-12d3-a456-426614174002"
  @self_conversation_id "44444444-4444-4444-4444-444444444444"
  @direct_conversation_id "11111111-1111-1111-1111-111111111111"
  @group_conversation_id "22222222-2222-2222-2222-222222222222"
  @family_conversation_id "33333333-3333-3333-3333-333333333333"
  @telemetry_timeout 1000
  @encryption_metadata_fields ~w(version_tag encryption_flag key_id)
  @encryption_metadata_atom_fields [:version_tag, :encryption_flag, :key_id]

  setup do
    # Start a telemetry handler for our tests
    test_pid = self()
    handler_id = "message-channel-test-#{:erlang.unique_integer()}"

    Logger.debug("Setting up telemetry handler with id: #{handler_id}")

    # Handler for join events
    :ok =
      :telemetry.attach(
        handler_id,
        [:famichat, :message_channel, :join],
        fn event_name, measurements, metadata, _ ->
          Logger.debug("""
          Telemetry event received in test:
          - event_name: #{inspect(event_name)}
          - measurements: #{inspect(measurements)}
          - metadata: #{inspect(metadata)}
          """)

          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

    # Handler for broadcast events
    broadcast_handler_id = "#{handler_id}-broadcast"

    :ok =
      :telemetry.attach(
        broadcast_handler_id,
        [:famichat, :message_channel, :broadcast],
        fn event_name, measurements, metadata, _ ->
          Logger.debug("""
          Broadcast telemetry event received in test:
          - event_name: #{inspect(event_name)}
          - measurements: #{inspect(measurements)}
          - metadata: #{inspect(metadata)}
          """)

          send(
            test_pid,
            {:broadcast_telemetry_event, event_name, measurements, metadata}
          )
        end,
        nil
      )

    on_exit(fn ->
      Logger.debug("Detaching telemetry handlers")
      :telemetry.detach(handler_id)
      :telemetry.detach(broadcast_handler_id)
    end)

    family = ChatFixtures.family_fixture()

    user =
      insert_user_with_id(@valid_user_id, family.id, %{
        username: "primary_user",
        email: "primary_user@example.com"
      })

    second_user =
      insert_user_with_id(@second_user_id, family.id, %{
        username: "secondary_user",
        email: "secondary_user@example.com"
      })

    third_user =
      insert_user_with_id(@third_user_id, family.id, %{
        username: "tertiary_user",
        email: "tertiary_user@example.com"
      })

    self_conversation =
      insert_conversation(@self_conversation_id, :self, family.id, [user.id])

    direct_conversation =
      insert_conversation(@direct_conversation_id, :direct, family.id, [
        user.id,
        second_user.id
      ])

    group_conversation =
      insert_conversation(@group_conversation_id, :group, family.id, [
        user.id,
        second_user.id,
        third_user.id
      ])

    family_conversation =
      insert_conversation(@family_conversation_id, :family, family.id, [
        user.id,
        second_user.id,
        third_user.id
      ])

    user_session = issue_access_token(user)

    {:ok,
     %{
       family: family,
       user: user,
       second_user: second_user,
       user_session: user_session,
       self_conversation: self_conversation,
       direct_conversation: direct_conversation,
       group_conversation: group_conversation,
       family_conversation: family_conversation
     }}
  end

  describe "socket connection" do
    test "returns error when token is invalid" do
      invalid_token = "invalid_token"

      assert {:error, %{reason: "invalid_token"}} =
               connect(UserSocket, %{"token" => invalid_token})
    end

    test "successfully connects with valid token", %{user_session: user_session} do
      token = user_session.access_token
      assert {:ok, socket} = connect(UserSocket, %{"token" => token})
      assert socket.assigns.user_id == @valid_user_id
      assert socket.assigns.device_id == user_session.device.device_id
    end

    test "rejects connections for revoked devices", %{user: user} do
      session = issue_access_token(user)

      assert {:ok, :revoked} =
               Sessions.revoke_device(user.id, session.device.device_id)

      assert {:error, %{reason: "invalid_token"}} =
               connect(UserSocket, %{"token" => session.access_token})
    end

    test "revoking a connected device blocks future joins", %{
      user: user,
      user_session: user_session
    } do
      {:ok, socket} =
        connect(UserSocket, %{"token" => user_session.access_token})

      assert {:ok, _, channel_socket} =
               subscribe_and_join(
                 socket,
                 MessageChannel,
                 "message:direct:#{@direct_conversation_id}"
               )

      assert {:ok, :revoked} =
               Sessions.revoke_device(user.id, user_session.device.device_id)

      assert {:error, %{reason: "device_revoked"}} =
               subscribe_and_join(
                 socket,
                 MessageChannel,
                 "message:group:#{@group_conversation_id}"
               )

      ref = push(channel_socket, "new_msg", %{"body" => "should not send"})
      assert_reply ref, :error, %{reason: "device_revoked"}
      refute_broadcast "new_msg", _

      ack_ref = push(channel_socket, "message_ack", %{"message_id" => "msg-1"})
      assert_reply ack_ref, :error, %{reason: "device_revoked"}
    end

    test "revoked connected device is blocked from receiving new messages and gets explicit security state",
         %{
           user: user,
           user_session: user_session
         } do
      {:ok, socket} =
        connect(UserSocket, %{"token" => user_session.access_token})

      topic = "message:direct:#{@direct_conversation_id}"

      assert {:ok, _, _channel_socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      assert {:ok, :revoked} =
               Sessions.revoke_device(user.id, user_session.device.device_id)

      @endpoint.broadcast!(topic, "new_msg", %{
        "body" => "should not deliver",
        "user_id" => @second_user_id
      })

      assert_push "security_state", payload

      assert (payload[:reason] || payload["reason"]) == "device_revoked"
      assert (payload[:action] || payload["action"]) == "reauth_required"

      refute_push "new_msg", _
    end
  end

  describe "channel join - type-aware format" do
    setup %{
      user_session: user_session,
      family: family,
      second_user: second_user
    } do
      {:ok, socket} =
        connect(UserSocket, %{"token" => user_session.access_token})

      {:ok,
       %{
         socket: socket,
         family: family,
         second_user: second_user,
         session: user_session
       }}
    end

    test "successfully joins self conversation channel", %{
      socket: socket
    } do
      topic = "message:self:#{@valid_user_id}"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert metadata for successful join
      assert metadata.status == :success
      assert metadata.encryption_status == "enabled"
      assert metadata.user_id == @valid_user_id
      assert metadata.conversation_type == "self"
      assert metadata.conversation_id == @self_conversation_id
      assert Map.has_key?(metadata, :timestamp)
    end

    test "rejects legacy self topic without actor user id", %{socket: socket} do
      assert {:error, %{reason: "invalid_topic_format"}} =
               subscribe_and_join(socket, MessageChannel, "message:self")

      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.status == :error
      assert metadata.error_reason == :invalid_topic_format
    end

    test "rejects join when resolved self conversation is malformed", %{
      socket: socket,
      family: family,
      self_conversation: self_conversation
    } do
      Repo.delete!(self_conversation)

      _malformed_self_conversation =
        insert_conversation(Ecto.UUID.generate(), :self, family.id, [
          @valid_user_id,
          @second_user_id
        ])

      topic = "message:self:#{@valid_user_id}"

      assert {:error, %{reason: "invalid_self_conversation"}} =
               subscribe_and_join(socket, MessageChannel, topic)

      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.status == :error
      assert metadata.error_reason == :invalid_self_conversation
      assert metadata.conversation_type == "self"
    end

    test "successfully joins direct conversation channel", %{socket: socket} do
      topic = "message:direct:#{@direct_conversation_id}"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert metadata for successful join
      assert metadata.status == :success
      assert metadata.conversation_type == "direct"
      assert metadata.conversation_id == @direct_conversation_id
    end

    test "successfully joins group conversation channel", %{socket: socket} do
      topic = "message:group:#{@group_conversation_id}"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert metadata for successful join
      assert metadata.status == :success
      assert metadata.conversation_type == "group"
      assert metadata.conversation_id == @group_conversation_id
    end

    test "successfully joins family conversation channel", %{socket: socket} do
      topic = "message:family:#{@family_conversation_id}"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert metadata for successful join
      assert metadata.status == :success
      assert metadata.conversation_type == "family"
      assert metadata.conversation_id == @family_conversation_id
    end

    test "allows family conversation join via membership when not a participant",
         %{socket: socket, family: family, second_user: second_user} do
      membership_only_conversation =
        insert_conversation(Ecto.UUID.generate(), :family, family.id, [
          second_user.id
        ])

      topic = "message:family:#{membership_only_conversation.id}"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.status == :success
      assert metadata.conversation_type == "family"
      assert metadata.conversation_id == membership_only_conversation.id
    end

    test "conceals join when user is not participant in direct conversation", %{
      socket: socket,
      family: family
    } do
      outsider1 = insert_user_with_id(Ecto.UUID.generate(), family.id)
      outsider2 = insert_user_with_id(Ecto.UUID.generate(), family.id)

      conversation =
        insert_conversation(Ecto.UUID.generate(), :direct, family.id, [
          outsider1.id,
          outsider2.id
        ])

      topic = "message:direct:#{conversation.id}"

      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(socket, MessageChannel, topic)

      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.status == :error
      assert metadata.error_reason == :unauthorized
    end

    test "returns indistinguishable not_found for inaccessible existing, missing, wrong-type, and malformed topics",
         %{family: family} do
      outsider = insert_user_with_id(Ecto.UUID.generate(), family.id)
      token = token_for_user(outsider)
      {:ok, outsider_socket} = connect(UserSocket, %{"token" => token})

      existing_response =
        outsider_socket
        |> subscribe_and_join(
          MessageChannel,
          "message:direct:#{@direct_conversation_id}"
        )

      unknown_response =
        outsider_socket
        |> subscribe_and_join(
          MessageChannel,
          "message:direct:#{Ecto.UUID.generate()}"
        )

      wrong_type_response =
        outsider_socket
        |> subscribe_and_join(
          MessageChannel,
          "message:group:#{@direct_conversation_id}"
        )

      malformed_response =
        outsider_socket
        |> subscribe_and_join(MessageChannel, "message:direct:not-a-uuid")

      assert existing_response == {:error, %{reason: "not_found"}}
      assert unknown_response == {:error, %{reason: "not_found"}}
      assert wrong_type_response == {:error, %{reason: "not_found"}}
      assert malformed_response == {:error, %{reason: "not_found"}}
      assert existing_response == unknown_response
      assert existing_response == wrong_type_response
      assert existing_response == malformed_response
    end

    test "rejects join with invalid topic format", %{socket: socket} do
      # Invalid format: missing conversation ID
      topic = "message:invalid"

      assert {:error, %{reason: "invalid_topic_format"}} =
               join(socket, topic, %{})

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert metadata for failed join
      assert metadata.status == :error
      assert metadata.error_reason == :invalid_topic_format
    end

    test "rejects join with invalid conversation type", %{socket: socket} do
      # Invalid conversation type
      topic = "message:invalid:some-id"

      assert {:error, %{reason: "invalid_topic_format"}} =
               join(socket, topic, %{})

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert metadata for failed join
      assert metadata.status == :error
      assert metadata.error_reason == :invalid_topic_format
    end

    test "conceals malformed conversation id behind not_found", %{
      socket: socket
    } do
      topic = "message:direct:not-a-uuid"

      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(socket, MessageChannel, topic)

      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.status == :error
      assert metadata.error_reason == :invalid_conversation_id
    end

    # New tests for encryption-aware telemetry
    test "failed join telemetry does not contain sensitive encryption metadata",
         %{socket: socket} do
      # Test with invalid topic format
      topic = "message:invalid:some-id"

      assert {:error, %{reason: "invalid_topic_format"}} =
               join(socket, topic, %{})

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.status == :error
      refute Map.has_key?(metadata, :encryption_status)
      assert_no_sensitive_encryption_metadata(metadata)

      # Test with unauthorized access (using a socket without user_id)
      socket_without_auth = socket_without_user_id()
      topic = "message:direct:#{@direct_conversation_id}"

      assert {:error, %{reason: "unauthorized"}} =
               join(socket_without_auth, topic, %{})

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.status == :error
      refute Map.has_key?(metadata, :encryption_status)
      assert_no_sensitive_encryption_metadata(metadata)
    end

    test "successful join telemetry only includes encryption_status field", %{
      socket: socket
    } do
      # Test with direct conversation
      topic = "message:direct:#{@direct_conversation_id}"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.status == :success
      assert Map.has_key?(metadata, :encryption_status)
      assert metadata.encryption_status in ["enabled", "disabled"]
      assert_no_sensitive_encryption_metadata(metadata)

      # Test with self conversation
      topic = "message:self:#{@valid_user_id}"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.status == :success
      assert Map.has_key?(metadata, :encryption_status)
      assert metadata.encryption_status in ["enabled", "disabled"]
      assert_no_sensitive_encryption_metadata(metadata)
    end
  end

  describe "message broadcasting - type-aware format" do
    setup %{user_session: user_session} do
      {:ok, socket} =
        connect(UserSocket, %{"token" => user_session.access_token})

      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          MessageChannel,
          "message:direct:#{@direct_conversation_id}"
        )

      {:ok, %{socket: socket}}
    end

    test "broadcasts messages on direct conversation channel", %{socket: socket} do
      payload = %{"body" => "Hello from direct conversation!"}
      {_, metadata} = push_and_assert_broadcast(socket, :direct, payload)
      assert metadata.encryption_status == "disabled"
    end

    test "broadcasts encrypted messages on direct conversation channel", %{
      socket: socket
    } do
      encrypted_message = %{
        "body" => "encrypted_direct_message",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_USER_v1"
      }

      {_, metadata} =
        push_and_assert_broadcast(socket, :direct, encrypted_message)

      assert metadata.encryption_status == "enabled"
    end

    test "broadcast telemetry only includes encryption_status field", %{
      socket: socket
    } do
      encrypted_payload = %{
        "body" => "encrypted message",
        "encryption_flag" => true,
        "version_tag" => "v1.0.0",
        "key_id" => "KEY_USER_v1"
      }

      {_, encrypted_metadata} =
        push_and_assert_broadcast(socket, :direct, encrypted_payload)

      assert encrypted_metadata.encryption_status == "enabled"

      plain_payload = %{"body" => "plain text message"}

      {_, plain_metadata} =
        push_and_assert_broadcast(socket, :direct, plain_payload)

      assert plain_metadata.encryption_status == "disabled"
      assert plain_metadata.user_id == @valid_user_id
    end

    test "persists messages before broadcast", %{socket: socket} do
      payload = %{"body" => "persisted direct message"}
      push_and_assert_broadcast(socket, :direct, payload)

      persisted =
        Repo.get_by(Message,
          conversation_id: @direct_conversation_id,
          sender_id: @valid_user_id,
          content: "persisted direct message"
        )

      assert persisted
    end
  end

  # New test blocks for different conversation types
  describe "message broadcasting - self conversation" do
    setup %{user_session: user_session} do
      {:ok, socket} =
        connect(UserSocket, %{"token" => user_session.access_token})

      {:ok, _, socket} =
        subscribe_and_join(socket, MessageChannel, conversation_topic(:self))

      {:ok, %{socket: socket}}
    end

    @doc """
    Tests broadcasting a plain text message in a self conversation.

    This test verifies:
    1. The message is correctly broadcast with the expected payload
    2. Telemetry events are emitted with the correct metadata
    3. The conversation type is properly identified as "self"
    """
    test "broadcasts plain text messages in self conversation", %{
      socket: socket
    } do
      payload = %{"body" => "Note to self: Remember to buy milk"}
      push_and_assert_broadcast(socket, :self, payload)
    end

    @doc """
    Tests broadcasting an encrypted message in a self conversation.

    This test verifies:
    1. The message with encryption metadata is correctly broadcast
    2. Telemetry events include encryption_status but not sensitive encryption metadata
    3. The payload preserves all encryption-related fields
    """
    test "broadcasts encrypted messages in self conversation", %{socket: socket} do
      encrypted_message = %{
        "body" => "encrypted_self_note",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_USER_v1"
      }

      {_, metadata} =
        push_and_assert_broadcast(socket, :self, encrypted_message)

      assert metadata.encryption_status == "enabled"
    end
  end

  describe "message broadcasting - group conversation" do
    setup %{user_session: user_session} do
      {:ok, socket} =
        connect(UserSocket, %{"token" => user_session.access_token})

      {:ok, _, socket} =
        subscribe_and_join(socket, MessageChannel, conversation_topic(:group))

      {:ok, %{socket: socket}}
    end

    @doc """
    Tests broadcasting a plain text message in a group conversation.

    This test verifies:
    1. The message is correctly broadcast with the expected payload
    2. Telemetry events are emitted with the correct metadata
    3. The conversation type is properly identified as "group"
    """
    test "broadcasts plain text messages in group conversation", %{
      socket: socket
    } do
      payload = %{"body" => "Hello group members!"}
      push_and_assert_broadcast(socket, :group, payload)
    end

    @doc """
    Tests broadcasting an encrypted message in a group conversation.

    This test verifies:
    1. The message with encryption metadata is correctly broadcast
    2. Telemetry events include encryption_status but not sensitive encryption metadata
    3. The payload preserves all encryption-related fields
    """
    test "broadcasts encrypted messages in group conversation", %{
      socket: socket
    } do
      encrypted_message = %{
        "body" => "encrypted_group_message",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_GROUP_v1"
      }

      {_, metadata} =
        push_and_assert_broadcast(socket, :group, encrypted_message)

      assert metadata.encryption_status == "enabled"
    end
  end

  describe "message broadcasting - family conversation" do
    setup %{user_session: user_session} do
      {:ok, socket} =
        connect(UserSocket, %{"token" => user_session.access_token})

      {:ok, _, socket} =
        subscribe_and_join(socket, MessageChannel, conversation_topic(:family))

      {:ok, %{socket: socket}}
    end

    @doc """
    Tests broadcasting a plain text message in a family conversation.

    This test verifies:
    1. The message is correctly broadcast with the expected payload
    2. Telemetry events are emitted with the correct metadata
    3. The conversation type is properly identified as "family"
    """
    test "broadcasts plain text messages in family conversation", %{
      socket: socket
    } do
      payload = %{"body" => "Family announcement: Dinner at 7pm"}
      push_and_assert_broadcast(socket, :family, payload)
    end

    @doc """
    Tests broadcasting an encrypted message in a family conversation.

    This test verifies:
    1. The message with encryption metadata is correctly broadcast
    2. Telemetry events include encryption_status but not sensitive encryption metadata
    3. The payload preserves all encryption-related fields
    """
    test "broadcasts encrypted messages in family conversation", %{
      socket: socket
    } do
      encrypted_message = %{
        "body" => "encrypted_family_message",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_FAMILY_v1"
      }

      {_, metadata} =
        push_and_assert_broadcast(socket, :family, encrypted_message)

      assert metadata.encryption_status == "enabled"
    end
  end

  describe "message broadcasting - error cases and edge cases" do
    setup %{user_session: user_session} do
      {:ok, socket} =
        connect(UserSocket, %{"token" => user_session.access_token})

      topic = "message:direct:#{@direct_conversation_id}"
      {:ok, _, socket} = subscribe_and_join(socket, MessageChannel, topic)
      {:ok, %{socket: socket, topic: topic}}
    end

    test "rejects messages with empty body", %{socket: socket} do
      ref = push(socket, "new_msg", %{"body" => ""})

      assert_reply ref, :error, %{reason: "invalid_message"}
      refute_broadcast "new_msg", _
    end

    test "rejects oversized messages", %{socket: socket} do
      oversized_body = String.duplicate("a", Message.max_content_bytes() + 1)
      ref = push(socket, "new_msg", %{"body" => oversized_body})

      assert_reply ref, :error, %{reason: "message_too_large"}
      refute_broadcast "new_msg", _
    end

    test "rate limits burst message sends", %{socket: socket} do
      burst_limit = MessageRateLimiter.window_limit(:msg_device_burst) || 20

      Enum.each(1..burst_limit, fn index ->
        body = "burst-message-#{index}"
        push(socket, "new_msg", %{"body" => body})

        assert_broadcast "new_msg", %{
          "body" => ^body,
          "user_id" => @valid_user_id
        }
      end)

      ref = push(socket, "new_msg", %{"body" => "burst-over-limit"})

      assert_reply ref, :error, %{reason: "rate_limited", retry_in: retry_in}
      assert is_integer(retry_in)
      assert retry_in > 0
      refute_broadcast "new_msg", _
    end

    @doc """
    Tests handling of messages with missing body field.

    This test verifies:
    1. Messages without a body field are rejected
    2. The appropriate error response is returned
    3. No broadcast occurs
    """
    test "rejects messages with missing body field", %{socket: socket} do
      # Send message without body field
      ref = push(socket, "new_msg", %{})

      # Verify error response
      assert_reply ref, :error, %{reason: "invalid_message"}

      # Verify no broadcast occurred
      refute_broadcast "new_msg", _
    end

    test "returns explicit recovery_required when conversation security state must be recovered",
         %{socket: socket} do
      previous_adapter = Application.get_env(:famichat, :mls_adapter)
      previous_enforcement = Application.get_env(:famichat, :mls_enforcement)

      Application.put_env(:famichat, :mls_adapter, RecoveryGateAdapter)
      Application.put_env(:famichat, :mls_enforcement, true)

      on_exit(fn ->
        restore_env(:mls_adapter, previous_adapter)
        restore_env(:mls_enforcement, previous_enforcement)
      end)

      ref = push(socket, "new_msg", %{"body" => "requires recovery"})

      assert_reply ref, :error, %{
        reason: "recovery_required",
        action: "recover_conversation_security_state",
        recovery_reason: "missing_group_state"
      }

      refute_broadcast "new_msg", _
    end

    @doc """
    Tests handling of messages with invalid topic format.

    This test verifies:
    1. Messages sent to invalid topics are rejected
    2. The appropriate error response is returned
    """
    test "rejects messages with invalid topic format", %{user: user} do
      # Create a socket with an invalid topic format
      token = token_for_user(user)
      {:ok, socket} = connect(UserSocket, %{"token" => token})

      # Try to join an invalid topic - this should return an error
      assert {:error, %{reason: "invalid_topic_format"}} =
               subscribe_and_join(
                 socket,
                 MessageChannel,
                 "message:invalid:format"
               )
    end

    @doc """
    Tests handling of encrypted messages with all required metadata.

    This test verifies:
    1. Encrypted messages with all required metadata are broadcast correctly
    2. The encryption metadata is preserved in the broadcast
    3. Telemetry events include encryption_status but not sensitive encryption metadata
    """
    test "broadcasts encrypted messages with complete metadata", %{
      socket: socket
    } do
      # Prepare encrypted message with all required metadata
      encrypted_message = %{
        "body" => "encrypted_message",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_USER_v1"
      }

      # Send the message
      push(socket, "new_msg", encrypted_message)

      # Verify the message is broadcast with all encryption metadata preserved
      assert_broadcast "new_msg", %{
        "body" => "encrypted_message",
        "user_id" => @valid_user_id,
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_USER_v1"
      }

      # Verify broadcast telemetry
      assert_receive {:broadcast_telemetry_event,
                      [:famichat, :message_channel, :broadcast], _measurements,
                      metadata},
                     @telemetry_timeout

      # Assert encryption status in telemetry metadata
      assert metadata.encryption_status == "enabled"

      # Assert sensitive encryption metadata is NOT present in telemetry
      refute Map.has_key?(metadata, :key_id)
      refute Map.has_key?(metadata, :encryption_flag)
      refute Map.has_key?(metadata, :version_tag)
    end
  end

  describe "integration tests - client subscription and event reception" do
    @doc """
    Tests the complete flow of a client subscribing to a channel and receiving messages.

    This integration test verifies:
    1. A client can successfully connect to the socket with a valid token
    2. The client can subscribe to a channel with a valid topic
    3. The client receives broadcast messages sent to that channel
    4. The client can send messages that are broadcast to all subscribers
    """
    test "client can subscribe to channel and receive messages", %{
      user_session: user_session,
      second_user: second_user
    } do
      # Create two clients
      token1 = user_session.access_token
      token2 = token_for_user(second_user)

      # Connect first client
      {:ok, socket1} = connect(UserSocket, %{"token" => token1})

      # Connect second client
      {:ok, socket2} = connect(UserSocket, %{"token" => token2})

      # Both clients join the same direct conversation channel
      topic = "message:direct:#{@direct_conversation_id}"
      {:ok, _, socket1} = subscribe_and_join(socket1, MessageChannel, topic)
      {:ok, _, socket2} = subscribe_and_join(socket2, MessageChannel, topic)

      # First client sends a message
      message_body = "Hello from client 1!"
      push(socket1, "new_msg", %{"body" => message_body})

      # Verify second client receives the message
      assert_push "new_msg", %{
        "body" => ^message_body,
        "user_id" => @valid_user_id
      }

      # Second client sends a message
      response_body = "Hello back from client 2!"
      push(socket2, "new_msg", %{"body" => response_body})

      # Verify first client receives the message
      assert_push "new_msg", %{
        "body" => ^response_body,
        "user_id" => @second_user_id
      }
    end

    @doc """
    Tests the complete flow of a client subscribing to a channel and receiving encrypted messages.

    This integration test verifies:
    1. A client can successfully connect to the socket with a valid token
    2. The client can subscribe to a channel with a valid topic
    3. The client receives encrypted broadcast messages with all encryption metadata preserved
    4. The client can send encrypted messages that are broadcast to all subscribers
    """
    test "client can subscribe to channel and receive encrypted messages", %{
      user_session: user_session,
      second_user: second_user
    } do
      # Create two clients
      token1 = user_session.access_token
      token2 = token_for_user(second_user)

      # Connect first client
      {:ok, socket1} = connect(UserSocket, %{"token" => token1})

      # Connect second client
      {:ok, socket2} = connect(UserSocket, %{"token" => token2})

      # Both clients join the same direct conversation channel
      topic = "message:direct:#{@direct_conversation_id}"
      {:ok, _, socket1} = subscribe_and_join(socket1, MessageChannel, topic)
      {:ok, _, socket2} = subscribe_and_join(socket2, MessageChannel, topic)

      # First client sends an encrypted message
      encrypted_message = %{
        "body" => "encrypted_content_from_client_1",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_DIRECT_v1"
      }

      push(socket1, "new_msg", encrypted_message)

      # Verify second client receives the encrypted message with all metadata
      assert_push "new_msg", %{
        "body" => "encrypted_content_from_client_1",
        "user_id" => @valid_user_id,
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_DIRECT_v1"
      }

      # Second client sends an encrypted message
      encrypted_response = %{
        "body" => "encrypted_content_from_client_2",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_DIRECT_v1"
      }

      push(socket2, "new_msg", encrypted_response)

      # Verify first client receives the encrypted message with all metadata
      assert_push "new_msg", %{
        "body" => "encrypted_content_from_client_2",
        "user_id" => @second_user_id,
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_DIRECT_v1"
      }
    end

    @doc """
    Tests the behavior when a client attempts to join a channel they are not authorized for.

    This integration test verifies:
    1. A client can successfully connect to the socket with a valid token
    2. The client is rejected when trying to join a channel they don't have access to
    3. The error response includes an appropriate reason
    """
    test "client is rejected when joining another user's self topic",
         %{
           user_session: user_session
         } do
      # Create a client
      token = user_session.access_token

      # Connect client
      {:ok, socket} = connect(UserSocket, %{"token" => token})

      topic = "message:self:#{Ecto.UUID.generate()}"

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, MessageChannel, topic)

      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.status == :error
      assert metadata.error_reason == :unauthorized
    end

    test "client receives not_found when joining unauthorized direct channel",
         %{
           family: family,
           second_user: second_user,
           user_session: user_session
         } do
      # Create a client
      token = user_session.access_token

      # Connect client
      {:ok, socket} = connect(UserSocket, %{"token" => token})

      other_direct_conversation =
        insert_conversation(Ecto.UUID.generate(), :direct, family.id, [
          second_user.id,
          @third_user_id
        ])

      topic = "message:direct:#{other_direct_conversation.id}"

      # This should be rejected
      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(socket, MessageChannel, topic)

      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.status == :error
      assert metadata.error_reason == :unauthorized
      assert metadata.conversation_type == "direct"
      assert metadata.conversation_id == other_direct_conversation.id
    end

    @doc """
    Tests the behavior when a client disconnects and reconnects to a channel.

    This integration test verifies:
    1. A client can successfully connect, disconnect, and reconnect
    2. After reconnecting, the client can still send and receive messages
    """
    test "client can disconnect and reconnect to channel", %{
      user_session: user_session
    } do
      # Create a client
      token = user_session.access_token

      # Connect client
      {:ok, socket} = connect(UserSocket, %{"token" => token})

      # Join a channel
      topic = "message:direct:#{@direct_conversation_id}"
      {:ok, _, socket} = subscribe_and_join(socket, MessageChannel, topic)

      # Send a message
      push(socket, "new_msg", %{"body" => "Hello before disconnect"})

      # Verify message was broadcast
      assert_broadcast "new_msg", %{
        "body" => "Hello before disconnect",
        "user_id" => @valid_user_id
      }

      # Disconnect by leaving the channel
      Process.unlink(socket.channel_pid)
      ref = leave(socket)
      assert_reply ref, :ok

      # Reconnect with a new socket
      {:ok, new_socket} = connect(UserSocket, %{"token" => token})

      {:ok, _, new_socket} =
        subscribe_and_join(new_socket, MessageChannel, topic)

      # Send a message after reconnecting
      push(new_socket, "new_msg", %{"body" => "Hello after reconnect"})

      # Verify message was broadcast
      assert_broadcast "new_msg", %{
        "body" => "Hello after reconnect",
        "user_id" => @valid_user_id
      }
    end
  end

  describe "enhanced broadcast logging and client acknowledgment" do
    setup %{user_session: user_session} do
      # Start a telemetry handler for ack events
      test_pid = self()
      handler_id = "message-ack-test-#{:erlang.unique_integer()}"

      Logger.debug("Setting up ack telemetry handler with id: #{handler_id}")

      # Handler for acknowledgment events
      :ok =
        :telemetry.attach(
          handler_id,
          [:famichat, :message_channel, :ack],
          fn event_name, measurements, metadata, _ ->
            Logger.debug("""
            Acknowledgment telemetry event received in test:
            - event_name: #{inspect(event_name)}
            - measurements: #{inspect(measurements)}
            - metadata: #{inspect(metadata)}
            """)

            send(
              test_pid,
              {:ack_telemetry_event, event_name, measurements, metadata}
            )
          end,
          nil
        )

      # Setup socket and join channel
      {:ok, socket} =
        connect(UserSocket, %{"token" => user_session.access_token})

      topic = "message:direct:#{@direct_conversation_id}"
      {:ok, _, socket} = subscribe_and_join(socket, MessageChannel, topic)

      on_exit(fn ->
        Logger.debug("Detaching ack telemetry handler")
        :telemetry.detach(handler_id)
      end)

      {:ok, %{socket: socket, handler_id: handler_id}}
    end

    @doc """
    Tests the enhanced broadcast logging functionality.

    This test verifies that:
    1. The logging is enhanced with detailed information
    2. Telemetry events include message size
    3. Log messages can be captured and verified
    """
    test "broadcasts include enhanced logging with message size and metadata",
         %{
           socket: socket
         } do
      import ExUnit.CaptureLog

      # Capture logs to verify the enhanced logging
      logs =
        capture_log(fn ->
          # Send a message with a known size
          # 100 byte message
          message_body = String.duplicate("a", 100)
          push(socket, "new_msg", %{"body" => message_body})

          # Wait for telemetry to be emitted
          assert_receive {:broadcast_telemetry_event,
                          [:famichat, :message_channel, :broadcast],
                          measurements, metadata},
                         @telemetry_timeout

          # Verify message size in telemetry
          assert metadata.message_size == 100
          assert Map.has_key?(measurements, :duration_ms)
        end)

      # Verify that the enhanced log contains all required fields
      assert logs =~ "[MessageChannel] Broadcast event:"
      assert logs =~ "conversation_type=direct"
      assert logs =~ "conversation_id=#{@direct_conversation_id}"
      assert logs =~ "user_id=#{@valid_user_id}"
      assert logs =~ "encryption_status=disabled"
      assert logs =~ "message_size=100"
      assert logs =~ "duration_ms="
    end

    @doc """
    Tests the client acknowledgment mechanism.

    This test verifies that:
    1. The server handles message_ack events correctly
    2. Telemetry events are emitted for acknowledgments
    3. The acknowledgment includes the correct metadata
    """
    test "client acknowledgments are received and logged", %{socket: socket} do
      import ExUnit.CaptureLog

      # Capture logs to verify the acknowledgment logging
      logs =
        capture_log(fn ->
          # Send a message acknowledgment
          message_id = "test-message-123"
          push(socket, "message_ack", %{"message_id" => message_id})

          # Wait for telemetry to be emitted
          assert_receive {:ack_telemetry_event,
                          [:famichat, :message_channel, :ack], measurements,
                          metadata},
                         @telemetry_timeout

          # Verify metadata in telemetry
          assert metadata.message_id == message_id
          assert metadata.user_id == @valid_user_id
          assert metadata.conversation_type == "direct"
          assert metadata.conversation_id == @direct_conversation_id
          assert Map.has_key?(metadata, :timestamp)
          assert Map.has_key?(measurements, :duration_ms)
        end)

      # Verify that the acknowledgment log contains all required fields
      assert logs =~ "[MessageChannel] Message acknowledgment:"
      assert logs =~ "conversation_type=direct"
      assert logs =~ "conversation_id=#{@direct_conversation_id}"
      assert logs =~ "user_id=#{@valid_user_id}"
      assert logs =~ "message_id=test-message-123"
    end

    test "acknowledgment telemetry captures non-direct conversations", %{
      socket: socket
    } do
      {:ok, _, group_socket} =
        subscribe_and_join(socket, MessageChannel, conversation_topic(:group))

      push(group_socket, "message_ack", %{"message_id" => "group-msg"})

      assert_receive {:ack_telemetry_event, [:famichat, :message_channel, :ack],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.conversation_type == "group"
      assert metadata.conversation_id == @group_conversation_id
      assert metadata.message_id == "group-msg"
    end

    test "acknowledgment telemetry defaults message_id when missing", %{
      socket: socket
    } do
      push(socket, "message_ack", %{})

      assert_receive {:ack_telemetry_event, [:famichat, :message_channel, :ack],
                      _measurements, metadata},
                     @telemetry_timeout

      assert metadata.message_id == "unknown"
    end

    @doc """
    Tests the end-to-end flow where a client receives a message and sends an acknowledgment.

    This test verifies that:
    1. A message can be broadcast to a client
    2. The client can acknowledge receipt of the message
    3. The server logs both the broadcast and the acknowledgment
    """
    test "end-to-end message delivery with acknowledgment logging", %{
      socket: socket,
      second_user: second_user
    } do
      # Create a second client
      token2 = token_for_user(second_user)
      {:ok, socket2} = connect(UserSocket, %{"token" => token2})
      topic = "message:direct:#{@direct_conversation_id}"
      {:ok, _, socket2} = subscribe_and_join(socket2, MessageChannel, topic)

      # First client sends a message with a message ID
      message_id = "unique-message-#{:rand.uniform(1000)}"

      push(socket, "new_msg", %{
        "body" => "Message requiring acknowledgment",
        "message_id" => message_id
      })

      # Verify message was broadcast to channel
      assert_broadcast "new_msg", %{
        "body" => "Message requiring acknowledgment",
        "user_id" => @valid_user_id
      }

      # Manually send an acknowledgment from the second client
      push(socket2, "message_ack", %{"message_id" => message_id})

      # Verify telemetry event for the acknowledgment
      assert_receive {:ack_telemetry_event, [:famichat, :message_channel, :ack],
                      _measurements, metadata},
                     @telemetry_timeout

      # Verify metadata in telemetry
      assert metadata.message_id == message_id
      # The acknowledging user
      assert metadata.user_id == @second_user_id
      assert metadata.conversation_type == "direct"
      assert metadata.conversation_id == @direct_conversation_id
    end
  end

  defp push_and_assert_broadcast(socket, type, payload, opts \\ []) do
    user_id = Keyword.get(opts, :user_id, @valid_user_id)
    device_id = Keyword.get(opts, :device_id, socket.assigns.device_id)

    expected_payload =
      payload
      |> Map.take(["body"] ++ @encryption_metadata_fields)
      |> Map.put("user_id", user_id)
      |> Map.put("device_id", device_id)

    push(socket, "new_msg", payload)
    assert_broadcast("new_msg", ^expected_payload)

    encryption_status =
      if Map.get(payload, "encryption_flag"), do: "enabled", else: "disabled"

    message_size =
      case Map.get(payload, "body") do
        body when is_binary(body) -> byte_size(body)
        _ -> 0
      end

    {measurements, metadata} =
      assert_broadcast_telemetry(
        type,
        conversation_id(type),
        user_id: user_id,
        encryption_status: encryption_status,
        message_size: message_size
      )

    {measurements, metadata}
  end

  defp assert_broadcast_telemetry(type, conversation_id, opts) do
    user_id = Keyword.get(opts, :user_id, @valid_user_id)
    encryption_status = Keyword.get(opts, :encryption_status, "disabled")
    message_size = Keyword.get(opts, :message_size, 0)

    assert_receive {:broadcast_telemetry_event,
                    [:famichat, :message_channel, :broadcast], measurements,
                    metadata},
                   @telemetry_timeout

    assert Map.has_key?(measurements, :duration_ms)
    assert Map.has_key?(measurements, :start_time)

    assert metadata.user_id == user_id
    assert metadata.conversation_type == type_to_string(type)
    assert metadata.conversation_id == conversation_id
    assert metadata.encryption_status == encryption_status
    assert metadata.message_size == message_size
    assert Map.has_key?(metadata, :timestamp)

    assert_no_sensitive_encryption_metadata(metadata)

    {measurements, metadata}
  end

  defp assert_no_sensitive_encryption_metadata(metadata) do
    Enum.each(@encryption_metadata_atom_fields, fn field ->
      refute Map.has_key?(metadata, field)
    end)

    Enum.each(@encryption_metadata_fields, fn field ->
      refute Map.has_key?(metadata, field)
    end)
  end

  defp conversation_topic(type) do
    case type do
      :self -> "message:self:#{@valid_user_id}"
      :direct -> "message:direct:#{@direct_conversation_id}"
      :group -> "message:group:#{@group_conversation_id}"
      :family -> "message:family:#{@family_conversation_id}"
    end
  end

  defp conversation_id(:self), do: @self_conversation_id
  defp conversation_id(:direct), do: @direct_conversation_id
  defp conversation_id(:group), do: @group_conversation_id
  defp conversation_id(:family), do: @family_conversation_id

  defp type_to_string(type) when is_atom(type), do: Atom.to_string(type)

  defp socket_without_user_id do
    socket(UserSocket, nil, %{})
  end

  defp insert_user_with_id(id, family_id, attrs \\ %{}) do
    defaults = %{
      username: ChatFixtures.unique_user_username(),
      email: ChatFixtures.unique_user_email(),
      role: :member,
      family_id: family_id
    }

    user_attrs =
      defaults
      |> Map.merge(Map.take(attrs, [:username, :email, :role, :family_id]))

    user =
      %User{id: id}
      |> User.changeset(user_attrs)
      |> Repo.insert!()

    %HouseholdMembership{}
    |> HouseholdMembership.changeset(%{
      user_id: user.id,
      family_id: family_id,
      role: Map.get(user_attrs, :role, :member)
    })
    |> Repo.insert!()

    user
  end

  defp insert_conversation(id, type, family_id, participant_ids, attrs \\ %{}) do
    metadata = Map.get(attrs, :metadata, default_metadata(type))

    conversation_attrs =
      %{
        family_id: family_id,
        conversation_type: type,
        metadata: metadata
      }
      |> maybe_put_direct_key(type, family_id, participant_ids)
      |> Map.merge(Map.take(attrs, [:direct_key]))

    conversation =
      %Conversation{id: id}
      |> Conversation.create_changeset(conversation_attrs)
      |> Repo.insert!()

    now = DateTime.utc_now(:microsecond)

    participant_rows =
      Enum.map(participant_ids, fn participant_id ->
        %{
          conversation_id: conversation.id,
          user_id: participant_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    if participant_rows != [] do
      Repo.insert_all(ConversationParticipant, participant_rows)
    end

    conversation
  end

  defp issue_access_token(user, opts \\ []) do
    device_id = Keyword.get(opts, :device_id, Ecto.UUID.generate())
    user_agent = Keyword.get(opts, :user_agent, "test-agent")
    ip = Keyword.get(opts, :ip, "127.0.0.1")
    trust? = Keyword.get(opts, :trust?, true)
    now = DateTime.utc_now(:microsecond)

    trusted_until =
      if trust? do
        DateTime.add(now, 30 * 24 * 60 * 60, :second)
      else
        nil
      end

    attrs = %{
      user_id: user.id,
      device_id: device_id,
      user_agent: user_agent,
      ip: ip,
      trusted_until: trusted_until,
      last_active_at: now,
      refresh_token_hash: Keyword.get(opts, :refresh_token_hash),
      previous_token_hash: Keyword.get(opts, :previous_token_hash),
      revoked_at: Keyword.get(opts, :revoked_at)
    }

    {:ok, device} =
      %UserDevice{}
      |> UserDevice.changeset(attrs)
      |> Repo.insert()

    token =
      Phoenix.Token.sign(@endpoint, @access_salt, %{
        "user_id" => user.id,
        "device_id" => device.device_id
      })

    %{access_token: token, device: device}
  end

  defp token_for_user(user, opts \\ []) do
    issue_access_token(user, opts).access_token
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)

  defp maybe_put_direct_key(attrs, :direct, family_id, [user1_id, user2_id | _]) do
    direct_key =
      Conversation.compute_direct_key(user1_id, user2_id, family_id)

    Map.put_new(attrs, :direct_key, direct_key)
  end

  defp maybe_put_direct_key(attrs, _type, _family_id, _participant_ids),
    do: attrs

  defp default_metadata(:group), do: %{"name" => "Test Group Conversation"}
  defp default_metadata(_), do: %{}
end
