defmodule Famichat.Chat.ConversationChangesetTest do
  use Famichat.DataCase

  alias Famichat.Chat.Conversation
  import Famichat.ChatFixtures

  describe "conversation changesets" do
    setup do
      family = family_fixture()
      user1 = user_fixture(%{family_id: family.id})
      user2 = user_fixture(%{family_id: family.id})

      {:ok, family: family, user1: user1, user2: user2}
    end

    test "create_changeset enforces required fields", %{family: family} do
      # Missing family_id
      changeset = Conversation.create_changeset(%Conversation{}, %{conversation_type: :direct})
      assert "can't be blank" in errors_on(changeset).family_id

      # Missing conversation_type still gets default :direct
      # but fails direct_key validation since direct conversations need a key
      changeset = Conversation.create_changeset(%Conversation{}, %{family_id: family.id})
      errors = errors_on(changeset)
      refute changeset.valid?
      assert errors[:direct_key] == ["must be set for direct conversations"]

      # Valid changeset for direct conversation
      changeset = Conversation.create_changeset(%Conversation{}, %{
        family_id: family.id,
        conversation_type: :direct,
        direct_key: "some-key"
      })
      assert changeset.valid?

      # Test with explicit nil conversation_type to verify it's required
      changeset = Conversation.create_changeset(%Conversation{}, %{
        family_id: family.id,
        conversation_type: nil
      })
      errors = errors_on(changeset)
      refute changeset.valid?
      assert errors[:conversation_type] == ["can't be blank"]
    end

    test "create_changeset validates direct conversation", %{family: family} do
      # Direct conversation without direct_key
      changeset = Conversation.create_changeset(%Conversation{}, %{
        family_id: family.id,
        conversation_type: :direct
      })
      assert "must be set for direct conversations" in errors_on(changeset).direct_key

      # Direct conversation with direct_key
      changeset = Conversation.create_changeset(%Conversation{}, %{
        family_id: family.id,
        conversation_type: :direct,
        direct_key: "some-unique-key"
      })
      assert changeset.valid?
    end

    test "create_changeset validates group conversation metadata", %{family: family} do
      # Group conversation without name
      changeset = Conversation.create_changeset(%Conversation{}, %{
        family_id: family.id,
        conversation_type: :group,
        metadata: %{}
      })
      assert "group conversations require a name" in errors_on(changeset).metadata

      # Group conversation with name
      changeset = Conversation.create_changeset(%Conversation{}, %{
        family_id: family.id,
        conversation_type: :group,
        metadata: %{"name" => "Test Group"}
      })
      assert changeset.valid?
    end

    test "create_changeset validates letter conversation metadata", %{family: family} do
      # Letter conversation without subject
      changeset = Conversation.create_changeset(%Conversation{}, %{
        family_id: family.id,
        conversation_type: :letter,
        metadata: %{}
      })
      assert "letters require a subject" in errors_on(changeset).metadata

      # Letter conversation with subject
      changeset = Conversation.create_changeset(%Conversation{}, %{
        family_id: family.id,
        conversation_type: :letter,
        metadata: %{"subject" => "Test Subject"}
      })
      assert changeset.valid?
    end

    test "create_changeset handles hidden_by_users field", %{family: family, user1: user1} do
      changeset = Conversation.create_changeset(%Conversation{}, %{
        family_id: family.id,
        conversation_type: :direct,
        direct_key: "some-key",
        hidden_by_users: [user1.id]
      })
      assert changeset.valid?
      assert changeset.changes.hidden_by_users == [user1.id]
    end

    test "update_changeset prevents changing conversation_type", %{family: family} do
      # Create a conversation first
      conversation = conversation_fixture(%{family_id: family.id, conversation_type: :direct})

      # Try to update the conversation_type
      changeset = Conversation.update_changeset(conversation, %{
        conversation_type: :group,
        metadata: %{"name" => "New Group"}
      })

      # Verify the conversation_type is not changed
      assert changeset.changes[:conversation_type] == nil

      # Verify other changes are applied
      assert changeset.changes[:metadata] == %{"name" => "New Group"}
    end

    test "update_changeset allows updating metadata", %{family: family} do
      conversation = conversation_fixture(%{family_id: family.id, conversation_type: :group, metadata: %{"name" => "Original Name"}})

      changeset = Conversation.update_changeset(conversation, %{
        metadata: %{"name" => "Updated Name"}
      })

      assert changeset.valid?
      assert changeset.changes.metadata == %{"name" => "Updated Name"}
    end

    test "update_changeset allows updating hidden_by_users", %{family: family, user1: user1, user2: user2} do
      conversation = conversation_fixture(%{family_id: family.id})

      # Add user1 to hidden_by_users
      changeset = Conversation.update_changeset(conversation, %{
        hidden_by_users: [user1.id]
      })

      assert changeset.valid?
      assert changeset.changes.hidden_by_users == [user1.id]

      # Update with user2 (replacing user1)
      updated_conversation = Ecto.Changeset.apply_changes(changeset)
      changeset = Conversation.update_changeset(updated_conversation, %{
        hidden_by_users: [user2.id]
      })

      assert changeset.valid?
      assert changeset.changes.hidden_by_users == [user2.id]
    end

    test "validate_user_count validates correct user counts", %{user1: user1, user2: user2} do
      # Direct conversation with 2 users
      changeset =
        %Conversation{}
        |> Conversation.create_changeset(%{conversation_type: :direct, family_id: user1.family_id, direct_key: "key"})
        |> Ecto.Changeset.put_assoc(:users, [user1, user2])
        |> Conversation.validate_user_count()

      assert changeset.valid?

      # Direct conversation with 1 user
      changeset =
        %Conversation{}
        |> Conversation.create_changeset(%{conversation_type: :direct, family_id: user1.family_id, direct_key: "key"})
        |> Ecto.Changeset.put_assoc(:users, [user1])
        |> Conversation.validate_user_count()

      assert "direct conversations require exactly 2 users" in errors_on(changeset).users

      # Self conversation with 1 user
      changeset =
        %Conversation{}
        |> Conversation.create_changeset(%{conversation_type: :self, family_id: user1.family_id})
        |> Ecto.Changeset.put_assoc(:users, [user1])
        |> Conversation.validate_user_count()

      assert changeset.valid?

      # Self conversation with 2 users
      changeset =
        %Conversation{}
        |> Conversation.create_changeset(%{conversation_type: :self, family_id: user1.family_id})
        |> Ecto.Changeset.put_assoc(:users, [user1, user2])
        |> Conversation.validate_user_count()

      assert "self conversations require exactly 1 user" in errors_on(changeset).users

      # Group conversation with 3 users
      user3 = user_fixture(%{family_id: user1.family_id})
      changeset =
        %Conversation{}
        |> Conversation.create_changeset(%{conversation_type: :group, family_id: user1.family_id, metadata: %{"name" => "Group"}})
        |> Ecto.Changeset.put_assoc(:users, [user1, user2, user3])
        |> Conversation.validate_user_count()

      assert changeset.valid?
    end

    test "validate_user_count allows empty users list", %{family: family} do
      changeset =
        %Conversation{}
        |> Conversation.create_changeset(%{conversation_type: :direct, family_id: family.id, direct_key: "key"})
        |> Ecto.Changeset.put_assoc(:users, [])
        |> Conversation.validate_user_count()

      assert changeset.valid?
    end
  end
end
