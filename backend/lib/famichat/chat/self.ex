defmodule Famichat.Chat.Self do
  @moduledoc """
  Actor-owned self conversation access and creation.

  This module is the single entrypoint for resolving a user's self conversation.
  """

  import Ecto.Query

  alias Famichat.Accounts.{HouseholdMembership, User}
  alias Famichat.Chat.{Conversation, ConversationParticipant}
  alias Famichat.Repo

  @spec get_or_create(Ecto.UUID.t()) ::
          {:ok, Conversation.t()}
          | {:error,
             :user_not_found
             | :not_in_family
             | :ambiguous_household
             | :invalid_self_conversation
             | :lock_failed}
  def get_or_create(user_id) when is_binary(user_id) do
    with {:ok, _user} <- fetch_user(user_id),
         {:ok, family_id} <- family_id_for_user(user_id) do
      Repo.transaction(fn ->
        with :ok <- lock_user_scope(user_id),
             {:ok, conversation} <- resolve_or_create(user_id, family_id) do
          Repo.preload(conversation, :explicit_users)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, conversation} -> {:ok, conversation}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def get_or_create(_), do: {:error, :user_not_found}

  defp fetch_user(user_id) do
    case Repo.get(User, user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :user_not_found}
    end
  end

  defp family_id_for_user(user_id) do
    family_ids =
      from(m in HouseholdMembership,
        where: m.user_id == ^user_id,
        order_by: [asc: m.inserted_at, asc: m.family_id],
        limit: 2,
        select: m.family_id
      )
      |> Repo.all()

    case family_ids do
      [] -> {:error, :not_in_family}
      [family_id] -> {:ok, family_id}
      [_family_id_one, _family_id_two] -> {:error, :ambiguous_household}
    end
  end

  defp lock_user_scope(user_id) do
    case Repo.query("SELECT pg_advisory_xact_lock(hashtext($1))", [user_id]) do
      {:ok, _} -> :ok
      _ -> {:error, :lock_failed}
    end
  end

  defp resolve_or_create(user_id, family_id) do
    with {:ok, maybe_conversation} <- find_existing(user_id, family_id) do
      case maybe_conversation do
        %Conversation{} = conversation -> {:ok, conversation}
        nil -> create_self_conversation(user_id, family_id)
      end
    end
  end

  defp find_existing(user_id, family_id) do
    query =
      from c in Conversation,
        join: cp in ConversationParticipant,
        on: cp.conversation_id == c.id,
        where:
          c.conversation_type == :self and c.family_id == ^family_id and
            cp.user_id == ^user_id,
        order_by: [asc: c.inserted_at],
        select: c.id

    case Repo.all(query) do
      [] ->
        {:ok, nil}

      [conversation_id] ->
        validate_private_self(conversation_id, user_id)

      _ ->
        {:error, :invalid_self_conversation}
    end
  end

  defp validate_private_self(conversation_id, user_id) do
    participant_ids_query =
      from cp in ConversationParticipant,
        where: cp.conversation_id == ^conversation_id,
        order_by: [asc: cp.user_id],
        select: cp.user_id

    case Repo.all(participant_ids_query) do
      [^user_id] ->
        {:ok, Repo.get!(Conversation, conversation_id)}

      _ ->
        {:error, :invalid_self_conversation}
    end
  end

  defp create_self_conversation(user_id, family_id) do
    attrs = %{
      family_id: family_id,
      conversation_type: :self,
      metadata: %{}
    }

    with {:ok, conversation} <-
           %Conversation{}
           |> Conversation.create_changeset(attrs)
           |> Repo.insert(),
         {:ok, _participant} <-
           %ConversationParticipant{}
           |> ConversationParticipant.changeset(%{
             conversation_id: conversation.id,
             user_id: user_id
           })
           |> Repo.insert() do
      {:ok, conversation}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_self_conversation}
    end
  end
end
