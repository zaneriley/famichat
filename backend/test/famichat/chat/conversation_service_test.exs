defmodule Famichat.Chat.ConversationServiceTest do
  use Famichat.DataCase

  alias Famichat.Chat.{ConversationService, Conversation}
  alias Famichat.Repo
  import Famichat.ChatFixtures

  describe "create_direct_conversation/2 self conversations" do
    test "creates a self conversation if not exists" do
      user = user_fixture()

      # Create a self conversation; expect a simple status tuple.
      {:ok, conversation} =
        ConversationService.create_direct_conversation(user.id, user.id)

      assert conversation.conversation_type == :self
      assert conversation.family_id == user.family_id
      assert Enum.any?(conversation.users, fn u -> u.id == user.id end)
    end

    test "returns existing self conversation when already created" do
      user = user_fixture()

      {:ok, conv1} =
        ConversationService.create_direct_conversation(user.id, user.id)

      {:ok, conv2} =
        ConversationService.create_direct_conversation(user.id, user.id)

      assert conv1.id == conv2.id

      # Optionally, you can check a log or telemetry event to know it was re-used.
    end
  end

  describe "create_direct_conversation/2 distinct conversations" do
    test "creates a direct conversation for users in the same family" do
      family = family_fixture()
      user1 = user_fixture(%{family_id: family.id})
      user2 = user_fixture(%{family_id: family.id})

      {:ok, conversation} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      assert conversation.conversation_type == :direct
      assert conversation.family_id == family.id

      user_ids = Enum.map(conversation.users, & &1.id)
      assert user1.id in user_ids
      assert user2.id in user_ids
    end

    test "returns existing direct conversation when already created" do
      family = family_fixture()
      user1 = user_fixture(%{family_id: family.id})
      user2 = user_fixture(%{family_id: family.id})

      {:ok, conv1} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      {:ok, conv2} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      assert conv1.id == conv2.id
    end

    test "fails when users are not in the same family" do
      family1 = family_fixture()
      family2 = family_fixture()

      user1 = user_fixture(%{family_id: family1.id})
      user2 = user_fixture(%{family_id: family2.id})

      {:error, reason} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      assert reason == :different_families
    end

    test "fails when one user does not exist" do
      family = family_fixture()
      user = user_fixture(%{family_id: family.id})

      {:error, reason} =
        ConversationService.create_direct_conversation(
          user.id,
          Ecto.UUID.generate()
        )

      assert reason == :user_not_found
    end
  end

  describe "list_user_conversations/1" do
    test "returns direct conversations for a given user" do
      user1 = user_fixture()
      user2 = user_fixture(%{family_id: user1.family_id})

      # Create a conversation between user1 and user2.
      {:ok, _conv} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      # List conversations for user1.
      {:ok, conversations} =
        ConversationService.list_user_conversations(user1.id)

      assert is_list(conversations)

      assert Enum.any?(conversations, fn c -> c.conversation_type == :direct end)

      # Similarly, list for user2.
      {:ok, conversations2} =
        ConversationService.list_user_conversations(user2.id)

      assert is_list(conversations2)
    end

    test "returns error when user_id is not a binary" do
      assert {:error, :invalid_user_id} =
               ConversationService.list_user_conversations(123)
    end
  end
end
