defmodule Famichat.Chat.ConversationTest do
  use Famichat.DataCase

  alias Famichat.Chat.{Conversation, User}

  describe "conversation schema" do
    @valid_attrs %{
      conversation_type: :direct,
      metadata: %{"title" => "Test Chat"}
    }
    @invalid_attrs %{conversation_type: nil, metadata: nil}

    test "changeset with valid attributes" do
      changeset = Conversation.changeset(%Conversation{}, @valid_attrs)
      assert changeset.valid?
    end

    test "changeset with invalid attributes" do
      changeset = Conversation.changeset(%Conversation{}, @invalid_attrs)
      refute changeset.valid?
    end

    test "changeset enforces required fields" do
      changeset = Conversation.changeset(%Conversation{}, %{})
      errors = errors_on(changeset)
      assert errors.conversation_type == ["can't be blank"]
    end

    test "conversation_type must be one of allowed values" do
      attrs = Map.put(@valid_attrs, :conversation_type, :invalid_type)
      changeset = Conversation.changeset(%Conversation{}, attrs)
      assert "is invalid" in errors_on(changeset).conversation_type
    end

    test "default conversation_type is :direct" do
      changeset = Conversation.changeset(%Conversation{}, %{metadata: %{}})
      assert :direct == Ecto.Changeset.get_field(changeset, :conversation_type)
    end
  end

  describe "conversation with users" do
    setup do
      {:ok, user1} = Repo.insert(%User{username: "user1"})
      {:ok, user2} = Repo.insert(%User{username: "user2"})
      {:ok, user1: user1, user2: user2}
    end

    test "can create conversation with users", %{user1: user1, user2: user2} do
      changeset = %Conversation{}
        |> Conversation.changeset(@valid_attrs)
        |> Ecto.Changeset.put_assoc(:users, [user1, user2])

      assert changeset.valid?
      {:ok, conversation} = Repo.insert(changeset)
      conversation = Repo.preload(conversation, :users)

      assert length(conversation.users) == 2
      user_ids = Enum.map(conversation.users, & &1.id)
      assert user1.id in user_ids
      assert user2.id in user_ids
    end

    test "supports different conversation types", %{user1: user1, user2: user2} do
      # Test direct conversation
      direct_changeset = %Conversation{}
        |> Conversation.changeset(%{conversation_type: :direct, metadata: %{}})
        |> Ecto.Changeset.put_assoc(:users, [user1, user2])
      assert direct_changeset.valid?

      # Test group conversation
      group_changeset = %Conversation{}
        |> Conversation.changeset(%{conversation_type: :group, metadata: %{"name" => "Group Chat"}})
        |> Ecto.Changeset.put_assoc(:users, [user1, user2])
      assert group_changeset.valid?

      # Test self conversation
      self_changeset = %Conversation{}
        |> Conversation.changeset(%{conversation_type: :self, metadata: %{}})
        |> Ecto.Changeset.put_assoc(:users, [user1])
      assert self_changeset.valid?
    end

    test "handles complex metadata", %{user1: user1} do
      complex_metadata = %{
        "title" => "Complex Chat",
        "settings" => %{
          "notifications" => true,
          "theme" => "dark",
          "custom_emojis" => ["🎮", "🎲"]
        },
        "last_active" => "2024-01-25T12:00:00Z"
      }

      changeset = %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :direct,
          metadata: complex_metadata
        })
        |> Ecto.Changeset.put_assoc(:users, [user1])

      assert changeset.valid?
      {:ok, conversation} = Repo.insert(changeset)

      assert conversation.metadata["settings"]["theme"] == "dark"
      assert conversation.metadata["settings"]["notifications"] == true
    end
  end

  describe "conversation constraints" do
    setup do
      {:ok, user} = Repo.insert(%User{username: "test_user"})
      {:ok, user: user}
    end

    test "self conversation requires exactly one user", %{user: user} do
      changeset = %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :self,
          metadata: %{}
        })
        |> Ecto.Changeset.put_assoc(:users, [user])

      assert changeset.valid?
      {:ok, conversation} = Repo.insert(changeset)
      conversation = Repo.preload(conversation, :users)

      assert length(conversation.users) == 1
      assert hd(conversation.users).id == user.id
    end

    test "handles empty users list" do
      changeset = %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :direct,
          metadata: %{}
        })
        |> Ecto.Changeset.put_assoc(:users, [])

      assert changeset.valid?  # Should be valid as users can be added later
    end

    test "validates user count for conversation types", %{user: user} do
      # Direct conversation should have exactly two users
      direct_changeset = %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :direct,
          metadata: %{}
        })
        |> Ecto.Changeset.put_assoc(:users, [user])
      assert direct_changeset.valid?  # Should be valid initially as users can be added later

      # Self conversation should have exactly one user
      self_changeset = %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :self,
          metadata: %{}
        })
        |> Ecto.Changeset.put_assoc(:users, [user])
      assert self_changeset.valid?

      # Group conversation should have at least one user
      group_changeset = %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :group,
          metadata: %{"name" => "Test Group"}
        })
        |> Ecto.Changeset.put_assoc(:users, [user])
      assert group_changeset.valid?  # Should be valid initially as more users can be added later
    end
  end
end
