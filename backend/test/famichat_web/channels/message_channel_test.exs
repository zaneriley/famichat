defmodule FamichatWeb.MessageChannelTest do
  use FamichatWeb.ChannelCase
  import Phoenix.ChannelTest
  require Logger

  alias FamichatWeb.MessageChannel
  alias FamichatWeb.UserSocket

  @endpoint FamichatWeb.Endpoint
  @salt "user_auth"
  @valid_user_id "123e4567-e89b-12d3-a456-426614174000"
  @telemetry_timeout 1000

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

    {:ok, %{handler_id: handler_id, broadcast_handler_id: broadcast_handler_id}}
  end

  describe "socket connection" do
    test "returns error when token is invalid" do
      invalid_token = "invalid_token"

      assert {:error, %{reason: "invalid_token"}} =
               connect(UserSocket, %{"token" => invalid_token})
    end

    test "successfully connects with valid token" do
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      assert {:ok, socket} = connect(UserSocket, %{"token" => token})
      assert socket.assigns.user_id == @valid_user_id
    end
  end

  describe "channel join - type-aware format" do
    setup do
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      {:ok, %{socket: socket}}
    end

    test "successfully joins self conversation channel", %{socket: socket} do
      # Use the user_id as the conversation ID for self conversations
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
      assert metadata.conversation_id == @valid_user_id
      assert Map.has_key?(metadata, :timestamp)
    end

    test "successfully joins direct conversation channel", %{socket: socket} do
      topic = "message:direct:some-conversation-id"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert metadata for successful join
      assert metadata.status == :success
      assert metadata.conversation_type == "direct"
      assert metadata.conversation_id == "some-conversation-id"
    end

    test "successfully joins group conversation channel", %{socket: socket} do
      topic = "message:group:group-conversation-id"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert metadata for successful join
      assert metadata.status == :success
      assert metadata.conversation_type == "group"
      assert metadata.conversation_id == "group-conversation-id"
    end

    test "successfully joins family conversation channel", %{socket: socket} do
      topic = "message:family:family-id"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert metadata for successful join
      assert metadata.status == :success
      assert metadata.conversation_type == "family"
      assert metadata.conversation_id == "family-id"
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

      # Assert sensitive encryption metadata is NOT present
      refute Map.has_key?(metadata, :key_id)
      refute Map.has_key?(metadata, :encryption_flag)
      refute Map.has_key?(metadata, :encryption_version)

      # Test with unauthorized access (using a socket without user_id)
      socket_without_auth = socket_without_user_id()

      assert {:error, %{reason: "unauthorized"}} =
               join(socket_without_auth, "message:direct:123", %{})

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert sensitive encryption metadata is NOT present
      refute Map.has_key?(metadata, :key_id)
      refute Map.has_key?(metadata, :encryption_flag)
      refute Map.has_key?(metadata, :encryption_version)
    end

    test "successful join telemetry only includes encryption_status field", %{
      socket: socket
    } do
      # Test with direct conversation
      topic = "message:direct:conversation-123"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert only encryption_status is present, not other encryption metadata
      assert Map.has_key?(metadata, :encryption_status)
      assert metadata.encryption_status in ["enabled", "disabled"]

      # Assert sensitive encryption metadata is NOT present
      refute Map.has_key?(metadata, :key_id)
      refute Map.has_key?(metadata, :encryption_flag)
      refute Map.has_key?(metadata, :encryption_version)

      # Test with self conversation
      topic = "message:self:#{@valid_user_id}"

      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, MessageChannel, topic)

      # Verify telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join],
                      _measurements, metadata},
                     @telemetry_timeout

      # Assert only encryption_status is present, not other encryption metadata
      assert Map.has_key?(metadata, :encryption_status)
      assert metadata.encryption_status in ["enabled", "disabled"]

      # Assert sensitive encryption metadata is NOT present
      refute Map.has_key?(metadata, :key_id)
      refute Map.has_key?(metadata, :encryption_flag)
      refute Map.has_key?(metadata, :encryption_version)
    end
  end

  describe "message broadcasting - type-aware format" do
    setup do
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      {:ok, socket} = connect(UserSocket, %{"token" => token})

      {:ok, _, socket} =
        subscribe_and_join(
          socket,
          MessageChannel,
          "message:direct:conversation-123"
        )

      {:ok, %{socket: socket}}
    end

    test "broadcasts messages on direct conversation channel", %{socket: socket} do
      message_body = "Hello from direct conversation!"
      push(socket, "new_msg", %{"body" => message_body})

      assert_broadcast "new_msg", %{
        "body" => ^message_body,
        "user_id" => @valid_user_id
      }

      # Verify broadcast telemetry
      assert_receive {:broadcast_telemetry_event,
                      [:famichat, :message_channel, :broadcast], _measurements,
                      metadata},
                     @telemetry_timeout

      # Assert metadata
      assert metadata.user_id == @valid_user_id
      assert metadata.conversation_type == "direct"
      assert metadata.conversation_id == "conversation-123"
      assert metadata.encryption_status == "disabled"
      assert Map.has_key?(metadata, :timestamp)
      assert Map.has_key?(metadata, :message_size)
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

      push(socket, "new_msg", encrypted_message)

      assert_broadcast "new_msg", %{
        "body" => "encrypted_direct_message",
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

      # Assert encryption status in metadata
      assert metadata.encryption_status == "enabled"
    end

    # New test for encryption-aware telemetry in broadcasts
    test "broadcast telemetry only includes encryption_status field", %{
      socket: socket
    } do
      # Test with encrypted message
      encrypted_payload = %{
        "body" => "encrypted message",
        "encryption_flag" => true,
        "version_tag" => "v1.0.0",
        "key_id" => "KEY_USER_v1"
      }

      push(socket, "new_msg", encrypted_payload)

      # Verify telemetry event
      assert_receive {:broadcast_telemetry_event,
                      [:famichat, :message_channel, :broadcast], _measurements,
                      metadata},
                     @telemetry_timeout

      # Assert only encryption_status is present, not other encryption metadata
      assert Map.has_key?(metadata, :encryption_status)
      assert metadata.encryption_status == "enabled"

      # Assert sensitive encryption metadata is NOT present
      refute Map.has_key?(metadata, :key_id)
      refute Map.has_key?(metadata, :encryption_flag)
      refute Map.has_key?(metadata, :version_tag)

      # Test with plain text message
      plain_payload = %{"body" => "plain text message"}

      push(socket, "new_msg", plain_payload)

      # Verify telemetry event
      assert_receive {:broadcast_telemetry_event,
                      [:famichat, :message_channel, :broadcast], _measurements,
                      metadata},
                     @telemetry_timeout

      # Assert only encryption_status is present, not other encryption metadata
      assert Map.has_key?(metadata, :encryption_status)
      assert metadata.encryption_status == "disabled"

      # Assert sensitive encryption metadata is NOT present
      refute Map.has_key?(metadata, :key_id)
      refute Map.has_key?(metadata, :encryption_flag)
      refute Map.has_key?(metadata, :version_tag)
    end
  end

  # New test blocks for different conversation types
  describe "message broadcasting - self conversation" do
    setup do
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      topic = "message:self:#{@valid_user_id}"
      {:ok, _, socket} = subscribe_and_join(socket, MessageChannel, topic)
      {:ok, %{socket: socket, topic: topic}}
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
      # Prepare test message
      message_body = "Note to self: Remember to buy milk"

      # Send the message
      push(socket, "new_msg", %{"body" => message_body})

      # Verify the message is broadcast with correct payload
      assert_broadcast "new_msg", %{
        "body" => ^message_body,
        "user_id" => @valid_user_id
      }

      # Verify broadcast telemetry
      assert_receive {:broadcast_telemetry_event,
                      [:famichat, :message_channel, :broadcast], measurements,
                      metadata},
                     @telemetry_timeout

      # Assert telemetry measurements
      assert is_map(measurements)
      assert Map.has_key?(measurements, :duration_ms)
      assert Map.has_key?(measurements, :start_time)

      # Assert telemetry metadata
      assert metadata.user_id == @valid_user_id
      assert metadata.conversation_type == "self"
      assert metadata.conversation_id == @valid_user_id
      assert metadata.encryption_status == "disabled"
      assert Map.has_key?(metadata, :timestamp)
      assert Map.has_key?(metadata, :message_size)
    end

    @doc """
    Tests broadcasting an encrypted message in a self conversation.

    This test verifies:
    1. The message with encryption metadata is correctly broadcast
    2. Telemetry events include encryption_status but not sensitive encryption metadata
    3. The payload preserves all encryption-related fields
    """
    test "broadcasts encrypted messages in self conversation", %{socket: socket} do
      # Prepare encrypted message
      encrypted_message = %{
        "body" => "encrypted_self_note",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_USER_v1"
      }

      # Send the message
      push(socket, "new_msg", encrypted_message)

      # Verify the message is broadcast with all encryption metadata preserved
      assert_broadcast "new_msg", %{
        "body" => "encrypted_self_note",
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

  describe "message broadcasting - group conversation" do
    setup do
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      topic = "message:group:group-123"
      {:ok, _, socket} = subscribe_and_join(socket, MessageChannel, topic)
      {:ok, %{socket: socket, topic: topic}}
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
      # Prepare test message
      message_body = "Hello group members!"

      # Send the message
      push(socket, "new_msg", %{"body" => message_body})

      # Verify the message is broadcast with correct payload
      assert_broadcast "new_msg", %{
        "body" => ^message_body,
        "user_id" => @valid_user_id
      }

      # Verify broadcast telemetry
      assert_receive {:broadcast_telemetry_event,
                      [:famichat, :message_channel, :broadcast], measurements,
                      metadata},
                     @telemetry_timeout

      # Assert telemetry measurements
      assert is_map(measurements)
      assert Map.has_key?(measurements, :duration_ms)
      assert Map.has_key?(measurements, :start_time)

      # Assert telemetry metadata
      assert metadata.user_id == @valid_user_id
      assert metadata.conversation_type == "group"
      assert metadata.conversation_id == "group-123"
      assert metadata.encryption_status == "disabled"
      assert Map.has_key?(metadata, :timestamp)
      assert Map.has_key?(metadata, :message_size)
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
      # Prepare encrypted message
      encrypted_message = %{
        "body" => "encrypted_group_message",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_GROUP_v1"
      }

      # Send the message
      push(socket, "new_msg", encrypted_message)

      # Verify the message is broadcast with all encryption metadata preserved
      assert_broadcast "new_msg", %{
        "body" => "encrypted_group_message",
        "user_id" => @valid_user_id,
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_GROUP_v1"
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

  describe "message broadcasting - family conversation" do
    setup do
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      topic = "message:family:family-123"
      {:ok, _, socket} = subscribe_and_join(socket, MessageChannel, topic)
      {:ok, %{socket: socket, topic: topic}}
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
      # Prepare test message
      message_body = "Family announcement: Dinner at 7pm"

      # Send the message
      push(socket, "new_msg", %{"body" => message_body})

      # Verify the message is broadcast with correct payload
      assert_broadcast "new_msg", %{
        "body" => ^message_body,
        "user_id" => @valid_user_id
      }

      # Verify broadcast telemetry
      assert_receive {:broadcast_telemetry_event,
                      [:famichat, :message_channel, :broadcast], measurements,
                      metadata},
                     @telemetry_timeout

      # Assert telemetry measurements
      assert is_map(measurements)
      assert Map.has_key?(measurements, :duration_ms)
      assert Map.has_key?(measurements, :start_time)

      # Assert telemetry metadata
      assert metadata.user_id == @valid_user_id
      assert metadata.conversation_type == "family"
      assert metadata.conversation_id == "family-123"
      assert metadata.encryption_status == "disabled"
      assert Map.has_key?(metadata, :timestamp)
      assert Map.has_key?(metadata, :message_size)
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
      # Prepare encrypted message
      encrypted_message = %{
        "body" => "encrypted_family_message",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_FAMILY_v1"
      }

      # Send the message
      push(socket, "new_msg", encrypted_message)

      # Verify the message is broadcast with all encryption metadata preserved
      assert_broadcast "new_msg", %{
        "body" => "encrypted_family_message",
        "user_id" => @valid_user_id,
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_FAMILY_v1"
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

  describe "message broadcasting - error cases and edge cases" do
    setup do
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      topic = "message:direct:conversation-123"
      {:ok, _, socket} = subscribe_and_join(socket, MessageChannel, topic)
      {:ok, %{socket: socket, topic: topic}}
    end

    @doc """
    Tests handling of empty message bodies.

    This test verifies:
    1. Empty message bodies are still broadcast (current implementation)
    2. The message is broadcast with the correct payload
    3. Telemetry events are emitted with the correct metadata
    """
    test "handles messages with empty body", %{socket: socket} do
      # Send message with empty body
      ref = push(socket, "new_msg", %{"body" => ""})

      # Verify the message is broadcast
      assert_broadcast "new_msg", %{
        "body" => "",
        "user_id" => @valid_user_id
      }

      # Verify no error response
      refute_reply ref, :error, _

      # Verify broadcast telemetry
      assert_receive {:broadcast_telemetry_event,
                      [:famichat, :message_channel, :broadcast], _measurements,
                      metadata},
                     @telemetry_timeout

      # Assert telemetry metadata
      assert metadata.user_id == @valid_user_id
      assert metadata.conversation_type == "direct"
      assert metadata.conversation_id == "conversation-123"
      assert metadata.encryption_status == "disabled"
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

    @doc """
    Tests handling of messages with invalid topic format.

    This test verifies:
    1. Messages sent to invalid topics are rejected
    2. The appropriate error response is returned
    """
    test "rejects messages with invalid topic format" do
      # Create a socket with an invalid topic format
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
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
    test "client can subscribe to channel and receive messages" do
      # Create two clients
      token1 = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      token2 = Phoenix.Token.sign(@endpoint, @salt, "user-456")

      # Connect first client
      {:ok, socket1} = connect(UserSocket, %{"token" => token1})

      # Connect second client
      {:ok, socket2} = connect(UserSocket, %{"token" => token2})

      # Both clients join the same direct conversation channel
      topic = "message:direct:conversation-123"
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
        "user_id" => "user-456"
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
    test "client can subscribe to channel and receive encrypted messages" do
      # Create two clients
      token1 = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      token2 = Phoenix.Token.sign(@endpoint, @salt, "user-456")

      # Connect first client
      {:ok, socket1} = connect(UserSocket, %{"token" => token1})

      # Connect second client
      {:ok, socket2} = connect(UserSocket, %{"token" => token2})

      # Both clients join the same direct conversation channel
      topic = "message:direct:conversation-123"
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
        "user_id" => "user-456",
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
    test "client is rejected when joining unauthorized channel" do
      # Create a client
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)

      # Connect client
      {:ok, socket} = connect(UserSocket, %{"token" => token})

      # Try to join a self conversation for a different user
      topic = "message:self:different-user-id"

      # This should be rejected
      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, MessageChannel, topic)
    end

    @doc """
    Tests the behavior when a client disconnects and reconnects to a channel.

    This integration test verifies:
    1. A client can successfully connect, disconnect, and reconnect
    2. After reconnecting, the client can still send and receive messages
    """
    test "client can disconnect and reconnect to channel" do
      # Create a client
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)

      # Connect client
      {:ok, socket} = connect(UserSocket, %{"token" => token})

      # Join a channel
      topic = "message:direct:conversation-123"
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

  defp socket_without_user_id do
    socket(UserSocket, nil, %{})
  end
end
