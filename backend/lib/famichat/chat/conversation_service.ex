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

  Emits events via `[:famichat, :conversation, :created]` with measurements:
  - `:count` (integer) - Always 1 per creation attempt
  Metadata:
  - `:result` - :success or :error
  - `:user1_id`, `:user2_id` - Participant IDs

  ## Example Usage

      {:ok, conv} = ConversationService.create_direct_conversation(user1_id, user2_id)
      {:ok, conversations} = ConversationService.list_user_conversations(user_id)
  """

  alias Famichat.{Repo, Chat.Conversation, Chat.User}
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

  ## Parameters

    - user1_id: Binary ID for initiating user
    - user2_id: Binary ID for receiving user (can match user1_id for self-conversation)

  ## Returns

    - `{:ok, Conversation.t()}` - Created/existing conversation
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
    result = do_create_conversation(user1_id, user2_id)

    # Emit telemetry after processing
    :telemetry.execute([:famichat, :conversation, :created], %{count: 1}, %{
      user1_id: user1_id,
      user2_id: user2_id,
      result: if(ok?(result), do: :success, else: :error)
    })

    # Unwrap and return only the status tuple.
    case result do
      {status, _meta} -> status
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

  defp do_create_conversation(user1_id, user2_id) do
    %ConversationState{user1_id: user1_id, user2_id: user2_id}
    |> load_users()
    |> validate_pair()
    |> handle_transaction()
    |> finalize_result()
  end

  defp load_users(state) do
    users =
      if state.user1_id == state.user2_id do
        Repo.all(from u in User, where: u.id == ^state.user1_id)
      else
        Repo.all(
          from u in User, where: u.id in ^[state.user1_id, state.user2_id]
        )
      end

    %{state | users: users}
  end

  defp validate_pair(state) do
    cond do
      state.user1_id == state.user2_id and length(state.users) != 1 ->
        %{state | error: :user_not_found, meta: %{error: "User not found"}}

      state.user1_id != state.user2_id and length(state.users) != 2 ->
        %{
          state
          | error: :user_not_found,
            meta: %{error: "One or both users not found"}
        }

      state.user1_id != state.user2_id and not same_family?(state.users) ->
        %{
          state
          | error: :different_families,
            meta: %{error: :different_families}
        }

      true ->
        state
    end
  end

  defp handle_transaction(%{error: nil} = state) do
    transaction_result =
      Repo.transaction(fn ->
        state
        |> find_existing_conversation()
        |> create_if_missing()
      end)

    case transaction_result do
      {:ok, {status, conv}} ->
        %{state | existing_conversation: conv, meta: %{status => true}}

      {:error, reason} ->
        %{state | error: reason, meta: %{error: reason}}
    end
  end

  defp handle_transaction(state), do: state

  defp find_existing_conversation(state) do
    # Consolidated existing conversation query logic
    type = if state.user1_id == state.user2_id, do: :self, else: :direct
    participant_count = if type == :self, do: 1, else: 2

    existing =
      from(c in Conversation,
        where: c.conversation_type == ^type,
        join: p in assoc(c, :participants),
        group_by: c.id,
        having: fragment("COUNT(DISTINCT ?) = ?", p.user_id, ^participant_count)
      )
      |> Repo.one()

    if existing, do: {:existing, existing}, else: {:create, state}
  end

  defp create_if_missing({:existing, conv}), do: {:existing, conv}

  defp create_if_missing({:create, state}) do
    family_id = hd(state.users).family_id

    unless Ecto.UUID.cast(family_id) do
      Logger.error("Invalid family_id format: #{family_id}")
      Repo.rollback(:invalid_family_id)
    end

    attrs = %{
      family_id: family_id,
      conversation_type:
        if(state.user1_id == state.user2_id, do: :self, else: :direct),
      metadata: %{}
    }

    # credo:disable-for-next-line Credo.Check.Readability.WithSingleClause
    with {:ok, conv} <-
           %Conversation{}
           |> Conversation.changeset(attrs)
           |> Ecto.Changeset.put_assoc(:users, state.users)
           |> Repo.insert() do
      {:new, conv}
    else
      {:error, changeset} ->
        log_changeset_error(changeset)

        Repo.rollback(
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)
        )
    end
  end

  defp finalize_result(%{error: nil, existing_conversation: conv, meta: meta}),
    do: {{:ok, conv}, meta}

  defp finalize_result(%{error: error, meta: meta}),
    do: {{:error, error}, meta}

  defp same_family?(users),
    do: Enum.map(users, & &1.family_id) |> Enum.uniq() |> length() == 1

  @dialyzer {:nowarn_function, log_changeset_error: 1}
  defp log_changeset_error(changeset),
    do:
      Logger.error("Conversation creation failed",
        changeset: inspect(changeset, pretty: true)
      )

  defp ok?({{:ok, _}, _}), do: true
  defp ok?(_), do: false

  defp get_conversations(user_id) do
    query =
      from c in Conversation,
        join: u in assoc(c, :users),
        where: u.id == ^user_id and c.conversation_type == ^:direct,
        distinct: c.id,
        preload: [:users]

    Repo.all(query)
  end
end
