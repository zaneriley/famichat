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

  def send_message(_, _, _), do: {:error, :invalid_input}
end
