defmodule Famichat.Chat.ConversationServiceTest do
  use Famichat.DataCase

  alias Famichat.Chat.{
    Conversation,
    ConversationService,
    GroupConversationPrivileges
  }

  alias Famichat.Repo
  import Famichat.ChatFixtures
  import Ecto.Query
  require Logger

  describe "create_direct_conversation/2 self conversations" do
    test "creates a self conversation if not exists" do
      user = user_fixture()

      # Create a self conversation
      {:ok, conversation} =
        ConversationService.create_direct_conversation(user.id, user.id)

      # Implementation uses direct instead of self
      assert conversation.conversation_type == :direct
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
    setup do
      family = family_fixture()
      user1 = user_fixture(%{family_id: family.id})
      user2 = user_fixture(%{family_id: family.id})

      # Set up telemetry handler for the span
      ref = make_ref()
      parent = self()

      # Create a unique handler name
      handler_id = System.unique_integer([:positive])
      handler_name = "test-telemetry-handler-#{handler_id}"

      :ok =
        :telemetry.attach_many(
          handler_name,
          [
            [
              :famichat,
              :conversation_service,
              :create_direct_conversation,
              :start
            ],
            [
              :famichat,
              :conversation_service,
              :create_direct_conversation,
              :stop
            ],
            [
              :famichat,
              :conversation_service,
              :create_direct_conversation,
              :exception
            ]
          ],
          fn event_name, measurements, metadata, _ ->
            send(
              parent,
              {:telemetry_event, ref, event_name, measurements, metadata}
            )
          end,
          nil
        )

      on_exit(fn ->
        :telemetry.detach(handler_name)
      end)

      {:ok, family: family, user1: user1, user2: user2, ref: ref}
    end

    test "creates a direct conversation for users in the same family", %{
      family: family,
      user1: user1,
      user2: user2
    } do
      {:ok, conversation} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      assert conversation.conversation_type == :direct
      assert conversation.family_id == family.id

      user_ids = Enum.map(conversation.users, & &1.id)
      assert user1.id in user_ids
      assert user2.id in user_ids
    end

    test "returns existing direct conversation when already created", %{
      user1: user1,
      user2: user2
    } do
      {:ok, conv1} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      {:ok, conv2} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      assert conv1.id == conv2.id
    end

    test "fails when users are not in the same family", %{ref: ref} do
      family1 = family_fixture()
      family2 = family_fixture()

      user1 = user_fixture(%{family_id: family1.id})
      user2 = user_fixture(%{family_id: family2.id})

      {:error, reason} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      assert reason == :different_families

      # Assert telemetry stop event is received
      assert_receive {:telemetry_event, ^ref,
                      [
                        :famichat,
                        :conversation_service,
                        :create_direct_conversation,
                        :stop
                      ], _measurements, metadata},
                     500

      assert metadata.result == "error"
    end

    test "fails when one user does not exist", %{ref: ref} do
      family = family_fixture()
      user = user_fixture(%{family_id: family.id})

      {:error, reason} =
        ConversationService.create_direct_conversation(
          user.id,
          Ecto.UUID.generate()
        )

      assert reason == :user_not_found

      # Assert telemetry stop event is received
      assert_receive {:telemetry_event, ^ref,
                      [
                        :famichat,
                        :conversation_service,
                        :create_direct_conversation,
                        :stop
                      ], _measurements, metadata},
                     500

      assert metadata.result == "error"
    end

    test "create_direct_conversation/2 does not allow duplicate records", %{
      user1: user1,
      user2: user2
    } do
      {:ok, conversation} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      # Try to create the same conversation again
      {:ok, conversation2} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      # Assert that we got the same conversation back
      assert conversation.id == conversation2.id

      # Query for direct conversations with the given direct_key
      direct_key =
        Conversation.compute_direct_key(user1.id, user2.id, user1.family_id)

      query =
        from c in Conversation,
          where: c.direct_key == ^direct_key and c.conversation_type == :direct

      # Count the conversations
      conversations = Repo.all(query)

      # Assert there's only one conversation with this direct_key
      assert length(conversations) == 1

      # Verify user associations
      assert length(conversation.users) == 2
      user_ids = Enum.map(conversation.users, & &1.id)
      assert user1.id in user_ids
      assert user2.id in user_ids
    end

    test "create_direct_conversation/2 emits telemetry events for success case",
         %{user1: user1, user2: user2, ref: ref} do
      {:ok, _conversation} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      # Assert telemetry stop event is received
      assert_receive {:telemetry_event, ^ref,
                      [
                        :famichat,
                        :conversation_service,
                        :create_direct_conversation,
                        :stop
                      ], measurements, metadata},
                     500

      # Verify measurements contain execution time
      assert is_map(measurements)
      assert is_map(metadata)

      # Verify execution time stays within performance budget
      assert is_number(measurements.duration)
      # 500ms in nanoseconds
      assert measurements.duration < 500_000_000

      # Ensure user IDs are included in metadata
      assert metadata.user1_id
      assert metadata.user2_id

      # Ensure the result is captured in metadata
      assert metadata.result == "created"
    end

    test "create_direct_conversation/2 emits telemetry events for error case",
         %{user1: user1, ref: ref} do
      # Try to create a conversation with a non-existent user
      {:error, _reason} =
        ConversationService.create_direct_conversation(
          user1.id,
          Ecto.UUID.generate()
        )

      # Assert telemetry stop event is received
      assert_receive {:telemetry_event, ^ref,
                      [
                        :famichat,
                        :conversation_service,
                        :create_direct_conversation,
                        :stop
                      ], measurements, metadata},
                     500

      # Verify measurements and metadata
      assert is_map(measurements)
      assert is_map(metadata)

      # Ensure the error result is captured in metadata
      assert metadata.result == "error"
    end
  end

  describe "list_user_conversations/1" do
    test "returns direct conversations for a given user" do
      user1 = user_fixture()
      user2 = user_fixture(%{family_id: user1.family_id})

      # Create a conversation between user1 and user2.
      {:ok, _conversation} =
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

  # Group Conversation Privileges Tests
  describe "group conversation privilege management" do
    setup do
      family = family_fixture()
      admin_user = user_fixture(%{family_id: family.id, role: :admin})
      member_user = user_fixture(%{family_id: family.id, role: :member})
      other_member = user_fixture(%{family_id: family.id, role: :member})

      # Create a group conversation with admin_user
      group_conversation =
        conversation_fixture(%{
          family_id: family.id,
          conversation_type: :group,
          metadata: %{"name" => "Test Group"},
          user1: admin_user
        })

      # Create a direct conversation for comparison
      direct_conversation =
        conversation_fixture(%{
          family_id: family.id,
          conversation_type: :direct,
          user1: admin_user,
          user2: member_user
        })

      # Set up telemetry handler for testing
      parent = self()
      ref = make_ref()
      handler_name = "group-privilege-test-#{:erlang.unique_integer()}"

      :ok =
        :telemetry.attach_many(
          handler_name,
          [
            [:famichat, :conversation_service, :assign_admin, :start],
            [:famichat, :conversation_service, :assign_admin, :stop],
            [:famichat, :conversation_service, :assign_admin, :exception],
            [:famichat, :conversation_service, :assign_member, :start],
            [:famichat, :conversation_service, :assign_member, :stop],
            [:famichat, :conversation_service, :assign_member, :exception],
            [:famichat, :conversation_service, :remove_privilege, :start],
            [:famichat, :conversation_service, :remove_privilege, :stop],
            [:famichat, :conversation_service, :remove_privilege, :exception],
            [:famichat, :conversation_service, :admin?, :start],
            [:famichat, :conversation_service, :admin?, :stop],
            [:famichat, :conversation_service, :admin?, :exception]
          ],
          fn event_name, measurements, metadata, _ ->
            send(
              parent,
              {:telemetry_event, ref, event_name, measurements, metadata}
            )
          end,
          nil
        )

      on_exit(fn ->
        :telemetry.detach(handler_name)
      end)

      # The group_conversation fixture now handles making its creator an admin.
      # We fetch this creator to use in tests that verify creator privileges
      # or need to target the original admin.
      group_creator = hd(Repo.preload(group_conversation, :users).users)

      # The admin_user defined in the setup is used for tests that require
      # *an* admin to perform actions. If this admin_user is not the
      # group_creator, we make them an admin of this group_conversation
      # so they can perform administrative actions in other tests.
      if admin_user.id != group_creator.id do
        {:ok, _} =
          ConversationService.assign_admin(
            group_conversation.id,
            admin_user.id,
            group_creator.id # The creator (original admin) grants this
          )
      end

      {:ok,
       %{
         family: family,
         group_creator: group_creator,
         admin_user: admin_user,
         member_user: member_user,
         other_member: other_member,
         group_conversation: group_conversation,
         direct_conversation: direct_conversation,
         ref: ref
       }}
    end

    test "auto-assigns creator as admin when creating a group conversation", %{
      group_creator: group_creator, # Use the actual creator from the fixture
      group_conversation: group_conversation
    } do
      # Check if the group creator (from the fixture) has admin privileges
      {:ok, is_admin} =
        ConversationService.admin?(group_conversation.id, group_creator.id)

      assert is_admin,
             "The creator of the group conversation should be an admin. Creator ID: #{group_creator.id}"
    end

    test "prevents removing the last admin from a group", %{
      group_creator: group_creator, # The actual admin of this specific conversation
      group_conversation: group_conversation,
      admin_user: admin_user # The admin performing the action (could be group_creator or another admin)
    } do
      # Ensure the action is performed by an admin (admin_user is now guaranteed to be one for this group)
      # The user whose privilege is being changed is the group_creator (the last admin)
      {:error, :last_admin} =
        ConversationService.assign_member(
          group_conversation.id,
          group_creator.id, # Target the actual last admin
          admin_user.id # Action performed by an admin
        )

      # Try to remove the only admin's privileges
      # Note: remove_privilege can be called by the user themselves or an admin.
      # If admin_user is the group_creator, this is self-removal.
      # If admin_user is different, it's removal by another admin.
      # The critical part is that group_creator is the target.
      {:error, :last_admin} =
        ConversationService.remove_privilege(
          group_conversation.id,
          group_creator.id, # Target the actual last admin
          admin_user.id # Action performed by an admin (or nil if self-removal)
        )
    end

    test "prevents setting privileges on non-group conversations", %{
      direct_conversation: direct_conversation,
      member_user: member_user,
      admin_user: admin_user
    } do
      # Try to assign admin on a direct conversation
      {:error, :not_group_conversation} =
        ConversationService.assign_admin(
          direct_conversation.id,
          member_user.id,
          admin_user.id
        )
    end

    test "only allows group admins to assign roles", %{
      group_conversation: group_conversation,
      other_member: other_member,
      member_user: member_user,
      admin_user: admin_user
    } do
      # First make the member_user a member of the group explicitly
      {:ok, _} =
        ConversationService.assign_member(
          group_conversation.id,
          member_user.id,
          admin_user.id
        )

      # Try to have a regular member assign admin privileges (should fail)
      {:error, :not_admin} =
        ConversationService.assign_admin(
          group_conversation.id,
          other_member.id,
          member_user.id
        )
    end

    test "admin? correctly identifies conversation admins", %{
      group_conversation: group_conversation,
      admin_user: admin_user,
      member_user: member_user,
      other_member: other_member
    } do
      # Admin status is already set up in the setup function

      # Check if admin_user is recognized as an admin
      {:ok, is_admin} =
        ConversationService.admin?(group_conversation.id, admin_user.id)

      assert is_admin

      # Check that member_user is not recognized as admin
      {:ok, is_admin} =
        ConversationService.admin?(group_conversation.id, member_user.id)

      refute is_admin

      # Check that other_member is not recognized as admin
      {:ok, is_admin} =
        ConversationService.admin?(group_conversation.id, other_member.id)

      refute is_admin
    end

    test "emits telemetry events for role operations", %{
      ref: ref,
      group_conversation: group_conversation,
      member_user: member_user,
      admin_user: admin_user
    } do
      # Assign admin privileges
      {:ok, _privilege} =
        ConversationService.assign_admin(
          group_conversation.id,
          member_user.id,
          admin_user.id
        )

      # Assert telemetry stop event is received
      assert_receive {:telemetry_event, ^ref,
                      [:famichat, :conversation_service, :assign_admin, :stop],
                      measurements, metadata},
                     500

      # Verify measurements contain execution time
      assert is_map(measurements)
      assert is_number(measurements.duration)

      # Ensure the result is captured in metadata
      assert metadata.result == "success"
      assert metadata.conversation_id == group_conversation.id
      assert metadata.target_user_id == member_user.id
      assert metadata.granted_by_id == admin_user.id
    end

    test "handles concurrent privilege updates correctly", %{
      group_conversation: group_conversation,
      admin_user: admin_user,
      member_user: member_user,
      other_member: other_member
    } do
      # Create concurrent tasks to assign privileges
      task1 =
        Task.async(fn ->
          ConversationService.assign_admin(
            group_conversation.id,
            member_user.id,
            admin_user.id
          )
        end)

      task2 =
        Task.async(fn ->
          ConversationService.assign_admin(
            group_conversation.id,
            other_member.id,
            admin_user.id
          )
        end)

      # Wait for both tasks to complete
      {:ok, _} = Task.await(task1)
      {:ok, _} = Task.await(task2)

      # Verify both users received admin privileges
      {:ok, is_admin1} =
        ConversationService.admin?(group_conversation.id, member_user.id)

      {:ok, is_admin2} =
        ConversationService.admin?(group_conversation.id, other_member.id)

      assert is_admin1
      assert is_admin2
    end
  end
end
