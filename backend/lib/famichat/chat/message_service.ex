defmodule Famichat.Chat.MessageService do
  @moduledoc """
  Provides the core message sending functionality for Famichat.

  This service module encapsulates the logic for sending messages,
  handling validations, and interacting with the database to persist messages.
  """
  alias Famichat.Repo
  alias Famichat.Chat
  alias Famichat.Chat.Message

  @doc """
  Sends a text message.

  Receives sender_id, conversation_id, and message content,
  creates a new message, and inserts it into the database.

  ## Returns
  - `{:ok, message}` on successful message creation, where `message` is the inserted `Famichat.Chat.Message` struct.
  - `{:error, changeset}` on validation errors, where `changeset` is an `Ecto.Changeset` struct containing error information.
  """
  @spec send_message(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_message(sender_id, conversation_id, content) do
    message_params = %{
      sender_id: sender_id,
      conversation_id: conversation_id,
      content: content,
      message_type: :text # For Level 1, we only send text messages
    }

    %Message{}
    |> Message.changeset(message_params)
    |> Repo.insert()
  end
end
