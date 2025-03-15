defmodule Famichat.Messages.DecryptionTest do
  use FamichatWeb.ConnCase, async: true
  import Famichat.ChatFixtures
  alias Famichat.Chat.MessageService
  alias Famichat.Chat.Message
  alias Famichat.Repo
  require Logger

  @telemetry_timeout 5000

  setup do
    # Attach telemetry handler to catch decryption events
    handler_id = "test-handler-#{inspect(self())}"

    :telemetry.attach_many(
      handler_id,
      [
        [:famichat, :message, :decryption_error],
        [:famichat, :message, :serialized],
        [:famichat, :message, :deserialized]
      ],
      fn event, measurements, metadata, _ ->
        Logger.debug(
          "Telemetry event received: #{inspect(event)}, metadata: #{inspect(metadata)}"
        )

        send(self(), {event, measurements, metadata})
      end,
      nil
    )

    user = user_fixture()
    conversation = conversation_fixture(%{conversation_type: :direct})

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, user: user, conversation: conversation}
  end

  describe "message serialization with encryption metadata" do
    test "direct conversations require encryption metadata", %{
      user: user,
      conversation: conversation
    } do
      # Create a basic message with no encryption metadata
      params = %{
        sender_id: user.id,
        conversation_id: conversation.id,
        content: "Hello, this should be encrypted!",
        message_type: :text
      }

      # This should fail or emit a warning telemetry event because direct messages require encryption
      {:ok, _message} = MessageService.send_message(params)

      # Check if the message was serialized with encryption requirement warning
      assert_receive {[:famichat, :message, :serialized], _measurements,
                      %{
                        warning: :missing_encryption_metadata,
                        conversation_type: :direct
                      }},
                     @telemetry_timeout
    end

    test "serializes message with encryption metadata", %{
      user: user,
      conversation: conversation
    } do
      params = %{
        sender_id: user.id,
        conversation_id: conversation.id,
        content: "Encrypted message",
        message_type: :text,
        encryption_metadata: %{
          key_id: "KEY_DIRECT_v1",
          version_tag: "v1.0.0",
          encryption_flag: true
        }
      }

      {:ok, message} = MessageService.send_message(params)

      # Reload the message from the database to ensure metadata is persisted
      message = Repo.get!(Message, message.id)

      # Check that encryption metadata was properly stored
      assert message.metadata["encryption"] != nil
      assert message.metadata["encryption"]["key_id"] == "KEY_DIRECT_v1"
      assert message.metadata["encryption"]["version_tag"] == "v1.0.0"
      assert message.metadata["encryption"]["encryption_flag"] == true

      # Check if proper telemetry was emitted
      assert_receive {[:famichat, :message, :serialized], _measurements,
                      %{encryption_status: "enabled"}},
                     @telemetry_timeout
    end
  end

  describe "conversation type-specific encryption requirements" do
    test "each conversation type has appropriate encryption requirements" do
      # These assertions validate the encryption policy per conversation type
      assert MessageService.requires_encryption?(:direct) == true
      assert MessageService.requires_encryption?(:family) == true
      assert MessageService.requires_encryption?(:group) == true
      assert MessageService.requires_encryption?(:self) == true
    end
  end

  describe "message deserialization with encryption metadata" do
    test "deserializes message with encryption metadata preserved", %{
      user: user,
      conversation: conversation
    } do
      # Create a message with encryption metadata
      params = %{
        sender_id: user.id,
        conversation_id: conversation.id,
        content: "Encrypted content",
        message_type: :text,
        encryption_metadata: %{
          key_id: "KEY_DIRECT_v1",
          version_tag: "v1.0.0",
          encryption_flag: true
        }
      }

      {:ok, _message} = MessageService.send_message(params)

      # Get the message from the database
      {:ok, [retrieved_message]} =
        MessageService.get_conversation_messages(conversation.id)

      # Deserialize the message with encryption metadata
      {:ok, deserialized} =
        MessageService.deserialize_message(retrieved_message)

      # Check that encryption metadata is preserved
      assert deserialized.encryption_metadata.key_id == "KEY_DIRECT_v1"
      assert deserialized.encryption_metadata.version_tag == "v1.0.0"
      assert deserialized.encryption_metadata.encryption_flag == true

      # Check that proper telemetry was emitted
      assert_receive {[:famichat, :message, :deserialized], _measurements,
                      %{encryption_status: "enabled"}},
                     @telemetry_timeout
    end
  end

  describe "decryption error handling" do
    test "emits telemetry for malformed ciphertext" do
      # Create a standalone test for decryption failure
      message = %Message{
        id: Ecto.UUID.generate(),
        sender_id: Ecto.UUID.generate(),
        conversation_id: Ecto.UUID.generate(),
        content: "THIS_IS_INVALID_CIPHERTEXT",
        message_type: :text,
        metadata: %{
          "encryption" => %{
            "key_id" => "KEY_DIRECT_v1",
            "version_tag" => "v1.0.0",
            "encryption_flag" => true
          }
        }
      }

      # Listen directly for the decryption_error event
      test_pid = self()

      :telemetry.attach(
        "decryption-error-test-#{inspect(self())}",
        [:famichat, :message, :decryption_error],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:decryption_error, metadata})
        end,
        nil
      )

      # Clear the mailbox of existing events
      flush_mailbox()

      # Attempt to decrypt the message (this should fail)
      {:error, _reason} = MessageService.decrypt_message(message)

      # Wait for the telemetry event
      assert_receive {:decryption_error, metadata}, @telemetry_timeout

      # Check that the error code and type are correct
      assert metadata.error_code == 603
      assert metadata.error_type == "decryption_failure"

      # Ensure no sensitive data is included in the error details
      refute Map.has_key?(metadata, :key_id)
      refute Map.has_key?(metadata, :ciphertext)
      refute Map.has_key?(metadata, :plaintext)

      # Detach the telemetry handler
      :telemetry.detach("decryption-error-test-#{inspect(self())}")
    end
  end

  # Helper to clear mailbox of events
  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
