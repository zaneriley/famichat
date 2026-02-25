defmodule Famichat.Chat.ConversationServiceTest do
  use Famichat.DataCase

  alias Famichat.Chat.{
    Conversation,
    ConversationParticipant,
    ConversationService,
    GroupConversationPrivileges
  }

  alias Famichat.Accounts.HouseholdMembership
  alias Famichat.Repo
  import Famichat.ChatFixtures
  import Ecto.Query
  require Logger

  @contention_signal_timeout 1_000

  describe "create_direct_conversation/2 self conversations" do
    test "creates a self conversation if not exists" do
      user = user_fixture()

      # Create a self conversation
      {:ok, conversation} =
        ConversationService.create_direct_conversation(user.id, user.id)

      # Implementation uses direct instead of self
      assert conversation.conversation_type == :direct
      membership = Repo.get_by!(HouseholdMembership, user_id: user.id)
      assert conversation.family_id == membership.family_id
      assert Enum.any?(conversation.explicit_users, fn u -> u.id == user.id end)
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

    test "same-user direct conversation remains :direct with one participant row" do
      user = user_fixture()

      {:ok, conversation} =
        ConversationService.create_direct_conversation(user.id, user.id)

      assert conversation.conversation_type == :direct

      assert conversation.direct_key ==
               Conversation.compute_direct_key(
                 user.id,
                 user.id,
                 conversation.family_id
               )

      participant_ids =
        from(p in ConversationParticipant,
          where: p.conversation_id == ^conversation.id,
          select: p.user_id
        )
        |> Repo.all()

      assert participant_ids == [user.id]

      member_ids =
        conversation
        |> ConversationService.list_members()
        |> Enum.map(& &1.id)

      assert member_ids == [user.id]
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

      user_ids = Enum.map(conversation.explicit_users, & &1.id)
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
        Conversation.compute_direct_key(
          user1.id,
          user2.id,
          conversation.family_id
        )

      query =
        from c in Conversation,
          where: c.direct_key == ^direct_key and c.conversation_type == :direct

      # Count the conversations
      conversations = Repo.all(query)

      # Assert there's only one conversation with this direct_key
      assert length(conversations) == 1

      # Verify user associations
      assert length(conversation.explicit_users) == 2
      user_ids = Enum.map(conversation.explicit_users, & &1.id)
      assert user1.id in user_ids
      assert user2.id in user_ids
    end

    test "users shared across two families get distinct direct conversations",
         %{
           family: primary_family,
           user1: user1,
           user2: user2
         } do
      {:ok, conversation_one} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      assert conversation_one.family_id == primary_family.id

      other_family = family_fixture()
      membership_fixture(user1, other_family)
      membership_fixture(user2, other_family)

      primary_membership_user1 =
        Repo.get_by!(
          HouseholdMembership,
          user_id: user1.id,
          family_id: primary_family.id
        )

      primary_membership_user2 =
        Repo.get_by!(
          HouseholdMembership,
          user_id: user2.id,
          family_id: primary_family.id
        )

      Repo.delete!(primary_membership_user1)
      Repo.delete!(primary_membership_user2)

      {:ok, conversation_two} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      assert conversation_two.family_id == other_family.id
      refute conversation_two.id == conversation_one.id
      refute conversation_two.direct_key == conversation_one.direct_key
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

  describe "membership helpers" do
    test "list_user_conversations includes family conversations via implicit membership" do
      family = family_fixture()
      user = user_fixture(%{family_id: family.id})
      _other = user_fixture(%{family_id: family.id})
      conversation_fixture(%{conversation_type: :family, family_id: family.id})

      assert {:ok, conversations} =
               ConversationService.list_user_conversations(user.id)

      assert Enum.any?(conversations, &(&1.conversation_type == :family))
    end

    test "list_members includes explicit participants for direct conversations" do
      conv = conversation_fixture(%{conversation_type: :direct})
      members = ConversationService.list_members(conv)

      assert Enum.count(members) == 2
      assert Enum.all?(members, &match?(%Famichat.Accounts.User{}, &1))
    end

    test "list_members includes implicit family members for family conversations" do
      family = family_fixture()
      member = user_fixture(%{family_id: family.id})
      _other = user_fixture(%{family_id: family.id})

      conv =
        conversation_fixture(%{
          conversation_type: :family,
          family_id: family.id
        })

      member_ids =
        conv
        |> ConversationService.list_members()
        |> Enum.map(& &1.id)

      assert member.id in member_ids
    end

    test "get_recipient_ids returns user ids for both membership models" do
      direct = conversation_fixture(%{conversation_type: :direct})
      family = family_fixture()
      family_member = user_fixture(%{family_id: family.id})

      family_conversation =
        conversation_fixture(%{
          conversation_type: :family,
          family_id: family.id
        })

      direct_recipient_ids = ConversationService.get_recipient_ids(direct)

      family_recipient_ids =
        ConversationService.get_recipient_ids(family_conversation)

      assert Enum.count(direct_recipient_ids) == 2
      assert family_member.id in family_recipient_ids
      assert Enum.all?(family_recipient_ids, &is_binary/1)
    end
  end

  describe "list_user_conversations/1" do
    test "returns direct conversations for a given user" do
      family = family_fixture()
      user1 = user_fixture(%{family_id: family.id})
      user2 = user_fixture(%{family_id: family.id})

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
      group_creator =
        group_conversation
        |> Repo.preload(:explicit_users)
        |> Map.fetch!(:explicit_users)
        |> hd()

      # The admin_user defined in the setup is used for tests that require
      # *an* admin to perform actions. If this admin_user is not the
      # group_creator, we make them an admin of this group_conversation
      # so they can perform administrative actions in other tests.
      if admin_user.id != group_creator.id do
        add_group_participant!(group_conversation.id, admin_user.id)

        {:ok, _} =
          ConversationService.assign_admin(
            group_conversation.id,
            admin_user.id,
            # The creator (original admin) grants this
            group_creator.id
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
      # Use the actual creator from the fixture
      group_creator: group_creator,
      group_conversation: group_conversation
    } do
      # Check if the group creator (from the fixture) has admin privileges
      {:ok, is_admin} =
        ConversationService.admin?(group_conversation.id, group_creator.id)

      assert is_admin,
             "The creator of the group conversation should be an admin. Creator ID: #{group_creator.id}"
    end

    test "prevents removing the last admin from a group", %{
      # The actual admin of this specific conversation
      group_creator: group_creator,
      group_conversation: group_conversation,
      # The admin performing the action (could be group_creator or another admin)
      admin_user: admin_user
    } do
      # Ensure the action is performed by an admin (admin_user is now guaranteed to be one for this group)
      # The user whose privilege is being changed is the group_creator (the last admin)
      {:error, :last_admin} =
        ConversationService.assign_member(
          group_conversation.id,
          # Target the actual last admin
          group_creator.id,
          # Action performed by an admin
          admin_user.id
        )

      # Try to remove the only admin's privileges
      # Note: remove_privilege can be called by the user themselves or an admin.
      # If admin_user is the group_creator, this is self-removal.
      # If admin_user is different, it's removal by another admin.
      # The critical part is that group_creator is the target.
      {:error, :last_admin} =
        ConversationService.remove_privilege(
          group_conversation.id,
          # Target the actual last admin
          group_creator.id,
          # Action performed by an admin (or nil if self-removal)
          admin_user.id
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
      add_group_participant!(group_conversation.id, member_user.id)
      add_group_participant!(group_conversation.id, other_member.id)

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

    test "rejects assigning privileges to users outside the conversation family",
         %{
           group_conversation: group_conversation,
           admin_user: admin_user
         } do
      outsider_family = family_fixture()
      outsider_user = user_fixture(%{family_id: outsider_family.id})

      assert {:error, :family_mismatch} =
               ConversationService.assign_admin(
                 group_conversation.id,
                 outsider_user.id,
                 admin_user.id
               )

      assert {:error, :family_mismatch} =
               ConversationService.assign_member(
                 group_conversation.id,
                 outsider_user.id,
                 admin_user.id
               )

      refute Repo.get_by(GroupConversationPrivileges,
               conversation_id: group_conversation.id,
               user_id: outsider_user.id
             )
    end

    test "rejects assigning privileges to non-participants", %{
      group_conversation: group_conversation,
      member_user: member_user,
      admin_user: admin_user
    } do
      assert {:error, :not_participant} =
               ConversationService.assign_admin(
                 group_conversation.id,
                 member_user.id,
                 admin_user.id
               )

      assert {:error, :not_participant} =
               ConversationService.assign_member(
                 group_conversation.id,
                 member_user.id,
                 admin_user.id
               )

      refute Repo.get_by(GroupConversationPrivileges,
               conversation_id: group_conversation.id,
               user_id: member_user.id
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
      add_group_participant!(group_conversation.id, member_user.id)

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
      add_group_participant!(group_conversation.id, member_user.id)
      add_group_participant!(group_conversation.id, other_member.id)

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

    test "assign_admin re-checks grantor authority after lock contention", %{
      family: family,
      admin_user: admin_user
    } do
      {group_conversation, second_admin} =
        create_group_with_two_admins!(family, admin_user)

      target_user = user_fixture(%{family_id: family.id, role: :member})
      add_group_participant!(group_conversation.id, target_user.id)

      parent = self()

      blocker =
        start_grantor_demotion_blocker(
          parent,
          group_conversation.id,
          admin_user.id,
          second_admin.id,
          :grantor_demoted_uncommitted
        )

      assert_receive :grantor_demoted_uncommitted, @contention_signal_timeout

      grant_task =
        Task.async(fn ->
          ConversationService.assign_admin(
            group_conversation.id,
            target_user.id,
            admin_user.id
          )
        end)

      send(blocker.pid, :commit)

      assert {:ok, :ok} = Task.await(blocker)
      assert {:error, :not_admin} = Task.await(grant_task)

      {:ok, target_is_admin?} =
        ConversationService.admin?(group_conversation.id, target_user.id)

      refute target_is_admin?
    end

    test "assign_member re-checks grantor authority after lock contention", %{
      family: family,
      admin_user: admin_user
    } do
      {group_conversation, second_admin} =
        create_group_with_two_admins!(family, admin_user)

      target_user = user_fixture(%{family_id: family.id, role: :member})
      add_group_participant!(group_conversation.id, target_user.id)

      {:ok, _} =
        ConversationService.assign_admin(
          group_conversation.id,
          target_user.id,
          second_admin.id
        )

      parent = self()

      blocker =
        start_grantor_demotion_blocker(
          parent,
          group_conversation.id,
          admin_user.id,
          second_admin.id,
          :grantor_demoted_uncommitted_assign_member
        )

      assert_receive :grantor_demoted_uncommitted_assign_member,
                     @contention_signal_timeout

      demote_task =
        Task.async(fn ->
          ConversationService.assign_member(
            group_conversation.id,
            target_user.id,
            admin_user.id
          )
        end)

      send(blocker.pid, :commit)

      assert {:ok, :ok} = Task.await(blocker)
      assert {:error, :not_admin} = Task.await(demote_task)

      {:ok, target_is_admin?} =
        ConversationService.admin?(group_conversation.id, target_user.id)

      assert target_is_admin?
    end

    test "remove_privilege rejects non-admin removal attempts with existing target privilege",
         %{
           group_conversation: group_conversation,
           admin_user: admin_user,
           member_user: member_user,
           other_member: other_member
         } do
      add_group_participant!(group_conversation.id, member_user.id)
      add_group_participant!(group_conversation.id, other_member.id)

      {:ok, _} =
        ConversationService.assign_member(
          group_conversation.id,
          member_user.id,
          admin_user.id
        )

      {:ok, _} =
        ConversationService.assign_member(
          group_conversation.id,
          other_member.id,
          admin_user.id
        )

      assert {:error, :not_admin} =
               ConversationService.remove_privilege(
                 group_conversation.id,
                 other_member.id,
                 member_user.id
               )

      assert Repo.get_by(GroupConversationPrivileges,
               conversation_id: group_conversation.id,
               user_id: other_member.id,
               role: :member
             )
    end

    test "concurrent admin self-removals cannot orphan a group", %{
      family: family,
      admin_user: admin_user
    } do
      Enum.each(1..5, fn _iteration ->
        {group_conversation, second_admin} =
          create_group_with_two_admins!(family, admin_user)

        parent = self()

        task1 =
          Task.async(fn ->
            send(parent, {:ready, :admin1, self()})

            receive do
              :go ->
                ConversationService.remove_privilege(
                  group_conversation.id,
                  admin_user.id,
                  admin_user.id
                )
            end
          end)

        task2 =
          Task.async(fn ->
            send(parent, {:ready, :admin2, self()})

            receive do
              :go ->
                ConversationService.remove_privilege(
                  group_conversation.id,
                  second_admin.id,
                  second_admin.id
                )
            end
          end)

        assert_receive {:ready, :admin1, task1_pid}, @contention_signal_timeout
        assert_receive {:ready, :admin2, task2_pid}, @contention_signal_timeout
        send(task1_pid, :go)
        send(task2_pid, :go)

        results = [Task.await(task1), Task.await(task2)]

        success_count =
          Enum.count(results, fn
            {:ok, _} -> true
            _ -> false
          end)

        assert success_count == 1
        assert Enum.any?(results, &match?({:error, :last_admin}, &1))

        admin_count =
          Repo.aggregate(
            from(g in GroupConversationPrivileges,
              where:
                g.conversation_id == ^group_conversation.id and
                  g.role == :admin
            ),
            :count,
            :id
          )

        assert admin_count == 1
      end)
    end
  end

  defp start_grantor_demotion_blocker(
         parent,
         conversation_id,
         grantor_id,
         demoted_by_id,
         ready_message
       ) do
    Task.async(fn ->
      Repo.transaction(fn ->
        lock_group_privileges(conversation_id)
        demote_privilege!(conversation_id, grantor_id, demoted_by_id)
        send(parent, ready_message)

        receive do
          :commit -> :ok
        end
      end)
    end)
  end

  defp lock_group_privileges(conversation_id) do
    Repo.all(
      from g in GroupConversationPrivileges,
        where: g.conversation_id == ^conversation_id,
        select: g.id,
        lock: "FOR UPDATE"
    )
  end

  defp demote_privilege!(conversation_id, user_id, demoted_by_id) do
    grantor_privilege =
      Repo.get_by!(
        GroupConversationPrivileges,
        conversation_id: conversation_id,
        user_id: user_id
      )

    {:ok, _} =
      grantor_privilege
      |> Ecto.Changeset.change(
        role: :member,
        granted_by_id: demoted_by_id
      )
      |> Repo.update()
  end

  defp create_group_with_two_admins!(family, primary_admin) do
    group_conversation =
      conversation_fixture(%{
        family_id: family.id,
        conversation_type: :group,
        metadata: %{"name" => "Race Group"},
        user1: primary_admin
      })

    second_admin = user_fixture(%{family_id: family.id, role: :admin})
    add_group_participant!(group_conversation.id, second_admin.id)

    {:ok, _} =
      ConversationService.assign_admin(
        group_conversation.id,
        second_admin.id,
        primary_admin.id
      )

    {group_conversation, second_admin}
  end

  defp add_group_participant!(conversation_id, user_id) do
    %ConversationParticipant{}
    |> ConversationParticipant.changeset(%{
      conversation_id: conversation_id,
      user_id: user_id
    })
    |> Repo.insert(on_conflict: :nothing)
  end
end
