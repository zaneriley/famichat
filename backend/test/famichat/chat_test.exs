defmodule Famichat.ChatTest do
  use Famichat.DataCase

  alias Famichat.Chat

  import Famichat.ChatFixtures

  describe "users" do
    alias Famichat.Chat.User

    @invalid_attrs %{username: nil, family_id: nil}

    test "list_users/0 returns all users" do
      user = user_fixture()
      users = Chat.list_users()
      assert Enum.any?(users, fn u -> u.id == user.id end)
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Chat.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      family = family_fixture()

      valid_attrs = %{
        username: "some username",
        email: "some_email@example.com",
        family_id: family.id,
        role: :member
      }

      assert {:ok, %User{} = user} = Chat.create_user(valid_attrs)
      assert user.username == "some username"
      assert user.email == "some_email@example.com"
      assert user.family_id == family.id
      assert user.role == :member
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Chat.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()
      update_attrs = %{username: "some updated username"}

      assert {:ok, %User{} = user} = Chat.update_user(user, update_attrs)
      assert user.username == "some updated username"
    end

    test "update_user/2 with invalid data returns error changeset" do
      user = user_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Chat.update_user(user, @invalid_attrs)

      assert user == Chat.get_user!(user.id)
    end

    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Chat.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Chat.get_user!(user.id) end
    end

    test "change_user/1 returns a user changeset" do
      user = user_fixture()
      assert %Ecto.Changeset{} = Chat.change_user(user)
    end
  end

  describe "conversation visibility" do
    alias Famichat.Chat.Conversation

    setup do
      family = family_fixture()
      user1 = user_fixture(family_id: family.id)
      user2 = user_fixture(family_id: family.id)
      user3 = user_fixture(family_id: family.id)

      # Generate a direct key for direct conversations
      direct_key =
        Conversation.compute_direct_key(user1.id, user2.id, family.id)

      conv1 =
        conversation_fixture(%{
          family_id: family.id,
          conversation_type: :direct,
          direct_key: direct_key
        })

      conv2 =
        conversation_fixture(%{
          family_id: family.id,
          conversation_type: :group,
          metadata: %{
            "name" => "Test Group"
          }
        })

      conv3 =
        conversation_fixture(%{
          family_id: family.id,
          conversation_type: :family,
          metadata: %{
            "name" => "Family Chat"
          }
        })

      %{
        family: family,
        user1: user1,
        user2: user2,
        user3: user3,
        conv1: conv1,
        conv2: conv2,
        conv3: conv3
      }
    end

    test "hide_conversation/2 adds user to hidden_by_users", %{
      conv1: conv,
      user1: user
    } do
      assert {:ok, updated_conv} = Chat.hide_conversation(conv.id, user.id)
      assert user.id in updated_conv.hidden_by_users
    end

    test "hide_conversation/2 returns error for non-existent conversation", %{
      user1: user
    } do
      assert {:error, :not_found} =
               Chat.hide_conversation(Ecto.UUID.generate(), user.id)
    end

    test "hide_conversation/2 is idempotent", %{conv1: conv, user1: user} do
      assert {:ok, conv1} = Chat.hide_conversation(conv.id, user.id)
      assert {:ok, conv2} = Chat.hide_conversation(conv.id, user.id)
      assert conv1.hidden_by_users == conv2.hidden_by_users
    end

    test "unhide_conversation/2 removes user from hidden_by_users", %{
      conv1: conv,
      user1: user
    } do
      {:ok, hidden_conv} = Chat.hide_conversation(conv.id, user.id)
      assert user.id in hidden_conv.hidden_by_users

      {:ok, updated_conv} = Chat.unhide_conversation(conv.id, user.id)
      refute user.id in updated_conv.hidden_by_users
    end

    test "list_visible_conversations/1 excludes hidden conversations", %{
      user1: user,
      conv1: conv1,
      conv2: conv2,
      conv3: conv3
    } do
      # Initially all our test conversations should be visible
      conversations = Chat.list_visible_conversations(user.id)
      assert Enum.find(conversations, &(&1.id == conv1.id))
      assert Enum.find(conversations, &(&1.id == conv2.id))
      assert Enum.find(conversations, &(&1.id == conv3.id))

      # Hide one conversation
      {:ok, _} = Chat.hide_conversation(conv1.id, user.id)

      # Now conv1 should not be visible, but conv2 and conv3 should be
      conversations = Chat.list_visible_conversations(user.id)
      refute Enum.find(conversations, &(&1.id == conv1.id))
      assert Enum.find(conversations, &(&1.id == conv2.id))
      assert Enum.find(conversations, &(&1.id == conv3.id))
    end

    test "list_visible_conversations/2 preloads associations", %{user1: user} do
      conversations =
        Chat.list_visible_conversations(user.id, preload: [:participants])

      assert hd(conversations).participants != nil
    end
  end
end
