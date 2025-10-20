defmodule Famichat.Chat.ConversationAccess do
  @moduledoc """
  Centralized authorization utilities for conversation-scoped actions.

  This module enforces business rules around who may interact with a
  conversation (send messages, manage membership, etc.) and emits
  telemetry on denied attempts so we can monitor probes.
  """
  import Ecto.Query
  alias Famichat.Repo
  alias Famichat.Chat.{Conversation, ConversationQueries}

  alias Famichat.Accounts.User

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
    case Repo.get(Conversation, conversation_id) do
      %Conversation{} = conversation ->
        membership_exists?(conversation, user_id)

      nil ->
        false
    end
  end

  defp do_authorize(%Conversation{} = conversation, user_id, :send_message) do
    if membership_exists?(conversation, user_id) do
      :ok
    else
      deny(
        :send_message,
        conversation.id,
        user_id,
        denial_reason(conversation.conversation_type)
      )
    end
  end

  defp do_authorize(%Conversation{} = conversation, user_id, _action) do
    deny(:unknown, conversation.id, user_id, :unknown_action)
  end

  defp membership_exists?(%Conversation{} = conversation, user_id) do
    conversation
    |> ConversationQueries.members()
    |> where([u], u.id == ^user_id)
    |> Repo.exists?()
  end

  defp denial_reason(:family), do: :wrong_family
  defp denial_reason(_), do: :not_participant

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
