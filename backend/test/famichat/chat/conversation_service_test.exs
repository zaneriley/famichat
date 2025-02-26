defmodule Famichat.Chat.ConversationServiceTest do
  use Famichat.DataCase

  alias Famichat.Chat.{Conversation, ConversationService}
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

      assert conversation.conversation_type == :direct # Implementation uses direct instead of self
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

      :ok = :telemetry.attach_many(
        handler_name,
        [
          [:famichat, :conversation_service, :create_direct_conversation, :start],
          [:famichat, :conversation_service, :create_direct_conversation, :stop],
          [:famichat, :conversation_service, :create_direct_conversation, :exception]
        ],
        fn event_name, measurements, metadata, _ ->
          send(parent, {:telemetry_event, ref, event_name, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_name)
      end)

      {:ok, family: family, user1: user1, user2: user2, ref: ref}
    end

    test "creates a direct conversation for users in the same family", %{family: family, user1: user1, user2: user2} do
      {:ok, conversation} =
        ConversationService.create_direct_conversation(user1.id, user2.id)

      assert conversation.conversation_type == :direct
      assert conversation.family_id == family.id

      user_ids = Enum.map(conversation.users, & &1.id)
      assert user1.id in user_ids
      assert user2.id in user_ids
    end

    test "returns existing direct conversation when already created", %{user1: user1, user2: user2} do
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
      assert_receive {:telemetry_event, ^ref, [:famichat, :conversation_service, :create_direct_conversation, :stop],
                     _measurements, metadata}, 500
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
      assert_receive {:telemetry_event, ^ref, [:famichat, :conversation_service, :create_direct_conversation, :stop],
                     _measurements, metadata}, 500
      assert metadata.result == "error"
    end

    test "create_direct_conversation/2 does not allow duplicate records", %{user1: user1, user2: user2} do
      {:ok, conversation} = ConversationService.create_direct_conversation(user1.id, user2.id)

      # Try to create the same conversation again
      {:ok, conversation2} = ConversationService.create_direct_conversation(user1.id, user2.id)

      # Assert that we got the same conversation back
      assert conversation.id == conversation2.id

      # Query for direct conversations with the given direct_key
      direct_key = Conversation.compute_direct_key(user1.id, user2.id, user1.family_id)

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

    test "create_direct_conversation/2 emits telemetry events for success case", %{user1: user1, user2: user2, ref: ref} do
      {:ok, _conversation} = ConversationService.create_direct_conversation(user1.id, user2.id)

      # Assert telemetry stop event is received
      assert_receive {:telemetry_event, ^ref, [:famichat, :conversation_service, :create_direct_conversation, :stop],
                     measurements, metadata}, 500

      # Verify measurements contain execution time
      assert is_map(measurements)
      assert is_map(metadata)

      # Verify execution time stays within performance budget
      assert is_number(measurements.duration)
      assert measurements.duration < 500_000_000 # 500ms in nanoseconds

      # Ensure user IDs are included in metadata
      assert metadata.user1_id
      assert metadata.user2_id

      # Ensure the result is captured in metadata
      assert metadata.result == "created"
    end

    test "create_direct_conversation/2 emits telemetry events for error case", %{user1: user1, ref: ref} do
      # Try to create a conversation with a non-existent user
      {:error, _reason} = ConversationService.create_direct_conversation(user1.id, Ecto.UUID.generate())

      # Assert telemetry stop event is received
      assert_receive {:telemetry_event, ^ref, [:famichat, :conversation_service, :create_direct_conversation, :stop],
                     measurements, metadata}, 500

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
end
