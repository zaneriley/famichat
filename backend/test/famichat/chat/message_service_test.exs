defmodule Famichat.Chat.MessageServiceTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.{
    ConversationAccess,
    ConversationService,
    MessageService,
    Message
  }

  alias Famichat.Repo
  import Famichat.ChatFixtures

  setup do
    previous = Application.get_env(:famichat, :mls_enforcement, false)
    Application.put_env(:famichat, :mls_enforcement, false)

    on_exit(fn ->
      Application.put_env(:famichat, :mls_enforcement, previous)
    end)

    :ok
  end

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

    test "supports catch-up cursor via after message id (exclusive)", %{
      conversation: conv,
      user: user
    } do
      {:ok, m1} =
        MessageService.send_message(
          valid_message_params(user, conv, "msg-1", 1)
        )

      {:ok, m2} =
        MessageService.send_message(
          valid_message_params(user, conv, "msg-2", 2)
        )

      {:ok, m3} =
        MessageService.send_message(
          valid_message_params(user, conv, "msg-3", 3)
        )

      {:ok, m4} =
        MessageService.send_message(
          valid_message_params(user, conv, "msg-4", 4)
        )

      assert {:ok, [msg2, msg3]} =
               MessageService.get_conversation_messages(conv.id,
                 limit: 2,
                 after: m1.id
               )

      assert msg2.id == m2.id
      assert msg3.id == m3.id

      assert {:ok, [msg4]} =
               MessageService.get_conversation_messages(conv.id,
                 limit: 2,
                 after: m3.id
               )

      assert msg4.id == m4.id
    end

    test "returns invalid pagination when after is malformed", %{
      conversation: conv
    } do
      assert {:error, {:invalid_pagination, changeset}} =
               MessageService.get_conversation_messages(conv.id,
                 after: "not-a-uuid"
               )

      assert {"is invalid", _} = Keyword.fetch!(changeset.errors, :after)
    end

    test "returns invalid pagination when after cursor is outside conversation",
         %{conversation: conv} do
      other_conversation = conversation_fixture(%{conversation_type: :direct})
      [other_user | _] = ConversationService.list_members(other_conversation)

      {:ok, foreign_message} =
        MessageService.send_message(
          valid_message_params(other_user, other_conversation, "foreign", 1)
        )

      assert {:error, {:invalid_pagination, changeset}} =
               MessageService.get_conversation_messages(conv.id,
                 after: foreign_message.id
               )

      assert {"does not belong to this conversation", _} =
               Keyword.fetch!(changeset.errors, :after)
    end

    test "returns invalid pagination when after and offset are combined", %{
      conversation: conv,
      user: user
    } do
      {:ok, m1} =
        MessageService.send_message(
          valid_message_params(user, conv, "msg-1", 1)
        )

      assert {:error, {:invalid_pagination, changeset}} =
               MessageService.get_conversation_messages(conv.id,
                 after: m1.id,
                 offset: 1
               )

      assert {"must be empty when after is provided", _} =
               Keyword.fetch!(changeset.errors, :offset)
    end

    test "uses inserted_at + id ordering for stable cursor paging", %{
      conversation: conv,
      user: user
    } do
      timestamp = ~U[2026-01-01 00:00:00.000000Z]
      m1 = create_message_at!(user, conv, "same-ts-a", timestamp)
      m2 = create_message_at!(user, conv, "same-ts-b", timestamp)

      m3 =
        create_message_at!(
          user,
          conv,
          "next-ts",
          DateTime.add(timestamp, 1, :second)
        )

      expected_first_ids = Enum.sort([m1.id, m2.id])

      assert {:ok, first_page} =
               MessageService.get_conversation_messages(conv.id, limit: 2)

      assert Enum.map(first_page, & &1.id) == expected_first_ids

      assert {:ok, [next_message]} =
               MessageService.get_conversation_messages(conv.id,
                 limit: 2,
                 after: List.last(expected_first_ids)
               )

      assert next_message.id == m3.id
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

      assert {:error, {:invalid_pagination, changeset}} =
               MessageService.get_conversation_messages(conversation.id,
                 limit: "ten",
                 offset: -1
               )

      assert {"is invalid", _} = Keyword.fetch!(changeset.errors, :limit)

      assert {"must be greater than or equal to %{number}", _} =
               Keyword.fetch!(changeset.errors, :offset)
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

  defp create_message_at!(user, conv, content, inserted_at) do
    %Message{
      sender_id: user.id,
      conversation_id: conv.id,
      content: content,
      inserted_at: inserted_at,
      updated_at: inserted_at
    }
    |> Repo.insert!()
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
