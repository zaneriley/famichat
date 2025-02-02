defmodule Famichat.Chat.MessageServiceTest do
  use Famichat.DataCase
  alias Famichat.Chat.{MessageService, Message, Conversation}
  alias Famichat.ChatFixtures

  describe "get_conversation_messages/1" do
    test "retrieves messages in chronological order for a valid conversation without pagination" do
      conversation = conversation_fixture(%{conversation_type: :direct})
      user = ChatFixtures.user_fixture()

      # Insert two messages with a slight delay to ensure different timestamps.
      {:ok, _msg1} = MessageService.send_message(user.id, conversation.id, "First message")
      :timer.sleep(5)
      {:ok, _msg2} = MessageService.send_message(user.id, conversation.id, "Second message")

      assert {:ok, messages} = MessageService.get_conversation_messages(conversation.id)
      assert length(messages) == 2
      # Validate the messages are in ascending order (oldest first)
      assert hd(messages).content == "First message"
      assert List.last(messages).content == "Second message"
    end

    test "returns an empty list when the conversation exists but has no messages" do
      conversation = conversation_fixture(%{conversation_type: :direct})
      assert {:ok, messages} = MessageService.get_conversation_messages(conversation.id)
      assert messages == []
    end

    test "returns error for a conversation id that does not exist" do
      non_existent_id = Ecto.UUID.generate()
      assert {:error, :not_found} = MessageService.get_conversation_messages(non_existent_id)
    end

    test "returns error when the conversation id is nil" do
      assert {:error, :invalid_conversation_id} = MessageService.get_conversation_messages(nil)
    end

    test "performance: retrieval completes under 150ms" do
      conversation = conversation_fixture(%{conversation_type: :direct})
      user = ChatFixtures.user_fixture()
      {:ok, _msg} = MessageService.send_message(user.id, conversation.id, "Test message")

      {time, {:ok, messages}} = :timer.tc(fn ->
        MessageService.get_conversation_messages(conversation.id)
      end)

      # Aggressive target: 150ms equals 150_000 microseconds.
      assert time < 150_000
      assert is_list(messages)
    end

    test "returns paginated messages with limit and offset" do
      conversation = conversation_fixture(%{conversation_type: :direct})
      user = ChatFixtures.user_fixture()

      base_ts = NaiveDateTime.utc_now()

      # Insert 5 messages with explicit inserted_at timestamps
      for i <- 1..5 do
        {:ok, msg} = MessageService.send_message(user.id, conversation.id, "Msg #{i}")
        # Set inserted_at to base_ts plus i seconds; convert to %DateTime{} with UTC
        new_ts =
          NaiveDateTime.add(base_ts, i, :second)
          |> DateTime.from_naive!("Etc/UTC")

        Famichat.Repo.update!(Ecto.Changeset.change(msg, inserted_at: new_ts))
      end

      # Retrieve messages with pagination: get 2 messages starting at offset 1.
      assert {:ok, paginated_messages} =
               MessageService.get_conversation_messages(conversation.id, limit: 2, offset: 1)

      assert length(paginated_messages) == 2

      # Check that the messages are returned in the expected order
      [first_msg, second_msg] = paginated_messages
      assert first_msg.content == "Msg 2"
      assert second_msg.content == "Msg 3"
    end

    test "returns error for invalid pagination options" do
      conversation = conversation_fixture(%{conversation_type: :direct})
      # Passing non-integer limit.
      assert {:error, :invalid_pagination_values} =
               MessageService.get_conversation_messages(conversation.id, limit: "ten", offset: -1)
    end
  end

  describe "telemetry" do
    setup do
      # Create a unique handler ID for this test
      handler_id = "test-handler-get-conversation-messages-#{System.unique_integer([:positive])}"
      :telemetry.attach(
         handler_id,
         [:famichat, :message_service, :get_conversation_messages, :stop],
         fn event, measurements, metadata, _config ->
           send(self(), {:telemetry_event, event, measurements, metadata, handler_id})
         end,
         nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "emits telemetry event" do
      conversation = conversation_fixture(%{conversation_type: :direct})
      user = ChatFixtures.user_fixture()
      {:ok, _msg} = MessageService.send_message(user.id, conversation.id, "Telemetry test message")

      # Call the function to trigger the telemetry span.
      assert {:ok, _} = MessageService.get_conversation_messages(conversation.id)

      # Assert that we receive the telemetry event.
      assert_receive {
         :telemetry_event,
         [:famichat, :message_service, :get_conversation_messages, :stop],
         measurements,
         _metadata,
         _handler_id
      } when is_map_key(measurements, :duration)
    end
  end

  # Helper to create a conversation fixture.
  defp conversation_fixture(attrs \\ %{}) do
    family = ChatFixtures.family_fixture()
    attrs =
      attrs
      |> Enum.into(%{
        family_id: family.id,
        conversation_type: :direct,
        metadata: %{}
      })

    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Famichat.Repo.insert!()
  end
end
