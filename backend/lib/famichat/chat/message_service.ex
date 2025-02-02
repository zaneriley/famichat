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
  Retrieves messages for the given conversation in ascending order (oldest first)
  with optional pagination.

  ## Parameters
  - conversation_id: A valid binary UUID for the conversation.
  - opts: A keyword list of options. Supported keys:
    - `:limit` - Maximum number of messages to return.
    - `:offset` - Number of messages to skip (zero-based index). Messages are ordered by insertion time.

  ## Returns
  - `{:ok, messages}` where messages are ordered by `inserted_at`
  - `{:error, :invalid_conversation_id}` if the conversation_id is nil.
  - `{:error, :not_found}` if the conversation does not exist.
  """
  @spec get_conversation_messages(Ecto.UUID.t(), Keyword.t()) ::
          {:ok, [Message.t()]} | {:error, :invalid_conversation_id | :not_found}
  def get_conversation_messages(conversation_id, opts \\ [])

  def get_conversation_messages(conversation_id, _opts) when is_nil(conversation_id),
    do: {:error, :invalid_conversation_id}

  def get_conversation_messages(conversation_id, opts) when is_binary(conversation_id) do
    with {:ok, validated_opts} <- validate_opts(opts) do
      :telemetry.span(
        [:famichat, :message_service, :get_conversation_messages],
        %{opts: validated_opts},
        fn ->
          start = System.monotonic_time(:microsecond)

          result =
            case Repo.get(Famichat.Chat.Conversation, conversation_id) do
              nil ->
                {:error, :not_found}
              _conversation ->
                query =
                  from m in Message,
                    where: m.conversation_id == ^conversation_id,
                    order_by: [asc: m.inserted_at]

                # Apply pagination if provided.
                query =
                  if limit = validated_opts[:limit] do
                    from q in query, limit: ^limit
                  else
                    query
                  end

                query =
                  if offset = validated_opts[:offset] do
                    from q in query, offset: ^offset
                  else
                    query
                  end

                {:ok, Repo.all(query)}
            end

          duration = System.monotonic_time(:microsecond) - start
          measurements =
            case result do
              {:ok, messages} ->
                %{message_count: length(messages), duration: duration}
                |> Map.merge(validated_opts)
              _ ->
                %{duration: duration} |> Map.merge(validated_opts)
            end

          {result, measurements}
        end
      )
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @max_limit 100
  # Private function to validate and normalize pagination options.
  defp validate_opts(opts) do
    opts = Enum.into(opts, %{})

    validated =
      opts
      |> Enum.reduce(%{}, fn
        {:limit, limit}, acc when is_integer(limit) and limit > 0 ->
          Map.put(acc, :limit, if(limit > @max_limit, do: @max_limit, else: limit))

        {:limit, _invalid}, _acc ->
          :error

        {:offset, offset}, acc when is_integer(offset) and offset >= 0 ->
          Map.put(acc, :offset, offset)

        {:offset, _invalid}, _acc ->
          :error

        {_key, _value}, acc ->
          acc
      end)

    case validated do
      :error -> {:error, :invalid_pagination_values}
      _ -> {:ok, validated}
    end
  end

  def send_message(_, _, _), do: {:error, :invalid_input}
end
