defmodule Famichat.Chat.MessageService do
  @moduledoc """
  Message handling pipeline implementing:
  1. Validation -> 2. Authorization -> 3. Persistence -> 4. Notification
  """
  import Ecto.Query, warn: false
  alias Famichat.Repo
  alias Famichat.Chat.{Message, Conversation}
  require Logger

  @max_limit 100
  @default_preloads [:sender, :conversation]

  # Encryption metadata fields - preserved for reference and future use
  # when implementing schema validation for encryption metadata
  @encryption_metadata_fields [:key_id, :version_tag, :encryption_flag]

  # Define conversation-type encryption requirements
  @encryption_requirements %{
    direct: true,
    family: true,
    group: true,
    self: true
  }

  # Telemetry prefixes
  @telemetry_prefix [:famichat, :message]

  @doc """
  Pipeline-based message retrieval with structured error handling:

  {:ok, messages} = MessageService.get_conversation_messages(conversation_id,
    limit: 20,
    offset: 0,
    preload: [:sender]
  )
  """
  @spec get_conversation_messages(Ecto.UUID.t(), Keyword.t()) ::
          {:ok, [Message.t()]} | {:error, atom()}
  def get_conversation_messages(conversation_id, opts \\ []) do
    initial_state = %{
      conversation_id: conversation_id,
      opts: opts,
      validated?: false,
      query: nil
    }

    initial_state
    |> validate_conversation_id()
    |> validate_pagination_opts()
    |> check_conversation_exists()
    |> build_base_query()
    |> apply_pagination()
    |> execute_query()
    |> preload_associations()
    |> handle_result()
  end

  defp validate_conversation_id(%{conversation_id: nil} = state) do
    put_in(state.validated?, false)
    |> Map.put(:error, :invalid_conversation_id)
  end

  defp validate_conversation_id(state) do
    put_in(state.validated?, true)
  end

  defp check_conversation_exists(%{error: _} = state), do: state

  defp check_conversation_exists(state) do
    if Repo.exists?(
         from c in Conversation,
           where: c.id == ^state.conversation_id
       ) do
      state
    else
      Map.put(state, :error, :conversation_not_found)
    end
  end

  defp validate_pagination_opts(%{validated?: false} = state), do: state

  defp validate_pagination_opts(state) do
    with {:ok, limit} <- validate_limit(state.opts[:limit]),
         {:ok, offset} <- validate_offset(state.opts[:offset]) do
      state
      |> put_in([:opts, :limit], limit)
      |> put_in([:opts, :offset], offset)
    else
      error -> Map.put(state, :error, error)
    end
  end

  defp build_base_query(%{error: _} = state), do: state

  defp build_base_query(state) do
    query =
      from m in Message,
        where: m.conversation_id == ^state.conversation_id,
        order_by: [asc: m.inserted_at]

    Map.put(state, :query, query)
  end

  defp apply_pagination(%{error: _} = state), do: state

  defp apply_pagination(state) do
    state.query
    |> maybe_apply(:limit, state.opts[:limit])
    |> maybe_apply(:offset, state.opts[:offset])
    |> then(&Map.put(state, :query, &1))
  end

  defp execute_query(%{error: _} = state), do: state

  defp execute_query(state) do
    case Repo.all(state.query) do
      [] -> Map.put(state, :result, [])
      messages -> Map.put(state, :result, messages)
    end
  rescue
    _ -> Map.put(state, :error, :query_execution_failed)
  end

  defp preload_associations(%{error: _} = state), do: state

  defp preload_associations(state) do
    preloads = state.opts[:preload] || @default_preloads
    Map.update!(state, :result, &Repo.preload(&1, preloads))
  end

  defp handle_result(%{error: error}), do: {:error, error}
  defp handle_result(%{message: message}), do: {:ok, message}
  defp handle_result(%{result: result}), do: {:ok, result}

  @doc """
  Message creation pipeline:

  {:ok, message} = MessageService.send_message(%{
    sender_id: "uuid",
    conversation_id: "uuid",
    content: "Hello",
    type: :text
  })
  """
  @spec send_message(map()) :: {:ok, Message.t()} | {:error, any()}
  def send_message(params) do
    initial_state = %{
      params: params,
      changeset: nil,
      message: nil
    }

    initial_state
    |> validate_required_fields()
    |> validate_sender()
    |> validate_conversation()
    |> process_encryption_metadata()
    |> build_changeset()
    |> persist_message()
    |> notify_participants()
    |> handle_result()
  end

  # Private pipeline implementations
  defp validate_required_fields(state) do
    required = [:sender_id, :conversation_id, :content]
    missing = Enum.reject(required, &Map.has_key?(state.params, &1))

    case missing do
      [] -> state
      _ -> Map.put(state, :error, {:missing_fields, missing})
    end
  end

  defp validate_sender(%{error: _} = state), do: state

  defp validate_sender(state) do
    if Repo.exists?(
         from u in Famichat.Chat.User, where: u.id == ^state.params.sender_id
       ) do
      state
    else
      Map.put(state, :error, :sender_not_found)
    end
  end

  defp validate_conversation(%{error: _} = state), do: state

  defp validate_conversation(state) do
    if Repo.exists?(
         from c in Conversation, where: c.id == ^state.params.conversation_id
       ) do
      state
    else
      Map.put(state, :error, :conversation_not_found)
    end
  end

  defp build_changeset(%{error: _} = state), do: state

  defp build_changeset(state) do
    changeset =
      %Message{}
      |> Message.changeset(state.params)

    if changeset.valid? do
      Map.put(state, :changeset, changeset)
    else
      Map.put(state, :error, changeset)
    end
  end

  defp persist_message(%{error: _} = state), do: state

  defp persist_message(state) do
    case Repo.insert(state.changeset) do
      {:ok, message} -> Map.put(state, :message, message)
      {:error, reason} -> Map.put(state, :error, reason)
    end
  end

  defp notify_participants(%{error: _} = state), do: state

  defp notify_participants(state) do
    # Placeholder for real notification system
    :telemetry.execute([:famichat, :message, :sent], %{count: 1}, %{
      conversation_id: state.message.conversation_id,
      sender_id: state.message.sender_id
    })

    state
  end

  # Shared helpers
  defp validate_limit(nil), do: {:ok, nil}

  defp validate_limit(limit)
       when is_integer(limit) and limit > 0 and limit <= @max_limit,
       do: {:ok, limit}

  defp validate_limit(_), do: {:error, :invalid_limit}

  defp validate_offset(nil), do: {:ok, nil}

  defp validate_offset(offset) when is_integer(offset) and offset >= 0,
    do: {:ok, offset}

  defp validate_offset(_), do: {:error, :invalid_offset}

  defp maybe_apply(query, _clause, nil), do: query
  defp maybe_apply(query, :limit, value), do: from(q in query, limit: ^value)
  defp maybe_apply(query, :offset, value), do: from(q in query, offset: ^value)

  @doc """
  Determines if a conversation type requires encryption based on policy configuration.

  ## Examples

      iex> requires_encryption?(:direct)
      true

      iex> requires_encryption?(:self)
      true
  """
  @spec requires_encryption?(atom()) :: boolean()
  def requires_encryption?(conversation_type) when is_atom(conversation_type) do
    Map.get(@encryption_requirements, conversation_type, false)
  end

  @doc """
  Serializes a message with its encryption metadata.

  This function takes a message and extracts the encryption metadata from the params
  to store it in the message metadata field. This allows for preserving encryption
  information when messages are stored in the database.

  ## Examples

      iex> serialize_message(%{content: "Hello", encryption_metadata: %{key_id: "KEY_1"}})
      %{content: "Hello", metadata: %{"encryption" => %{"key_id" => "KEY_1"}}}
  """
  @spec serialize_message(map()) :: map()
  def serialize_message(params) when is_map(params) do
    start_time = System.monotonic_time()

    with encryption_metadata <- extract_encryption_metadata(params),
         conversation_type <- get_conversation_type(params),
         {updated_params, status} <-
           process_encryption_metadata(
             params,
             encryption_metadata,
             conversation_type
           ) do
      # Add conversation type to telemetry metadata
      telemetry_metadata = build_telemetry_metadata(status, conversation_type)

      # Execute telemetry and return result
      execute_serialization_telemetry(start_time, telemetry_metadata)
      updated_params
    end
  end

  # Extracts encryption metadata from params, handling both atom and string keys
  defp extract_encryption_metadata(params) do
    Map.get(params, :encryption_metadata) ||
      Map.get(params, "encryption_metadata")
  end

  # Gets the conversation type based on the conversation_id in params
  defp get_conversation_type(params) do
    conversation_id =
      Map.get(params, :conversation_id) || Map.get(params, "conversation_id")

    if conversation_id do
      case Repo.get(Conversation, conversation_id) do
        %Conversation{conversation_type: type} -> type
        _ -> nil
      end
    else
      nil
    end
  end

  # Processes encryption metadata based on requirements and available data
  defp process_encryption_metadata(
         params,
         encryption_metadata,
         conversation_type
       ) do
    if is_nil(encryption_metadata) && conversation_type &&
         requires_encryption?(conversation_type) do
      # Encryption is required but missing - record warning
      metadata = %{
        warning: :missing_encryption_metadata,
        conversation_type: conversation_type,
        encryption_status: "disabled"
      }

      {params, metadata}
    else
      apply_encryption_metadata(params, encryption_metadata)
    end
  end

  # Applies encryption metadata to params if present
  defp apply_encryption_metadata(params, nil),
    do: {params, %{encryption_status: "disabled"}}

  defp apply_encryption_metadata(params, encryption_metadata) do
    # Normalize metadata keys to strings
    normalized_metadata =
      for {key, value} <- encryption_metadata, into: %{} do
        {to_string(key), value}
      end

    # Store encryption metadata in the message metadata
    existing_metadata = Map.get(params, :metadata, %{})

    updated_params =
      params
      |> Map.put(
        :metadata,
        Map.put(existing_metadata, "encryption", normalized_metadata)
      )

    {updated_params, %{encryption_status: "enabled"}}
  end

  # Builds telemetry metadata including conversation type if available
  defp build_telemetry_metadata(status_metadata, nil), do: status_metadata

  defp build_telemetry_metadata(status_metadata, conversation_type) do
    Map.put(status_metadata, :conversation_type, conversation_type)
  end

  # Executes telemetry for message serialization
  defp execute_serialization_telemetry(start_time, metadata) do
    measurements = %{
      start_time: start_time,
      end_time: System.monotonic_time(),
      duration_ms:
        System.convert_time_unit(
          System.monotonic_time() - start_time,
          :native,
          :millisecond
        )
    }

    :telemetry.execute(
      @telemetry_prefix ++ [:serialized],
      measurements,
      metadata
    )
  end

  @doc """
  Deserializes a message from the database format to include explicit encryption metadata.

  This function takes a message from the database and extracts any encryption metadata
  stored in the message's metadata field, adding it to a dedicated encryption_metadata field.

  ## Examples

      iex> deserialize_message(%Message{metadata: %{"encryption" => %{"key_id" => "KEY_1"}}})
      {:ok, %{encryption_metadata: %{key_id: "KEY_1"}}}
  """
  @spec deserialize_message(Message.t()) :: {:ok, map()} | {:error, atom()}
  def deserialize_message(%Message{} = message) do
    start_time = System.monotonic_time()

    # Extract encryption metadata if present
    encryption_from_metadata = get_in(message.metadata, ["encryption"])

    # Create the result structure
    {result, encryption_status} =
      if encryption_from_metadata do
        # Convert string keys to atoms for the API
        encryption_metadata =
          for {key, value} <- encryption_from_metadata, into: %{} do
            {String.to_existing_atom(key), value}
          end

        # Build the result with encryption metadata
        deserialized =
          Map.put(message, :encryption_metadata, encryption_metadata)

        {{:ok, deserialized}, "enabled"}
      else
        {{:ok, message}, "disabled"}
      end

    # Extract conversation type for telemetry
    conversation_type =
      case message.conversation do
        %Conversation{conversation_type: type} ->
          type

        _ ->
          case Repo.get(Conversation, message.conversation_id) do
            %Conversation{conversation_type: type} -> type
            _ -> nil
          end
      end

    # Prepare telemetry metadata
    telemetry_metadata = %{encryption_status: encryption_status}

    telemetry_metadata =
      if conversation_type do
        Map.put(telemetry_metadata, :conversation_type, conversation_type)
      else
        telemetry_metadata
      end

    # Emit telemetry
    measurements = %{
      start_time: start_time,
      end_time: System.monotonic_time(),
      duration_ms:
        System.convert_time_unit(
          System.monotonic_time() - start_time,
          :native,
          :millisecond
        )
    }

    :telemetry.execute(
      @telemetry_prefix ++ [:deserialized],
      measurements,
      telemetry_metadata
    )

    result
  end

  @doc """
  Simulates decryption of a message with error handling.

  This is a placeholder function that demonstrates how decryption failures
  should be handled, particularly for telemetry purposes. In a real implementation,
  this would use cryptographic libraries to decrypt the message content.

  ## Examples

      iex> decrypt_message(%Message{content: "VALID_ENCRYPTED_CONTENT"})
      {:ok, %{content: "Decrypted content"}}

      iex> decrypt_message(%Message{content: "INVALID_ENCRYPTED_CONTENT"})
      {:error, :decryption_failure}
  """
  @spec decrypt_message(Message.t()) :: {:ok, map()} | {:error, atom()}
  def decrypt_message(%Message{} = message) do
    start_time = System.monotonic_time()

    # In a real implementation, this would use proper cryptographic algorithms
    # and handle errors when decryption fails

    # Check if the message content contains the word "INVALID" to simulate decryption failure
    if String.contains?(message.content, "INVALID") do
      # Log the error (without sensitive data)
      Logger.error("Decryption failed for message_id=#{message.id}")

      # Emit telemetry for the error, avoiding including sensitive information
      measurements = %{
        start_time: start_time,
        end_time: System.monotonic_time(),
        duration_ms:
          System.convert_time_unit(
            System.monotonic_time() - start_time,
            :native,
            :millisecond
          )
      }

      telemetry_metadata = %{
        error_code: 603,
        error_type: "decryption_failure",
        message_id: message.id,
        conversation_id: message.conversation_id
        # Note: We deliberately avoid including key_id, ciphertext, etc.
      }

      # Ensure the telemetry event is sent before continuing
      :telemetry.execute(
        @telemetry_prefix ++ [:decryption_error],
        measurements,
        telemetry_metadata
      )

      {:error, :decryption_failure}
    else
      # In a real implementation, actually decrypt the message here
      {:ok, message}
    end
  end

  # Add a new pipeline step for encryption metadata processing
  defp process_encryption_metadata(%{error: _} = state), do: state

  defp process_encryption_metadata(state) do
    updated_params = serialize_message(state.params)
    %{state | params: updated_params}
  end
end
