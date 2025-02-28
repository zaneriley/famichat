defmodule Famichat.Chat.ConversationService do
  @moduledoc """
  Provides service functions for managing conversations.

  ## Key Responsibilities

  - Direct/self conversation creation with conflict prevention
  - Family membership validation
  - Conversation listing with efficient preloading
  - Transactional integrity for conversation operations

  ## Core Concepts

  1. **Direct Conversations**: Private 1:1 chats between family members
  2. **Self Conversations**: Personal message threads (user ↔ themselves)
  3. **Family Boundary**: All participants must share the same family ID

  ## Telemetry Events

  Emits events via `[:famichat, :conversation_service, :create_direct_conversation]` with measurements:
  - `:duration` - Time taken to execute the operation
  Metadata:
  - `:result` - "created" or "error"
  - `:user1_id`, `:user2_id` - Participant IDs

  ## Example Usage

      {:ok, conv} = ConversationService.create_direct_conversation(user1_id, user2_id)
      {:ok, conversations} = ConversationService.list_user_conversations(user_id)
  """

  alias Famichat.{Repo, Chat.Conversation, Chat.User, Chat.ConversationParticipant}
  import Ecto.Query, only: [from: 2]
  require Logger

  defmodule ConversationState do
    # Internal implementation detail
    @moduledoc false
    @enforce_keys [:user1_id, :user2_id]

    @typedoc """
    Internal state container for conversation creation pipeline.

    ## Fields

    - user1_id: Initiating user ID
    - user2_id: Receiving user ID
    - users: Loaded User structs
    - family_valid?: Family consistency check
    - existing_conversation: Pre-existing conversation if found
    - error: Failure reason
    - meta: Process metadata for instrumentation
    """
    @type t :: %__MODULE__{
            user1_id: String.t(),
            user2_id: String.t(),
            users: [Famichat.Chat.User.t()] | nil,
            family_valid?: boolean() | nil,
            existing_conversation: Famichat.Chat.Conversation.t() | nil,
            error: atom() | nil,
            meta: map() | nil
          }

    defstruct [
      :user1_id,
      :user2_id,
      :users,
      :family_valid?,
      :existing_conversation,
      :error,
      :meta
    ]
  end

  @doc """
  Creates a validated conversation between two users with conflict prevention.

  ## Flow

  1. Validate user existence
  2. Verify family membership
  3. Check for existing conversation
  4. Create new conversation if needed
  5. Create participants if needed
  6. Preload associations

  ## Parameters

    - user1_id: Binary ID for initiating user
    - user2_id: Binary ID for receiving user (can match user1_id for self-conversation)

  ## Returns

    - `{:ok, Conversation.t()}` - Created/existing conversation with users preloaded
    - `{:error, reason}` - Tuple with error atom

  ## Errors

    - `:user_not_found` - Missing user records
    - `:different_families` - Cross-family conversation attempt
    - `:changeset_invalid` - Validation failures

  ## Examples

      # Successful direct conversation
      {:ok, conv} = create_direct_conversation(uuid1, uuid2)

      # Self-conversation
      {:ok, conv} = create_direct_conversation(uuid1, uuid1)

      # Cross-family error
      {:error, :different_families} = create_direct_conversation(uuid1, uuid3)
  """
  @spec create_direct_conversation(String.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, atom()}
  def create_direct_conversation(user1_id, user2_id)
      when is_binary(user1_id) and is_binary(user2_id) do
    metadata = %{user1_id: user1_id, user2_id: user2_id}

    # Execute the operation within a telemetry span
    :telemetry.span(
      [:famichat, :conversation_service, :create_direct_conversation],
      metadata,
      fn ->
        result = do_create_direct_conversation(user1_id, user2_id)

        # Determine the result status for metadata
        metadata_with_result = case result do
          {:ok, _} -> Map.put(metadata, :result, "created")
          {:error, _} -> Map.put(metadata, :result, "error")
        end

        # Return the result and the metadata
        {result, metadata_with_result}
      end
    )
  end

  # Private implementation of create_direct_conversation without telemetry
  defp do_create_direct_conversation(user1_id, user2_id) do
    with {:ok, user1} <- get_user(user1_id),
         {:ok, user2} <- get_user(user2_id),
         true <- user1.family_id == user2.family_id || {:error, :different_families} do
      family_id = user1.family_id
      direct_key = Conversation.compute_direct_key(user1_id, user2_id, family_id)

      # Create a new Multi for the transaction
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:existing, fn repo, _changes ->
          query =
            from c in Conversation,
              where: c.direct_key == ^direct_key and c.conversation_type == ^:direct

          case repo.one(query) do
            nil -> {:ok, nil}
            conv -> {:ok, conv}
          end
        end)
        |> Ecto.Multi.run(:create, fn repo, %{existing: existing} ->
          if existing do
            {:ok, existing}
          else
            attrs = %{
              family_id: family_id,
              conversation_type: :direct,
              direct_key: direct_key,
              metadata: %{}
            }

            changeset = Conversation.changeset(%Conversation{}, attrs)
            repo.insert(changeset)
          end
        end)
        |> Ecto.Multi.run(:participants, fn repo, %{create: conversation} ->
          # Check if participants already exist
          query =
            from p in ConversationParticipant,
              where: p.conversation_id == ^conversation.id,
              select: p.user_id

          existing_participant_ids = repo.all(query)

          # Create participants for each user not already in the conversation
          user_ids = [user1_id, user2_id] |> Enum.uniq()

          result =
            user_ids
            |> Enum.reject(fn user_id -> user_id in existing_participant_ids end)
            |> Enum.map(fn user_id ->
              %ConversationParticipant{}
              |> ConversationParticipant.changeset(%{
                conversation_id: conversation.id,
                user_id: user_id
              })
              |> repo.insert()
            end)
            |> Enum.all?(fn
              {:ok, _participant} -> true
              _ -> false
            end)

          if result do
            {:ok, conversation}
          else
            {:error, :participant_creation_failed}
          end
        end)
        |> Ecto.Multi.run(:preload, fn repo, %{participants: conversation} ->
          {:ok, repo.preload(conversation, :users)}
        end)

      case Repo.transaction(multi) do
        {:ok, %{preload: conversation}} ->
          {:ok, conversation}

        {:error, _op, reason, _changes} ->
          {:error, reason}
      end
    else
      error -> error
    end
  end

  @doc """
  Retrieves paginated direct conversations for a user with preloaded participants.

  ## Parameters

    - user_id: Binary ID of the user

  ## Returns

    - `{:ok, [Conversation.t()]}` - List of conversations
    - `{:error, :invalid_user_id}` - For non-UUID input

  ## Features

    - Automatic preloading of participant users
    - Distinct results to prevent duplicates
    - Ordered by recent activity

  ## Example

      {:ok, conversations} = list_user_conversations("a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11")
  """
  @spec list_user_conversations(String.t()) ::
          {:ok, [Conversation.t()]} | {:error, atom()}
  def list_user_conversations(user_id) when is_binary(user_id) do
    :telemetry.span(
      [
        :famichat,
        :conversation_service,
        :list_user_conversations
      ],
      %{},
      fn ->
        conversations = get_conversations(user_id)
        measurements = %{count: length(conversations)}
        # Wrap the list in a status tuple.
        {{:ok, conversations}, measurements}
      end
    )
  end

  def list_user_conversations(_), do: {:error, :invalid_user_id}

  defp get_user(user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp get_conversations(user_id) do
    query =
      from c in Conversation,
        join: u in assoc(c, :users),
        where: u.id == ^user_id and c.conversation_type == ^:direct,
        distinct: c.id,
        preload: [:users]

    Repo.all(query)
  end

  defp result_status({:ok, _}), do: "success"
  defp result_status({:error, _}), do: "error"

  @doc """
  Assigns the admin role to a user in a group conversation.

  Only existing admins can assign admin roles to others.

  ## Parameters
    - conversation_id: The ID of the group conversation
    - target_user_id: The user to be assigned as admin
    - granted_by_id: The user who is granting the admin role (must be an admin)

  ## Returns
    - {:ok, GroupConversationPrivileges.t()} - The newly created privilege
    - {:error, :not_admin} - If the granting user is not an admin
    - {:error, :not_group_conversation} - If the conversation is not a group
    - {:error, changeset} - If the operation failed due to validation errors
  """
  @spec assign_admin(binary(), binary(), binary()) :: {:ok, any()} | {:error, any()}
  def assign_admin(conversation_id, target_user_id, granted_by_id) do
    metadata = %{conversation_id: conversation_id, target_user_id: target_user_id, granted_by_id: granted_by_id}
    :telemetry.span([:famichat, :conversation_service, :assign_admin], metadata, fn ->
      conversation = Repo.get(Conversation, conversation_id)

      result =
        cond do
          is_nil(conversation) ->
            {:error, :conversation_not_found}
          conversation.conversation_type != :group ->
            {:error, :not_group_conversation}
          conversation_id != nil && granted_by_id != nil ->
            case is_admin?(conversation_id, granted_by_id) do
              {:ok, true} ->
                attrs = %{conversation_id: conversation_id, user_id: target_user_id, role: :admin, granted_by_id: granted_by_id}
                changeset = Famichat.Chat.GroupConversationPrivileges.changeset(%Famichat.Chat.GroupConversationPrivileges{}, attrs)
                Repo.insert(changeset)
              {:ok, false} ->
                {:error, :not_admin}
              error ->
                error
            end
          true ->
            {:error, :invalid_parameters}
        end
      {result, Map.put(metadata, :result, result_status(result))}
    end)
  end

  @doc """
  Assigns the member role to a user in a group conversation.

  Only admins can change roles, and the operation prevents removing the last admin.

  ## Parameters
    - conversation_id: The ID of the group conversation
    - target_user_id: The user to be assigned as member
    - granted_by_id: The user who is granting the member role (must be an admin)

  ## Returns
    - {:ok, GroupConversationPrivileges.t()} - The updated privilege
    - {:error, :not_admin} - If the granting user is not an admin
    - {:error, :last_admin} - If trying to demote the last admin
    - {:error, :not_group_conversation} - If the conversation is not a group
    - {:error, changeset} - If the operation failed due to validation errors
  """
  @spec assign_member(binary(), binary(), binary()) :: {:ok, any()} | {:error, any()}
  def assign_member(conversation_id, target_user_id, granted_by_id) do
    metadata = %{conversation_id: conversation_id, target_user_id: target_user_id, granted_by_id: granted_by_id}
    :telemetry.span([:famichat, :conversation_service, :assign_member], metadata, fn ->
      conversation = Repo.get(Conversation, conversation_id)

      result =
        cond do
          is_nil(conversation) ->
            {:error, :conversation_not_found}
          conversation.conversation_type != :group ->
            {:error, :not_group_conversation}
          granted_by_id != nil ->
            case is_admin?(conversation_id, granted_by_id) do
              {:ok, true} ->
                privilege = Repo.get_by(Famichat.Chat.GroupConversationPrivileges, conversation_id: conversation_id, user_id: target_user_id)
                cond do
                  privilege && privilege.role == :admin ->
                    # Check if this is the last admin
                    admin_count = Repo.aggregate(from(g in Famichat.Chat.GroupConversationPrivileges, where: g.conversation_id == ^conversation_id and g.role == :admin), :count, :id)
                    if admin_count <= 1 do
                      {:error, :last_admin}
                    else
                      changeset = Ecto.Changeset.change(privilege, role: :member)
                      Repo.update(changeset)
                    end
                  privilege ->
                    # Already a member
                    {:ok, privilege}
                  true ->
                    attrs = %{conversation_id: conversation_id, user_id: target_user_id, role: :member, granted_by_id: granted_by_id}
                    changeset = Famichat.Chat.GroupConversationPrivileges.changeset(%Famichat.Chat.GroupConversationPrivileges{}, attrs)
                    Repo.insert(changeset)
                end
              {:ok, false} ->
                {:error, :not_admin}
              error ->
                error
            end
          true ->
            {:error, :invalid_parameters}
        end
      {result, Map.put(metadata, :result, result_status(result))}
    end)
  end

  @doc """
  Checks if a user is an admin in a group conversation.

  ## Parameters
    - conversation_id: The ID of the group conversation
    - user_id: The user to check for admin privileges

  ## Returns
    - {:ok, true} - If the user is an admin
    - {:ok, false} - If the user is not an admin
    - {:error, :conversation_not_found} - If the conversation doesn't exist
  """
  @spec is_admin?(binary(), binary()) :: {:ok, boolean()} | {:error, any()}
  def is_admin?(conversation_id, user_id) do
    metadata = %{conversation_id: conversation_id, user_id: user_id}
    :telemetry.span([:famichat, :conversation_service, :is_admin?], metadata, fn ->
      conversation = Repo.get(Conversation, conversation_id)
      result =
        cond do
          is_nil(conversation) ->
            {:error, :conversation_not_found}
          true ->
            privilege = Repo.get_by(Famichat.Chat.GroupConversationPrivileges, conversation_id: conversation_id, user_id: user_id)
            case privilege do
              %Famichat.Chat.GroupConversationPrivileges{role: :admin} -> {:ok, true}
              %Famichat.Chat.GroupConversationPrivileges{} -> {:ok, false}
              nil -> {:ok, false}
            end
        end
      {result, Map.put(metadata, :result, result_status(result))}
    end)
  end

  @doc """
  Removes a privilege from a group conversation. Prevents removal if it is the last admin.

  ## Parameters
    - conversation_id: The ID of the group conversation
    - user_id: The user whose privilege will be removed
    - removed_by_id: The user who is removing the privilege (must be an admin)

  ## Returns
    - {:ok, GroupConversationPrivileges.t()} - The removed privilege
    - {:error, :not_admin} - If the removing user is not an admin
    - {:error, :last_admin} - If trying to remove the last admin
    - {:error, :not_found} - If the privilege doesn't exist
  """
  @spec remove_privilege(binary(), binary(), binary() | nil) :: {:ok, any()} | {:error, any()}
  def remove_privilege(conversation_id, user_id, removed_by_id \\ nil) do
    metadata = %{conversation_id: conversation_id, user_id: user_id, removed_by_id: removed_by_id}
    :telemetry.span([:famichat, :conversation_service, :remove_privilege], metadata, fn ->
      privilege = Repo.get_by(Famichat.Chat.GroupConversationPrivileges, conversation_id: conversation_id, user_id: user_id)
      result =
        cond do
          is_nil(privilege) ->
            {:error, :not_found}
          removed_by_id && removed_by_id != user_id ->
            case is_admin?(conversation_id, removed_by_id) do
              {:ok, true} -> do_remove_privilege(privilege, conversation_id)
              {:ok, false} -> {:error, :not_admin}
              error -> error
            end
          true ->
            # Self-removal or system action
            do_remove_privilege(privilege, conversation_id)
        end
      {result, Map.put(metadata, :result, result_status(result))}
    end)
  end

  defp do_remove_privilege(privilege, conversation_id) do
    if privilege.role == :admin do
      admin_count = Repo.aggregate(from(g in Famichat.Chat.GroupConversationPrivileges, where: g.conversation_id == ^conversation_id and g.role == :admin), :count, :id)
      if admin_count <= 1 do
        {:error, :last_admin}
      else
        Repo.delete(privilege)
      end
    else
      Repo.delete(privilege)
    end
  end
end
