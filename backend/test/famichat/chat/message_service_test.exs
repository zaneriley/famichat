defmodule Famichat.Chat.MessageServiceTest do
  use Famichat.DataCase
  use ExUnit.Case, async: true

  alias Famichat.Chat.{
    ConversationAccess,
    ConversationService,
    MessageService,
    Message
  }

  alias Famichat.Repo
  import Famichat.ChatFixtures

  describe "get_conversation_messages/2" do
    setup do
      conversation = conversation_fixture(%{conversation_type: :direct})
      [user | _] = ConversationService.list_members(conversation)

      {:ok, conversation: conversation, user: user}
    end

    test "returns messages in chronological order", %{
      conversation: conv,
      user: user
    } do
      params1 = valid_message_params(user, conv, "First", 1)
      params2 = valid_message_params(user, conv, "Second", 2)
      {:ok, m1} = MessageService.send_message(params1)
      {:ok, m2} = MessageService.send_message(params2)

      assert {:ok, [%{id: id1}, %{id: id2}]} =
               MessageService.get_conversation_messages(conv.id)

      assert id1 == m1.id
      assert id2 == m2.id
    end

    test "handles pagination parameters", %{conversation: conv, user: user} do
      create_messages(conv, user, 5)

      assert {:ok, [_, _]} =
               MessageService.get_conversation_messages(conv.id, limit: 2)

      assert {:ok, messages} =
               MessageService.get_conversation_messages(conv.id,
                 limit: 2,
                 offset: 1
               )

      assert length(messages) == 2
    end

    test "returns error for invalid conversation ID" do
      assert {:error, :invalid_conversation_id} =
               MessageService.get_conversation_messages(nil)

      assert {:error, :conversation_not_found} =
               MessageService.get_conversation_messages(Ecto.UUID.generate())
    end

    test "preloads associations when requested", %{
      conversation: conv,
      user: user
    } do
      create_message(user, conv, "Test")

      assert {:ok, [msg]} =
               MessageService.get_conversation_messages(conv.id,
                 preload: [:sender]
               )

      assert %{sender: %Famichat.Accounts.User{}} = msg
    end

    test "returns error for invalid pagination options" do
      conversation = conversation_fixture(%{conversation_type: :direct})
      # Passing non-integer limit.
      assert {:error, {:error, :invalid_limit}} =
               MessageService.get_conversation_messages(conversation.id,
                 limit: "ten",
                 offset: -1
               )
    end

    test "telemetry emits telemetry event" do
      conv = conversation_fixture(%{conversation_type: :direct})
      [user | _] = ConversationService.list_members(conv)

      assert ConversationAccess.member?(conv.id, user.id)

      user_id = user.id
      conv_id = conv.id
      params = valid_message_params(user, conv, "Telemetry test message")

      # Attach temporary handler for test environment
      :telemetry.attach_many(
        "test-handler-#{inspect(self())}",
        [[:famichat, :message, :sent]],
        fn event, measurements, metadata, _ ->
          send(self(), {event, measurements, metadata})
        end,
        nil
      )

      {:ok, _msg} = MessageService.send_message(params)

      assert_receive {
                       [:famichat, :message, :sent],
                       %{count: 1},
                       %{sender_id: ^user_id, conversation_id: ^conv_id}
                     },
                     5000

      # Cleanup handler
      :telemetry.detach("test-handler-#{inspect(self())}")
    end
  end

  describe "send_message/1" do
    setup do
      conv = conversation_fixture(%{conversation_type: :direct})
      [participant | _] = ConversationService.list_members(conv)

      {:ok, user: participant, conv: conv}
    end

    test "creates valid message", %{user: user, conv: conv} do
      params = valid_message_params(user, conv)
      assert {:ok, %Message{}} = MessageService.send_message(params)
    end

    test "validates required fields", %{user: user, conv: conv} do
      assert {:error, {:missing_fields, [:content]}} =
               MessageService.send_message(%{
                 sender_id: user.id,
                 conversation_id: conv.id
               })
    end

    test "verifies sender existence", %{conv: conv} do
      params = valid_message_params(%{id: Ecto.UUID.generate()}, conv)
      assert {:error, :sender_not_found} = MessageService.send_message(params)
    end

    test "verifies conversation existence", %{user: user} do
      params = valid_message_params(user, %{id: Ecto.UUID.generate()})

      assert {:error, :conversation_not_found} =
               MessageService.send_message(params)
    end

    test "rejects messages from non-participants", %{conv: conv} do
      outsider = user_fixture(%{family_id: conv.family_id})
      params = valid_message_params(outsider, conv)

      assert {:error, :not_participant} = MessageService.send_message(params)
    end

    test "rejects cross-family messages in family conversation", %{user: user} do
      family = family_fixture()
      _member = membership_fixture(user, family)

      family_conversation =
        conversation_fixture(%{
          conversation_type: :family,
          family_id: family.id,
          user1: user
        })

      outsider = user_fixture()
      params = valid_message_params(outsider, family_conversation)

      assert {:error, :wrong_family} = MessageService.send_message(params)
    end

    test "emits telemetry on authorization failure", %{conv: conv} do
      outsider = user_fixture(%{family_id: conv.family_id})

      :telemetry.attach_many(
        "auth-denied-#{inspect(self())}",
        [[:famichat, :conversation, :authorization_denied]],
        fn event, measurements, metadata, _ ->
          send(self(), {event, measurements, metadata})
        end,
        nil
      )

      params = valid_message_params(outsider, conv)
      assert {:error, :not_participant} = MessageService.send_message(params)

      assert_receive {
                       [:famichat, :conversation, :authorization_denied],
                       %{count: 1},
                       %{action: :send_message, reason: :not_participant}
                     },
                     5_000

      :telemetry.detach("auth-denied-#{inspect(self())}")
    end
  end

  defp create_messages(conv, user, count) do
    for i <- 1..count do
      create_message(user, conv, "Msg #{i}", i)
    end
  end

  defp create_message(user, conv, content, delay_sec \\ 0) do
    message = %Message{
      sender_id: user.id,
      conversation_id: conv.id,
      content: content,
      inserted_at: DateTime.add(DateTime.utc_now(), delay_sec, :second)
    }

    Repo.insert(message)
  end

  defp valid_message_params(
         user,
         conv,
         content \\ "Valid message",
         delay_sec \\ 0
       ) do
    %{
      sender_id: user.id,
      conversation_id: conv.id,
      content: content,
      inserted_at: DateTime.add(DateTime.utc_now(), delay_sec, :second)
    }
  end
end
