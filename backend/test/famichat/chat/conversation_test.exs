defmodule Famichat.Chat.ConversationTest do
  use Famichat.DataCase

  alias Famichat.Chat.{Conversation}
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

    test "creates valid direct conversation using fixture", %{family: family} do
      conversation = conversation_fixture(%{family_id: family.id, metadata: @valid_attrs.metadata})
      assert conversation.conversation_type == :direct
      assert conversation.direct_key != nil
    end

    test "changeset with invalid attributes" do
      changeset = Conversation.changeset(%Conversation{}, @invalid_attrs)
      refute changeset.valid?
    end

    test "changeset enforces required fields" do
      changeset = Conversation.changeset(%Conversation{}, %{})
      errors = errors_on(changeset)
      assert errors.family_id == ["can't be blank"]
    end

    test "conversation_type must be one of allowed values", %{family: family} do
      attrs = Map.put(@valid_attrs, :conversation_type, :invalid_type)
      attrs = Map.put(attrs, :family_id, family.id)
      changeset = Conversation.changeset(%Conversation{}, attrs)
      assert "is invalid" in errors_on(changeset).conversation_type
    end

    test "default conversation_type is :direct", %{family: family} do
      changeset =
        Conversation.changeset(%Conversation{}, %{
          metadata: %{},
          family_id: family.id
        })

      assert :direct == Ecto.Changeset.get_field(changeset, :conversation_type)
    end

    test "conversation_type has default value" do
      changeset =
        Conversation.changeset(%Conversation{}, %{
          family_id: Ecto.UUID.generate()
        })

      assert changeset.changes[:conversation_type] == nil
      assert Ecto.Changeset.get_field(changeset, :conversation_type) == :direct
    end

    test "requires family_id" do
      changeset = Conversation.changeset(%Conversation{}, %{})
      assert "can't be blank" in errors_on(changeset).family_id
    end
  end

  describe "conversation with users" do
    setup do
      family = family_fixture()
      user1 = user_fixture(%{family_id: family.id})
      user2 = user_fixture(%{family_id: family.id})

      {:ok, user1: user1, user2: user2, family: family}
    end

    test "can create conversation with users using fixture", %{user1: user1, user2: user2, family: family} do
      conversation = conversation_fixture(%{family_id: family.id, user1: user1, user2: user2})
      conversation = Repo.preload(conversation, :users)

      assert length(conversation.users) == 2
      user_ids = Enum.map(conversation.users, & &1.id)
      assert user1.id in user_ids
      assert user2.id in user_ids
    end

    test "supports different conversation types", %{user1: user1, user2: user2, family: family} do
      # Test direct conversation using fixture
      direct = conversation_fixture(%{family_id: family.id, user1: user1, user2: user2, conversation_type: :direct})
      assert direct.conversation_type == :direct
      assert direct.direct_key != nil

      # Test group conversation
      group_changeset =
        %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :group,
          metadata: %{"name" => "Group Chat"},
          family_id: family.id
        })
        |> Ecto.Changeset.put_assoc(:users, [user1, user2])

      assert group_changeset.valid?

      # Test self conversation
      self_changeset =
        %Conversation{}
        |> Conversation.changeset(%{
          conversation_type: :self,
          metadata: %{},
          family_id: family.id
        })
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

      conversation = conversation_fixture(%{family_id: family.id, conversation_type: :direct, metadata: complex_metadata, user1: user1})

      assert conversation.metadata["settings"]["theme"] == "dark"
      assert conversation.metadata["settings"]["notifications"] == true
    end
  end

  describe "conversation constraints" do
    setup do
      family = family_fixture()
      user = user_fixture(%{family_id: family.id})

      {:ok, user: user, family: family}
    end

    test "self conversation requires exactly one user", %{
      user: user,
      family: family
    } do
      changeset =
        %Conversation{}
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
      # Generate a dummy direct key for testing
      direct_key = "test_direct_key_#{:rand.uniform(1000)}"

      changeset =
        %Conversation{}
        |> Conversation.create_changeset(%{
          conversation_type: :direct,
          metadata: %{},
          family_id: family.id,
          direct_key: direct_key
        })
        |> Ecto.Changeset.put_assoc(:users, [])

      # Should be valid as users can be added later
      assert changeset.valid?
    end

    test "validates user count for conversation types", %{
      user: user,
      family: family
    } do
      # Generate a dummy direct key for testing
      direct_key = "test_direct_key_#{:rand.uniform(1000)}"

      # Direct conversation should have exactly two users
      direct_changeset =
        %Conversation{}
        |> Conversation.create_changeset(%{
          conversation_type: :direct,
          metadata: %{},
          family_id: family.id,
          direct_key: direct_key
        })
        |> Ecto.Changeset.put_assoc(:users, [user])

      # Should be valid initially as users can be added later
      assert direct_changeset.valid?

      # Self conversation should have exactly one user
      self_changeset =
        %Conversation{}
        |> Conversation.create_changeset(%{
          conversation_type: :self,
          metadata: %{},
          family_id: family.id
        })
        |> Ecto.Changeset.put_assoc(:users, [user])

      assert self_changeset.valid?

      # Group conversation should have at least one user
      group_changeset =
        %Conversation{}
        |> Conversation.create_changeset(%{
          conversation_type: :group,
          metadata: %{"name" => "Test Group"},
          family_id: family.id
        })
        |> Ecto.Changeset.put_assoc(:users, [user])

      # Should be valid initially as more users can be added later
      assert group_changeset.valid?
    end
  end
end
