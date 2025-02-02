defmodule Famichat.Chat.MessageService do
  @moduledoc """
  Provides the core message sending functionality for Famichat.

  This service module encapsulates the logic for sending messages,
  handling validations, and interacting with the database to persist messages.
  """
  import Ecto.Query, warn: false
  alias Famichat.{Repo}
  alias Famichat.Chat.Message

  @doc """
  Sends a new text message in a conversation.

  ## Parameters
  - `sender_id` - The ID of the user sending the message
  - `conversation_id` - The ID of the conversation to send the message in
  - `content` - The text content of the message

  ## Returns
  - `{:ok, Message.t()}` on success, where `Message.t()` is the created message.
  - `{:error, Ecto.Changeset.t()}` on validation errors, where `Ecto.Changeset.t()` contains error information.
  - `{:error, :invalid_input}` on invalid input parameters.
  """
  @spec send_message(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, Message.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :invalid_input}
  def send_message(sender_id, conversation_id, content)
      when is_binary(sender_id) and is_binary(conversation_id) and
             is_binary(content) do
    message_params = %{
      message_type: :text,
      content: content,
      sender_id: sender_id,
      conversation_id: conversation_id
    }

    try do
      %Message{}
      |> Message.changeset(message_params)
      |> Repo.insert()
    rescue
      _ -> {:error, :invalid_input}
    end
  end

  @doc """
  Retrieves all messages for the given conversation in ascending order (oldest first).

  ## Parameters
  - conversation_id: A valid binary UUID for the conversation.

  ## Returns
  - `{:ok, messages}` where messages are ordered by `inserted_at`
  - `{:error, :invalid_conversation_id}` if the conversation_id is nil.
  - `{:error, :not_found}` if the conversation does not exist.
  """
  @spec get_conversation_messages(Ecto.UUID.t()) ::
          {:ok, [Message.t()]} | {:error, :invalid_conversation_id | :not_found}
  def get_conversation_messages(conversation_id) when is_nil(conversation_id),
    do: {:error, :invalid_conversation_id}

  def get_conversation_messages(conversation_id) when is_binary(conversation_id) do
    :telemetry.span([:famichat, :message_service, :get_conversation_messages], %{}, fn ->
      start = System.monotonic_time()

      result =
        case Repo.get(Famichat.Chat.Conversation, conversation_id) do
          nil -> {:error, :not_found}
          _ -> {:ok, Repo.all(from m in Message,
            where: m.conversation_id == ^conversation_id,
            order_by: [asc: m.inserted_at]
          )}
        end

      duration = System.monotonic_time() - start
      measurements =
        case result do
          {:ok, messages} -> %{message_count: length(messages), duration: duration}
          _ -> %{duration: duration}
        end

      {result, measurements}
    end)
  end

  def send_message(_, _, _), do: {:error, :invalid_input}
end
