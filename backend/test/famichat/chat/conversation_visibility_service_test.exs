defmodule Famichat.Chat.ConversationVisibilityServiceTest do
  use Famichat.DataCase

  alias Famichat.Chat.ConversationVisibilityService
  import Famichat.ChatFixtures

  describe "conversation visibility" do
    setup do
      family = family_fixture()
      user1 = user_fixture(%{family_id: family.id})
      user2 = user_fixture(%{family_id: family.id})
      user3 = user_fixture(%{family_id: family.id})

      # Create several conversations with different participants
      conversation1 = conversation_fixture(%{family_id: family.id, user1: user1, user2: user2})
      conversation2 = conversation_fixture(%{family_id: family.id, user1: user1, user2: user3})
      conversation3 = conversation_fixture(%{family_id: family.id, user1: user2, user2: user3})

      {:ok,
       family: family,
       user1: user1,
       user2: user2,
       user3: user3,
       conversation1: conversation1,
       conversation2: conversation2,
       conversation3: conversation3
      }
    end

    test "hide_conversation/2 hides a conversation for a user", %{user1: user1, conversation1: conversation} do
      assert {:ok, updated_convo} = ConversationVisibilityService.hide_conversation(conversation.id, user1.id)
      assert user1.id in updated_convo.hidden_by_users
    end

    test "hide_conversation/2 returns error for non-existent conversation", %{user1: user1} do
      assert {:error, :not_found} = ConversationVisibilityService.hide_conversation(Ecto.UUID.generate(), user1.id)
    end

    test "hide_conversation/2 is idempotent", %{user1: user1, conversation1: conversation} do
      # Hide conversation first time
      assert {:ok, updated_convo} = ConversationVisibilityService.hide_conversation(conversation.id, user1.id)
      assert user1.id in updated_convo.hidden_by_users
      assert length(updated_convo.hidden_by_users) == 1

      # Hide same conversation again - should not duplicate user in list
      assert {:ok, updated_convo2} = ConversationVisibilityService.hide_conversation(conversation.id, user1.id)
      assert user1.id in updated_convo2.hidden_by_users
      assert length(updated_convo2.hidden_by_users) == 1
    end

    test "unhide_conversation/2 unhides a conversation for a user", %{user1: user1, conversation1: conversation} do
      # First hide the conversation
      {:ok, hidden_convo} = ConversationVisibilityService.hide_conversation(conversation.id, user1.id)
      assert user1.id in hidden_convo.hidden_by_users

      # Then unhide it
      assert {:ok, updated_convo} = ConversationVisibilityService.unhide_conversation(conversation.id, user1.id)
      refute user1.id in updated_convo.hidden_by_users
    end

    test "unhide_conversation/2 returns error for non-existent conversation", %{user1: user1} do
      assert {:error, :not_found} = ConversationVisibilityService.unhide_conversation(Ecto.UUID.generate(), user1.id)
    end

    test "unhide_conversation/2 is idempotent", %{user1: user1, conversation1: conversation} do
      # First hide the conversation
      {:ok, _} = ConversationVisibilityService.hide_conversation(conversation.id, user1.id)

      # Unhide conversation first time
      assert {:ok, updated_convo} = ConversationVisibilityService.unhide_conversation(conversation.id, user1.id)
      refute user1.id in updated_convo.hidden_by_users

      # Unhide same conversation again - should be a no-op
      assert {:ok, updated_convo2} = ConversationVisibilityService.unhide_conversation(conversation.id, user1.id)
      refute user1.id in updated_convo2.hidden_by_users
    end

    test "list_visible_conversations/1 excludes hidden conversations", %{
      user1: user1,
      conversation1: conversation1,
      conversation2: conversation2,
      conversation3: conversation3
    } do
      # Initially all conversations should be visible
      visible = ConversationVisibilityService.list_visible_conversations(user1.id)
      assert length(visible) >= 3
      assert Enum.any?(visible, fn c -> c.id == conversation1.id end)
      assert Enum.any?(visible, fn c -> c.id == conversation2.id end)
      assert Enum.any?(visible, fn c -> c.id == conversation3.id end)

      # Hide conversation1
      {:ok, _} = ConversationVisibilityService.hide_conversation(conversation1.id, user1.id)

      # Now conversation1 should not be visible
      visible = ConversationVisibilityService.list_visible_conversations(user1.id)
      refute Enum.any?(visible, fn c -> c.id == conversation1.id end)
      assert Enum.any?(visible, fn c -> c.id == conversation2.id end)
      assert Enum.any?(visible, fn c -> c.id == conversation3.id end)

      # Hide conversation2
      {:ok, _} = ConversationVisibilityService.hide_conversation(conversation2.id, user1.id)

      # Now both conversation1 and conversation2 should not be visible
      visible = ConversationVisibilityService.list_visible_conversations(user1.id)
      refute Enum.any?(visible, fn c -> c.id == conversation1.id end)
      refute Enum.any?(visible, fn c -> c.id == conversation2.id end)
      assert Enum.any?(visible, fn c -> c.id == conversation3.id end)
    end

    test "list_visible_conversations/2 can preload associations", %{
      user1: user1
    } do
      # Test with preloading users
      visible = ConversationVisibilityService.list_visible_conversations(user1.id, preload: [:users])
      assert length(visible) > 0

      # All conversations should have users preloaded
      Enum.each(visible, fn conversation ->
        assert Ecto.assoc_loaded?(conversation.users)
      end)
    end
  end
end
