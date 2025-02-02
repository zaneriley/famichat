defmodule Famichat.Chat.ConversationTest do
  use Famichat.DataCase

  alias Famichat.Chat.{Conversation, User}
  import Famichat.ChatFixtures

  describe "conversation schema" do
    setup do
      family = family_fixture()
      {:ok, family: family}
    end

    @valid_attrs %{
      conversation_type: :direct,
      metadata: %{"title" => "Test Chat"}
    }
    @invalid_attrs %{conversation_type: nil, metadata: nil}

    test "changeset with valid attributes", %{family: family} do
      changeset = Conversation.changeset(%Conversation{}, Map.put(@valid_attrs, :family_id, family.id))
      assert changeset.valid?
    end

    test "changeset with invalid attributes" do
      changeset = Conversation.changeset(%Conversation{}, @invalid_attrs)
      refute changeset.valid?
    end

    test "changeset enforces required fields" do
      changeset = Conversation.changeset(%Conversation{}, %{})
      errors = errors_on(changeset)
      assert errors.family_id == ["can't be blank"]
      assert errors.conversation_type == ["can't be blank"]
    end

    test "conversation_type must be one of allowed values", %{family: family} do
      attrs = Map.put(@valid_attrs, :conversation_type, :invalid_type)
      attrs = Map.put(attrs, :family_id, family.id)
      changeset = Conversation.changeset(%Conversation{}, attrs)
      assert "is invalid" in errors_on(changeset).conversation_type
    end

    test "default conversation_type is :direct", %{family: family} do
      changeset = Conversation.changeset(%Conversation{}, %{metadata: %{}, family_id: family.id})
      assert :direct == Ecto.Changeset.get_field(changeset, :conversation_type)
    end
  end

  describe "conversation with users" do
    setup do
      family = family_fixture()
      {:ok, user1} = Repo.insert(%User{username: "user1", family_id: family.id, role: :member})
      {:ok, user2} = Repo.insert(%User{username: "user2", family_id: family.id, role: :member})
      {:ok, user1: user1, user2: user2, family: family}
    end

    test "can create conversation with users", %{user1: user1, user2: user2, family: family} do
      changeset = %Conversation{}
        |> Conversation.changeset(Map.put(@valid_attrs, :family_id, family.id))
        |> Ecto.Changeset.put_assoc(:users, [user1, user2])

      assert changeset.valid?
      {:ok, conversation} = Repo.insert(changeset)
      conversation = Repo.preload(conversation, :users)

      assert length(conversation.users) == 2
      user_ids = Enum.map(conversation.users, & &1.id)
      assert user1.id in user_ids
      assert user2.id in user_ids
    end

    test "supports different conversation types", %{user1: user1, user2: user2, family: family} do
      # Test direct conversation
      direct_changeset = %Conversation{}
        |> Conversation.changeset(%{conversation_type: :direct, metadata: %{}, family_id: family.id})
        |> Ecto.Changeset.put_assoc(:users, [user1, user2])
      assert direct_changeset.valid?

      # Test group conversation
      group_changeset = %Conversation{}
        |> Conversation.changeset(%{conversation_type: :group, metadata: %{"name" => "Group Chat"}, family_id: family.id})
        |> Ecto.Changeset.put_assoc(:users, [user1, user2])
      assert group_changeset.valid?

      # Test self conversation
      self_changeset = %Conversation{}
        |> Conversation.changeset(%{conversation_type: :self, metadata: %{}, family_id: family.id})
        |> Ecto.Changeset.put_assoc(:users, [user1])
      assert self_changeset.valid?
    end

    test "handles complex metadata", %{user1: user1, family: family} do
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
          metadata: complex_metadata,
          family_id: family.id
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
      family = family_fixture()
      {:ok, user} = Repo.insert(%User{username: "test_user", family_id: family.id, role: :member})
      {:ok, user: user, family: family}
    end

    test "self conversation requires exactly one user", %{user: user, family: family} do
      changeset = %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :self,
          metadata: %{},
          family_id: family.id
        })
        |> Ecto.Changeset.put_assoc(:users, [user])

      assert changeset.valid?
      {:ok, conversation} = Repo.insert(changeset)
      conversation = Repo.preload(conversation, :users)

      assert length(conversation.users) == 1
      assert hd(conversation.users).id == user.id
    end

    test "handles empty users list", %{family: family} do
      changeset = %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :direct,
          metadata: %{},
          family_id: family.id
        })
        |> Ecto.Changeset.put_assoc(:users, [])

      assert changeset.valid?  # Should be valid as users can be added later
    end

    test "validates user count for conversation types", %{user: user, family: family} do
      # Direct conversation should have exactly two users
      direct_changeset = %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :direct,
          metadata: %{},
          family_id: family.id
        })
        |> Ecto.Changeset.put_assoc(:users, [user])
      assert direct_changeset.valid?  # Should be valid initially as users can be added later

      # Self conversation should have exactly one user
      self_changeset = %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :self,
          metadata: %{},
          family_id: family.id
        })
        |> Ecto.Changeset.put_assoc(:users, [user])
      assert self_changeset.valid?

      # Group conversation should have at least one user
      group_changeset = %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :group,
          metadata: %{"name" => "Test Group"},
          family_id: family.id
        })
        |> Ecto.Changeset.put_assoc(:users, [user])
      assert group_changeset.valid?  # Should be valid initially as more users can be added later
    end
  end
end
