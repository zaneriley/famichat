defmodule Famichat.Chat.ConversationAccessTest do
  use Famichat.DataCase, async: true

  alias Famichat.Chat.{ConversationAccess, ConversationService}
  alias Famichat.ChatFixtures

  setup do
    family = ChatFixtures.family_fixture()
    member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    second_member =
      ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    outsider = ChatFixtures.user_fixture()

    {:ok, direct_conversation} =
      ConversationService.create_direct_conversation(
        member.id,
        second_member.id
      )

    family_conversation =
      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :family
      })

    %{
      member: member,
      outsider: outsider,
      direct_conversation: direct_conversation,
      family_conversation: family_conversation
    }
  end

  describe "authorize/3" do
    test "allows send_message for direct conversation participant", %{
      member: member,
      direct_conversation: direct_conversation
    } do
      assert :ok =
               ConversationAccess.authorize(
                 direct_conversation,
                 member.id,
                 :send_message
               )
    end

    test "returns conversation_not_found for missing conversation id", %{
      member: member
    } do
      assert {:error, :conversation_not_found} =
               ConversationAccess.authorize(
                 Ecto.UUID.generate(),
                 member.id,
                 :send_message
               )
    end

    test "returns user_not_found for invalid user input", %{
      direct_conversation: direct_conversation
    } do
      assert {:error, :user_not_found} =
               ConversationAccess.authorize(
                 direct_conversation,
                 123,
                 :send_message
               )
    end

    test "returns not_participant for non-member on direct conversation", %{
      outsider: outsider,
      direct_conversation: direct_conversation
    } do
      assert {:error, :not_participant} =
               ConversationAccess.authorize(
                 direct_conversation,
                 outsider.id,
                 :send_message
               )
    end

    test "returns wrong_family for outsider on family conversation", %{
      outsider: outsider,
      family_conversation: family_conversation
    } do
      assert {:error, :wrong_family} =
               ConversationAccess.authorize(
                 family_conversation,
                 outsider.id,
                 :send_message
               )
    end

    test "returns unknown_action for unsupported actions", %{
      member: member,
      direct_conversation: direct_conversation
    } do
      assert {:error, :unknown_action} =
               ConversationAccess.authorize(
                 direct_conversation,
                 member.id,
                 :delete_conversation
               )
    end
  end

  describe "member?/2" do
    test "returns true for participant and false for outsider", %{
      member: member,
      outsider: outsider,
      direct_conversation: direct_conversation
    } do
      assert ConversationAccess.member?(direct_conversation.id, member.id)
      refute ConversationAccess.member?(direct_conversation.id, outsider.id)
    end

    test "returns false for missing conversation", %{member: member} do
      refute ConversationAccess.member?(Ecto.UUID.generate(), member.id)
    end
  end
end
