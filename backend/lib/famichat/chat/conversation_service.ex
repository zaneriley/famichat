defmodule Famichat.Chat.ConversationService do
  @moduledoc """
  Provides service functions for managing conversations.

  This module includes functions for creating direct (one-to-one) conversations
  and listing a user's direct conversations. It ensures that a direct conversation
  between users is unique regardless of input order, and performs validations such as ensuring that both users exist and belong to
  the same family. A user messaging themselves is now allowed and produces a conversation of type :self.
  """

  alias Famichat.{Repo, Chat.Conversation, Chat.User}
  import Ecto.Query, only: [from: 2]
  require Logger

  @doc """
  Creates a conversation between two users.

  If the two IDs are identical, a self conversation is created (or returned if it already exists).
  If they are distinct, a direct conversation is created if both users exist and share a family.

  ## Parameters
    - user1_id: Binary ID for the first user.
    - user2_id: Binary ID for the second user.

  ## Returns
    - {{:ok, conversation}, meta} on success.
    - {{:error, reason}, meta} if any validation fails.
  """
  @spec create_direct_conversation(String.t(), String.t()) :: {:ok, Conversation.t()} | {:error, any()}
  def create_direct_conversation(user1_id, user2_id) when is_binary(user1_id) and is_binary(user2_id) do
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
  Lists all direct conversations for a given user.

  Only conversations of type :direct are returned.

  ## Parameters
    - user_id: Binary ID for the user.

  ## Returns
    - {{:ok, [conversation]} , meta} on success.
    - {:error, reason} if input is invalid.
  """
  @spec list_user_conversations(String.t()) :: {:ok, [Conversation.t()]} | {:error, any()}
  def list_user_conversations(user_id) when is_binary(user_id) do
    :telemetry.span([
      :famichat, :conversation_service, :list_user_conversations
    ], %{}, fn ->
      conversations = get_conversations(user_id)
      measurements = %{count: length(conversations)}
      # Wrap the list in a status tuple.
      {{:ok, conversations}, measurements}
    end)
  end

  def list_user_conversations(_), do: {:error, :invalid_user_id}

  defp validate_same_family_batch(users) when is_list(users) do
    case Enum.uniq(Enum.map(users, & &1.family_id)) do
      [_] -> :ok
      _   -> {:error, :different_families}
    end
  end

  defp translate_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp do_create_conversation(user1_id, user2_id) when is_binary(user1_id) and is_binary(user2_id) do
      if user1_id == user2_id do
        # Self conversation branch
        users = Repo.all(from u in User, where: u.id == ^user1_id)
        if length(users) != 1 do
          { {:error, :user_not_found}, %{error: "User not found"} }
        else
          user = hd(users)
          result = Repo.transaction(fn ->
            existing_conversation =
              from(c in Conversation,
                where: c.conversation_type == ^:self,
                join: cp in Famichat.Chat.ConversationParticipant,
                  on: cp.conversation_id == c.id,
                where: cp.user_id == ^user1_id,
                group_by: c.id,
                having: fragment("COUNT(DISTINCT ?) = ?", cp.user_id, 1)
              )
              |> Repo.one()

            if existing_conversation do
              {:existing, existing_conversation}
            else
              conversation_changeset =
                %Conversation{}
                |> Conversation.changeset(%{
                  family_id: user.family_id,
                  conversation_type: :self,
                  metadata: %{}
                })
                |> Ecto.Changeset.put_assoc(:users, [user])

              case Repo.insert(conversation_changeset) do
                {:ok, conversation} ->
                  {:new, conversation}
                {:error, changeset} ->
                  Logger.error("Failed to create self conversation", changeset: inspect(changeset))
                  Repo.rollback({:error, translate_changeset_errors(changeset)})
              end
            end
          end)

          case result do
            {:ok, {:existing, conv}} -> { {:ok, conv}, %{existing: true} }
            {:ok, {:new, conv}} -> { {:ok, conv}, %{created: true} }
            {:error, error} -> { {:error, error}, %{error: error} }
          end
        end
      else
        # Distinct users branch
        users = Repo.all(from u in User, where: u.id in ^[user1_id, user2_id])
        if length(users) != 2 do
          { {:error, :user_not_found}, %{error: "One or both users not found"} }
        else
          with :ok <- validate_same_family_batch(users) do
            # Sort users deterministically (by id)
            [user1, user2] = Enum.sort(users, fn u1, u2 -> u1.id <= u2.id end)

            result = Repo.transaction(fn ->
              # Query for an existing direct conversation that has exactly these two participants.
              existing_conversation =
                from(c in Conversation,
                  where: c.conversation_type == ^:direct,
                  join: cp in Famichat.Chat.ConversationParticipant,
                    on: cp.conversation_id == c.id,
                  where: cp.user_id in [^user1_id, ^user2_id],
                  group_by: c.id,
                  having: fragment("COUNT(DISTINCT ?) = ?", cp.user_id, 2)
                )
                |> Repo.one()

              if existing_conversation do
                {:existing, existing_conversation}
              else
                conversation_changeset =
                  %Conversation{}
                  |> Conversation.changeset(%{
                    family_id: user1.family_id,
                    conversation_type: :direct,
                    metadata: %{}
                  })
                  |> Ecto.Changeset.put_assoc(:users, [user1, user2])

                case Repo.insert(conversation_changeset) do
                  {:ok, conversation} ->
                    {:new, conversation}
                  {:error, changeset} ->
                    Logger.error("Failed to create conversation", changeset: inspect(changeset))
                    Repo.rollback({:error, translate_changeset_errors(changeset)})
                end
              end
            end)

            case result do
              {:ok, {:existing, conversation}} ->
                { {:ok, conversation}, %{existing: true} }
              {:ok, {:new, conversation}} ->
                { {:ok, conversation}, %{created: true} }
              {:error, error} ->
                { {:error, error}, %{error: error} }
            end
          else
            {:error, reason} ->
              { {:error, reason}, %{error: reason} }
          end
        end
      end
  end

  defp ok?(result) do
    case result do
      {:ok, _} -> true
      _         -> false
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
end
