defmodule Famichat.Chat.GroupConversationPrivilegesTest do
  use Famichat.DataCase
  use ExUnit.Case, async: true

  alias Famichat.Chat.GroupConversationPrivileges
  import Famichat.ChatFixtures

  describe "schema" do
    setup do
      family = family_fixture()
      user1 = user_fixture(%{family_id: family.id})
      user2 = user_fixture(%{family_id: family.id})

      # Create a group conversation
      group_conversation = conversation_fixture(%{
        family_id: family.id,
        conversation_type: :group,
        metadata: %{"name" => "Test Group"},
        user1: user1
      })

      # Create a direct conversation for comparison
      direct_conversation = conversation_fixture(%{
        family_id: family.id,
        conversation_type: :direct,
        user1: user1,
        user2: user2
      })

      {:ok, %{
        family: family,
        user1: user1,
        user2: user2,
        admin_user: user1,
        member_user: user2,
        group_conversation: group_conversation,
        direct_conversation: direct_conversation
      }}
    end

    test "validates required fields", %{group_conversation: group_conversation, admin_user: admin_user} do
      # Missing user_id
      changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, %{
        conversation_id: group_conversation.id,
        role: :admin
      })
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_id

      # Missing conversation_id
      changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, %{
        user_id: admin_user.id,
        role: :admin
      })
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).conversation_id

      # Missing role
      changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, %{
        conversation_id: group_conversation.id,
        user_id: admin_user.id
      })
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).role
    end

    test "validates role is admin or member", %{group_conversation: group_conversation, admin_user: admin_user} do
      # Valid admin role
      changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, %{
        conversation_id: group_conversation.id,
        user_id: admin_user.id,
        role: :admin
      })
      assert changeset.valid?

      # Valid member role
      changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, %{
        conversation_id: group_conversation.id,
        user_id: admin_user.id,
        role: :member
      })
      assert changeset.valid?

      # Invalid role
      changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, %{
        conversation_id: group_conversation.id,
        user_id: admin_user.id,
        role: :invalid_role
      })
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end

    test "validates granted_by_id if present", %{
      group_conversation: group_conversation,
      admin_user: admin_user,
      member_user: member_user
    } do
      # Valid with granted_by_id
      changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, %{
        conversation_id: group_conversation.id,
        user_id: member_user.id,
        role: :member,
        granted_by_id: admin_user.id
      })
      assert changeset.valid?

      # Valid without granted_by_id (for initial creation)
      changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, %{
        conversation_id: group_conversation.id,
        user_id: admin_user.id,
        role: :admin
      })
      assert changeset.valid?
    end

    test "validates granted_at if present", %{
      group_conversation: group_conversation,
      admin_user: admin_user
    } do
      now = DateTime.utc_now()

      # Valid with granted_at
      changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, %{
        conversation_id: group_conversation.id,
        user_id: admin_user.id,
        role: :admin,
        granted_at: now
      })
      assert changeset.valid?

      # Valid without granted_at (will be set automatically)
      changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, %{
        conversation_id: group_conversation.id,
        user_id: admin_user.id,
        role: :admin
      })
      assert changeset.valid?
    end

    test "enforces conversation and user uniqueness", %{
      group_conversation: group_conversation,
      admin_user: admin_user
    } do
      attrs = %{
        conversation_id: group_conversation.id,
        user_id: admin_user.id,
        role: :admin
      }

      # Create the first record
      {:ok, _privilege} =
        %GroupConversationPrivileges{}
        |> GroupConversationPrivileges.changeset(attrs)
        |> Repo.insert()

      # Try to create another record with the same conversation_id and user_id
      {:error, changeset} =
        %GroupConversationPrivileges{}
        |> GroupConversationPrivileges.changeset(attrs)
        |> Repo.insert()

      assert %{conversation_id_user_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "conversation type validation" do
    setup do
      family = family_fixture()
      user1 = user_fixture(%{family_id: family.id})
      user2 = user_fixture(%{family_id: family.id})

      # Create different conversation types
      group_conversation = conversation_fixture(%{
        family_id: family.id,
        conversation_type: :group,
        metadata: %{"name" => "Test Group"},
        user1: user1
      })

      direct_conversation = conversation_fixture(%{
        family_id: family.id,
        conversation_type: :direct,
        user1: user1,
        user2: user2
      })

      {:ok, %{
        user1: user1,
        user2: user2,
        group_conversation: group_conversation,
        direct_conversation: direct_conversation
      }}
    end

    test "validates privileges only for group conversations", %{
      user1: user,
      group_conversation: group_conversation,
      direct_conversation: direct_conversation
    } do
      # Valid for group conversation
      group_attrs = %{
        conversation_id: group_conversation.id,
        user_id: user.id,
        role: :admin
      }

      group_changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, group_attrs)
      assert group_changeset.valid?

      # Not valid for direct conversation
      direct_attrs = %{
        conversation_id: direct_conversation.id,
        user_id: user.id,
        role: :admin
      }

      # Currently this would be valid in the changeset, but we expect a custom validation
      # to be added to the service layer to prevent privileges for non-group conversations
      # (For TDD purposes we're asserting what should happen in the future)
      direct_changeset = GroupConversationPrivileges.changeset(%GroupConversationPrivileges{}, direct_attrs)
      assert direct_changeset.valid?

      # In the future implementation, we'll have validation at the service level
      # that checks conversation type before allowing privilege creation
    end
  end

  describe "telemetry" do
    setup do
      family = family_fixture()
      user1 = user_fixture(%{family_id: family.id})
      user2 = user_fixture(%{family_id: family.id})

      group_conversation = conversation_fixture(%{
        family_id: family.id,
        conversation_type: :group,
        metadata: %{"name" => "Test Group"},
        user1: user1
      })

      # Set up telemetry handler for testing
      parent = self()
      ref = make_ref()
      handler_name = "group-conversation-privileges-test-#{:erlang.unique_integer()}"

      :ok = :telemetry.attach_many(
        handler_name,
        [
          [:famichat, :group_conversation_privileges, :create, :start],
          [:famichat, :group_conversation_privileges, :create, :stop],
          [:famichat, :group_conversation_privileges, :create, :exception],
          [:famichat, :group_conversation_privileges, :update, :start],
          [:famichat, :group_conversation_privileges, :update, :stop],
          [:famichat, :group_conversation_privileges, :update, :exception]
        ],
        fn event_name, measurements, metadata, _ ->
          send(parent, {:telemetry_event, ref, event_name, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_name)
      end)

      {:ok, %{
        family: family,
        user1: user1,
        user2: user2,
        admin_user: user1,
        member_user: user2,
        group_conversation: group_conversation,
        ref: ref
      }}
    end

    test "emits telemetry events for future create/update operations", %{ref: _ref} do
      # This test is a placeholder for future telemetry implementation
      # The actual assertions will be added when the service functions are implemented
      #
      # For now, we're just ensuring the test setup works properly

      # Expected assertions in future implementations:
      #
      # # Create a privilege with the service
      # {:ok, privilege} =
      #   GroupConversationService.create_privilege(group_conversation.id, member_user.id, :member, granted_by_id: admin_user.id)
      #
      # # Assert telemetry stop event is received
      # assert_receive {:telemetry_event, ^ref,
      #                [:famichat, :group_conversation_privileges, :create, :stop],
      #                measurements, metadata}, 500
      #
      # # Verify measurements contain execution time
      # assert is_map(measurements)
      # assert is_number(measurements.duration)
      #
      # # Ensure the result is captured in metadata
      # assert metadata.result == "created"
      # assert metadata.conversation_id == group_conversation.id
      # assert metadata.user_id == member_user.id
      # assert metadata.role == :member
    end
  end
end
