defmodule Famichat.Chat.ConversationAccess do
  @moduledoc """
  Centralized authorization utilities for conversation-scoped actions.

  This module enforces business rules around who may interact with a
  conversation (send messages, manage membership, etc.) and emits
  telemetry on denied attempts so we can monitor probes.
  """
  import Ecto.Query, only: [from: 2]
  alias Famichat.Repo
  alias Famichat.Chat.{Conversation, ConversationParticipant}

  alias Famichat.Accounts.{FamilyMembership, User}

  @typedoc "Allowed authorization actions."
  @type action :: :send_message

  @typedoc "Reasons returned for authorization failures."
  @type reason ::
          :conversation_not_found
          | :user_not_found
          | :not_participant
          | :wrong_family
          | :not_authorized
          | :unknown_action

  @telemetry_prefix [:famichat, :conversation, :authorization_denied]

  @doc """
  Authorizes a conversation-scoped `action` for the given `user`.

  Accepts either struct or ID inputs. Returns `:ok` on success or
  `{:error, reason}` on denial.
  """
  @spec authorize(
          Conversation.t() | Ecto.UUID.t(),
          User.t() | Ecto.UUID.t(),
          action()
        ) ::
          :ok | {:error, reason()}
  def authorize(%Conversation{} = conversation, user, action) do
    with {:ok, user_id} <- normalize_user(user) do
      do_authorize(conversation, user_id, action)
    end
  end

  def authorize(conversation_id, user, action)
      when is_binary(conversation_id) do
    case Repo.get(Conversation, conversation_id) do
      %Conversation{} = conversation -> authorize(conversation, user, action)
      nil -> {:error, :conversation_not_found}
    end
  end

  @doc """
  Returns whether the given user participates in the conversation.
  """
  @spec member?(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def member?(conversation_id, user_id) do
    Repo.exists?(
      from p in ConversationParticipant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
    )
  end

  defp do_authorize(%Conversation{} = conversation, user_id, :send_message) do
    case conversation.conversation_type do
      :direct -> authorize_direct(conversation, user_id)
      :group -> authorize_group(conversation, user_id)
      :self -> authorize_self(conversation, user_id)
      :family -> authorize_family(conversation, user_id)
      _ -> deny(:send_message, conversation.id, user_id, :unknown_action)
    end
  end

  defp do_authorize(%Conversation{} = conversation, user_id, _action) do
    deny(:unknown, conversation.id, user_id, :unknown_action)
  end

  defp authorize_direct(conversation, user_id) do
    if participant?(conversation.id, user_id) do
      :ok
    else
      deny(:send_message, conversation.id, user_id, :not_participant)
    end
  end

  defp authorize_group(conversation, user_id) do
    if participant?(conversation.id, user_id) do
      :ok
    else
      deny(:send_message, conversation.id, user_id, :not_participant)
    end
  end

  defp authorize_self(conversation, user_id) do
    if participant?(conversation.id, user_id) do
      :ok
    else
      deny(:send_message, conversation.id, user_id, :not_participant)
    end
  end

  defp authorize_family(
         %Conversation{family_id: family_id} = conversation,
         user_id
       ) do
    if family_member?(family_id, user_id) do
      :ok
    else
      deny(:send_message, conversation.id, user_id, :wrong_family)
    end
  end

  defp participant?(conversation_id, user_id) do
    Repo.exists?(
      from p in ConversationParticipant,
        where: p.conversation_id == ^conversation_id and p.user_id == ^user_id
    )
  end

  defp family_member?(family_id, user_id) do
    Repo.exists?(
      from m in FamilyMembership,
        where: m.family_id == ^family_id and m.user_id == ^user_id
    )
  end

  defp deny(action, conversation_id, user_id, reason) do
    emit_denied(action, conversation_id, user_id, reason)
    {:error, reason}
  end

  defp emit_denied(action, conversation_id, user_id, reason) do
    :telemetry.execute(
      @telemetry_prefix,
      %{count: 1},
      %{
        action: action,
        conversation_id: conversation_id,
        user_id: user_id,
        reason: reason
      }
    )
  end

  defp normalize_user(%User{id: id}), do: {:ok, id}

  defp normalize_user(user_id) when is_binary(user_id), do: {:ok, user_id}

  defp normalize_user(_invalid), do: {:error, :user_not_found}
end
