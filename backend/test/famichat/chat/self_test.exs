defmodule Famichat.Chat.SelfTest do
  use Famichat.DataCase, async: true

  import Ecto.Query

  alias Famichat.Accounts.HouseholdMembership
  alias Famichat.Chat.{Conversation, ConversationParticipant, Self}
  alias Famichat.ChatFixtures
  alias Famichat.Repo

  describe "get_or_create/1" do
    test "creates a self conversation with one participant when missing" do
      family = ChatFixtures.family_fixture()
      user = ChatFixtures.user_fixture(%{family_id: family.id})

      assert {:ok, conversation} = Self.get_or_create(user.id)
      assert conversation.conversation_type == :self
      assert conversation.family_id == family.id
      assert Enum.map(conversation.explicit_users, & &1.id) == [user.id]

      participant_ids =
        from(cp in ConversationParticipant,
          where: cp.conversation_id == ^conversation.id,
          select: cp.user_id
        )
        |> Repo.all()

      assert participant_ids == [user.id]
    end

    test "returns existing self conversation without creating duplicates" do
      family = ChatFixtures.family_fixture()
      user = ChatFixtures.user_fixture(%{family_id: family.id})

      assert {:ok, first} = Self.get_or_create(user.id)
      assert {:ok, second} = Self.get_or_create(user.id)
      assert first.id == second.id

      self_conversation_ids =
        from(c in Conversation,
          join: cp in ConversationParticipant,
          on: cp.conversation_id == c.id,
          where:
            c.conversation_type == :self and c.family_id == ^family.id and
              cp.user_id == ^user.id,
          select: c.id
        )
        |> Repo.all()
        |> Enum.uniq()

      assert self_conversation_ids == [first.id]
    end

    test "returns invalid_self_conversation when one self conversation has multiple participants" do
      family = ChatFixtures.family_fixture()
      user = ChatFixtures.user_fixture(%{family_id: family.id})
      intruder = ChatFixtures.user_fixture(%{family_id: family.id})

      conversation =
        ChatFixtures.conversation_fixture(%{
          family_id: family.id,
          conversation_type: :self,
          user1: user
        })

      %ConversationParticipant{}
      |> ConversationParticipant.changeset(%{
        conversation_id: conversation.id,
        user_id: intruder.id
      })
      |> Repo.insert!()

      assert {:error, :invalid_self_conversation} = Self.get_or_create(user.id)
    end

    test "returns invalid_self_conversation when duplicate self conversations exist" do
      family = ChatFixtures.family_fixture()
      user = ChatFixtures.user_fixture(%{family_id: family.id})

      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :self,
        user1: user
      })

      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :self,
        user1: user
      })

      assert {:error, :invalid_self_conversation} = Self.get_or_create(user.id)
    end

    test "returns not_in_family when user has no family membership" do
      family = ChatFixtures.family_fixture()
      user = ChatFixtures.user_fixture(%{family_id: family.id})

      from(m in HouseholdMembership, where: m.user_id == ^user.id)
      |> Repo.delete_all()

      assert {:error, :not_in_family} = Self.get_or_create(user.id)
    end

    test "returns user_not_found for unknown user id" do
      assert {:error, :user_not_found} =
               Self.get_or_create(Ecto.UUID.generate())
    end
  end
end
