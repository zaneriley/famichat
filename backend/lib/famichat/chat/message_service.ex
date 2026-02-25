defmodule Famichat.Chat.MessageService do
  @moduledoc """
  Message handling pipeline implementing:
  1. Validation -> 2. Authorization -> 3. Persistence -> 4. Notification
  """
  import Ecto.Query, warn: false
  alias Famichat.Repo
  alias Famichat.Chat.{Conversation, ConversationAccess, Message}
  alias Famichat.Crypto.MLS
  alias Famichat.Vault
  alias Famichat.Ecto.Pagination
  require Logger

  @default_preloads [:sender, :conversation]

  # Define conversation-type encryption requirements
  @encryption_requirements %{
    direct: true,
    family: true,
    group: true,
    self: true
  }

  # Telemetry prefixes
  @telemetry_prefix [:famichat, :message]
  @mls_snapshot_keys [
    "session_sender_storage",
    "session_recipient_storage",
    "session_sender_signer",
    "session_recipient_signer",
    "session_cache"
  ]
  @mls_snapshot_legacy_key "session_snapshot"
  @mls_snapshot_envelope_key "session_snapshot_encrypted"
  @mls_snapshot_envelope_format_key "session_snapshot_format"
  @mls_snapshot_envelope_format "vault_term_v1"

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
      query: nil
    }

    initial_state
    |> validate_conversation_id()
    |> check_conversation_exists()
    |> build_base_query()
    |> apply_pagination()
    |> execute_query()
    |> preload_associations()
    |> decrypt_messages_if_required()
    |> handle_result()
  end

  defp validate_conversation_id(%{conversation_id: nil} = state),
    do: Map.put(state, :error, :invalid_conversation_id)

  defp validate_conversation_id(state), do: state

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

  defp build_base_query(%{error: _} = state), do: state

  defp build_base_query(state) do
    query =
      from m in Message,
        where: m.conversation_id == ^state.conversation_id,
        order_by: [asc: m.inserted_at]

    Map.put(state, :query, query)
  end

  defp apply_pagination(%{error: _} = state), do: state

  defp apply_pagination(%{query: query, opts: opts} = state) do
    params =
      opts
      |> Keyword.take([:limit, :offset])
      |> Enum.into(%{})

    case Pagination.apply_or_default(query, params) do
      {:ok, paginated_query} ->
        Map.put(state, :query, paginated_query)

      {:error, {:invalid_pagination, _changeset} = reason} ->
        Map.put(state, :error, reason)
    end
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
      message: nil,
      mls_session_snapshot: nil
    }

    initial_state
    |> validate_required_fields()
    |> validate_sender()
    |> validate_conversation()
    |> verify_sender_in_conversation()
    |> encrypt_with_mls_if_required()
    |> process_encryption_metadata()
    |> build_changeset()
    |> persist_message()
    |> persist_mls_session_snapshot()
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
         from u in Famichat.Accounts.User,
           where: u.id == ^state.params.sender_id
       ) do
      state
    else
      Map.put(state, :error, :sender_not_found)
    end
  end

  defp validate_conversation(%{error: _} = state), do: state

  defp validate_conversation(
         %{params: %{conversation_id: conversation_id}} = state
       ) do
    case Repo.get(Conversation, conversation_id) do
      %Conversation{} = conversation ->
        Map.put(state, :conversation, conversation)

      nil ->
        Map.put(state, :error, :conversation_not_found)
    end
  end

  defp verify_sender_in_conversation(%{error: _} = state), do: state

  defp verify_sender_in_conversation(
         %{params: %{sender_id: sender_id}, conversation: conversation} = state
       ) do
    case ConversationAccess.authorize(conversation, sender_id, :send_message) do
      :ok ->
        state

      {:error, reason} ->
        Map.put(state, :error, reason)
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

  defp persist_mls_session_snapshot(%{error: _} = state), do: state

  defp persist_mls_session_snapshot(
         %{
           conversation: %Conversation{} = conversation,
           mls_session_snapshot: snapshot
         } = state
       )
       when is_map(snapshot) and snapshot != %{} do
    if mls_snapshot_from_conversation(conversation) == snapshot do
      state
    else
      case persist_mls_snapshot_to_conversation(conversation, snapshot) do
        {:ok, updated_conversation} ->
          Map.put(state, :conversation, updated_conversation)

        {:error, _reason} ->
          details = %{
            operation: :persist_mls_session_snapshot,
            reason: :conversation_update_failed
          }

          emit_mls_failure(:persist_state, :storage_inconsistent, details, state)

          Map.put(
            state,
            :error,
            {:mls_encryption_failed, :storage_inconsistent, details}
          )
      end
    end
  end

  defp persist_mls_session_snapshot(state), do: state

  defp notify_participants(%{error: _} = state), do: state

  defp notify_participants(state) do
    # Placeholder for real notification system
    :telemetry.execute([:famichat, :message, :sent], %{count: 1}, %{
      conversation_id: state.message.conversation_id,
      sender_id: state.message.sender_id
    })

    state
  end

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
  @spec serialize_message(map(), Conversation.t() | nil) :: map()
  def serialize_message(params, conversation \\ nil) when is_map(params) do
    start_time = System.monotonic_time()

    with encryption_metadata <- extract_encryption_metadata(params),
         conversation_type <-
           resolve_conversation_type(conversation, params),
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
  defp resolve_conversation_type(
         %Conversation{conversation_type: type},
         _params
       ),
       do: type

  defp resolve_conversation_type(nil, params) do
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
      count: 1,
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
      count: 1,
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
        count: 1,
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
    updated_params =
      serialize_message(state.params, Map.get(state, :conversation))

    %{state | params: updated_params}
  end

  defp encrypt_with_mls_if_required(%{error: _} = state), do: state

  defp encrypt_with_mls_if_required(
         %{conversation: %Conversation{conversation_type: conversation_type}} =
           state
       ) do
    if mls_enforcement_enabled?() and requires_encryption?(conversation_type) do
      case ensure_mls_runtime_ready() do
        :ok ->
          request =
            %{
              group_id: state.conversation.id,
              sender_id:
                Map.get(state.params, :sender_id) ||
                  Map.get(state.params, "sender_id"),
              body:
                Map.get(state.params, :content) ||
                  Map.get(state.params, "content")
            }
            |> maybe_put_mls_snapshot(
              mls_snapshot_from_conversation(state.conversation)
            )

          case MLS.create_application_message(request) do
            {:ok, payload} ->
              case extract_mls_ciphertext(payload) do
                {:ok, ciphertext} ->
                  updated_params =
                    apply_mls_ciphertext(state.params, payload, ciphertext)

                  state
                  |> Map.put(:params, updated_params)
                  |> maybe_store_mls_snapshot(payload)

                {:error, details} ->
                  emit_mls_failure(:encrypt, :crypto_failure, details, state)

                  Map.put(
                    state,
                    :error,
                    {:mls_encryption_failed, :crypto_failure, details}
                  )
              end

            {:error, code, details} ->
              emit_mls_failure(:encrypt, code, details, state)
              Map.put(state, :error, {:mls_encryption_failed, code, details})
          end

        {:error, code, details} ->
          emit_mls_failure(:encrypt, code, details, state)
          Map.put(state, :error, {:mls_encryption_failed, code, details})
      end
    else
      state
    end
  end

  defp decrypt_messages_if_required(%{error: _} = state), do: state
  defp decrypt_messages_if_required(%{result: []} = state), do: state

  defp decrypt_messages_if_required(
         %{result: messages, conversation_id: conversation_id} = state
       ) do
    if not mls_enforcement_enabled?() do
      state
    else
      case Repo.get(Conversation, conversation_id) do
        %Conversation{} = conversation
        when conversation.conversation_type in [:direct, :family, :group, :self] ->
          do_decrypt_messages(
            state,
            messages,
            conversation_id,
            conversation.conversation_type,
            conversation
          )

        _ ->
          state
      end
    end
  end

  defp do_decrypt_messages(
         state,
         messages,
         conversation_id,
         conversation_type,
         conversation
       ) do
    if requires_encryption?(conversation_type) do
      initial_snapshot =
        case conversation do
          %Conversation{} = value -> mls_snapshot_from_conversation(value)
          _ -> nil
        end

      case ensure_mls_runtime_ready() do
        :ok ->
          case Enum.reduce_while(
                 messages,
                 {:ok, [], initial_snapshot},
                 fn message, {:ok, acc, snapshot} ->
                   request =
                     %{
                       group_id: conversation_id,
                       message_id: message.id,
                       ciphertext: message.content
                     }
                     |> maybe_put_mls_snapshot(snapshot)

                   case MLS.process_incoming(request) do
                     {:ok, payload} ->
                       case extract_mls_plaintext(payload) do
                         {:ok, plaintext} ->
                           next_snapshot =
                             case extract_mls_snapshot(payload) do
                               {:ok, restored} -> restored
                               :none -> snapshot
                             end

                           {:cont,
                            {:ok, [%{message | content: plaintext} | acc],
                             next_snapshot}}

                         {:error, details} ->
                           {:halt, {:error, :crypto_failure, details, message}}
                       end

                     {:error, code, details} ->
                       {:halt, {:error, code, details, message}}
                   end
                 end
               ) do
            {:ok, decrypted_reversed, final_snapshot} ->
              updated_state =
                %{state | result: Enum.reverse(decrypted_reversed)}

              maybe_persist_decrypt_snapshot(
                updated_state,
                conversation,
                initial_snapshot,
                final_snapshot
              )

            {:error, code, details, message} ->
              emit_mls_failure(:decrypt, code, details, state, message)
              Map.put(state, :error, {:mls_decryption_failed, code, details})
          end

        {:error, code, details} ->
          emit_mls_failure(:decrypt, code, details, state)
          Map.put(state, :error, {:mls_decryption_failed, code, details})
      end
    else
      state
    end
  end

  defp extract_mls_ciphertext(payload) do
    ciphertext = Map.get(payload, :ciphertext) || Map.get(payload, "ciphertext")

    if is_binary(ciphertext) and byte_size(ciphertext) > 0 do
      {:ok, ciphertext}
    else
      {:error,
       %{
         operation: :create_application_message,
         reason: :missing_ciphertext
       }}
    end
  end

  defp extract_mls_plaintext(payload) do
    plaintext = Map.get(payload, :plaintext) || Map.get(payload, "plaintext")

    if is_binary(plaintext) do
      {:ok, plaintext}
    else
      {:error, %{operation: :process_incoming, reason: :missing_plaintext}}
    end
  end

  defp apply_mls_ciphertext(params, _payload, ciphertext) do
    existing_metadata =
      Map.get(params, :metadata) || Map.get(params, "metadata") || %{}

    mls_metadata =
      existing_metadata
      |> Map.put("mls", %{"encrypted" => true})

    params
    |> Map.put(:content, ciphertext)
    |> Map.delete("content")
    |> Map.put(:metadata, mls_metadata)
    |> Map.delete("metadata")
  end

  defp maybe_store_mls_snapshot(state, payload) do
    case extract_mls_snapshot(payload) do
      {:ok, snapshot} ->
        Map.put(state, :mls_session_snapshot, snapshot)

      :none ->
        state
    end
  end

  defp maybe_put_mls_snapshot(request, snapshot)
       when is_map(snapshot) and snapshot != %{} do
    Map.merge(request, snapshot)
  end

  defp maybe_put_mls_snapshot(request, _snapshot), do: request

  defp mls_snapshot_from_conversation(%Conversation{metadata: metadata}) do
    with %{} = mls <- Map.get(metadata || %{}, "mls") do
      case Map.get(mls, @mls_snapshot_envelope_key) do
        envelope when is_binary(envelope) and envelope != "" ->
          case decode_mls_snapshot_envelope(envelope) do
            {:ok, snapshot} -> snapshot
            :none -> legacy_snapshot_from_metadata(mls)
          end

        _ ->
          legacy_snapshot_from_metadata(mls)
      end
    else
      _ -> nil
    end
  end

  defp extract_mls_snapshot(payload) do
    normalize_mls_snapshot(payload)
  end

  defp maybe_persist_decrypt_snapshot(
         state,
         %Conversation{} = conversation,
         initial_snapshot,
         final_snapshot
       )
       when is_map(final_snapshot) and final_snapshot != initial_snapshot do
    case persist_mls_snapshot_to_conversation(conversation, final_snapshot) do
      {:ok, updated_conversation} ->
        Map.put(state, :conversation, updated_conversation)

      {:error, _changeset} ->
        details = %{
          operation: :persist_mls_session_snapshot,
          reason: :conversation_update_failed
        }

        emit_mls_failure(:persist_state, :storage_inconsistent, details, state)

        Map.put(
          state,
          :error,
          {:mls_decryption_failed, :storage_inconsistent, details}
        )
    end
  end

  defp maybe_persist_decrypt_snapshot(state, _conversation, _initial, _final),
    do: state

  defp persist_mls_snapshot_to_conversation(
         %Conversation{} = conversation,
         snapshot
       ) do
    with {:ok, envelope} <- encode_mls_snapshot_envelope(snapshot) do
      metadata = conversation.metadata || %{}
      mls_metadata = Map.get(metadata, "mls", %{})

      updated_mls_metadata =
        mls_metadata
        |> Map.put(@mls_snapshot_envelope_key, envelope)
        |> Map.put(
          @mls_snapshot_envelope_format_key,
          @mls_snapshot_envelope_format
        )
        |> Map.delete(@mls_snapshot_legacy_key)

      updated_metadata = Map.put(metadata, "mls", updated_mls_metadata)

      conversation
      |> Conversation.update_changeset(%{metadata: updated_metadata})
      |> Repo.update()
    end
  end

  defp encode_mls_snapshot_envelope(snapshot) do
    try do
      snapshot
      |> :erlang.term_to_binary([:compressed])
      |> Vault.encrypt!()
      |> Base.encode64()
      |> then(&{:ok, &1})
    rescue
      _ -> {:error, :snapshot_envelope_encode_failed}
    end
  end

  defp decode_mls_snapshot_envelope(envelope) when is_binary(envelope) do
    try do
      with {:ok, encrypted} <- Base.decode64(envelope),
           decrypted when is_binary(decrypted) <- Vault.decrypt!(encrypted),
           decoded <- :erlang.binary_to_term(decrypted, [:safe]),
           {:ok, snapshot} <- normalize_mls_snapshot(decoded) do
        {:ok, snapshot}
      else
        _ -> :none
      end
    rescue
      _ -> :none
    end
  end

  defp decode_mls_snapshot_envelope(_), do: :none

  defp legacy_snapshot_from_metadata(mls) when is_map(mls) do
    case Map.get(mls, @mls_snapshot_legacy_key) do
      %{} = snapshot ->
        case normalize_mls_snapshot(snapshot) do
          {:ok, normalized} -> normalized
          :none -> nil
        end

      _ ->
        nil
    end
  end

  defp legacy_snapshot_from_metadata(_), do: nil

  defp normalize_mls_snapshot(payload) when is_map(payload) do
    snapshot =
      Enum.reduce(@mls_snapshot_keys, %{}, fn key, acc ->
        case snapshot_value(payload, key) do
          value when is_binary(value) -> Map.put(acc, key, value)
          _ -> acc
        end
      end)

    if map_size(snapshot) == length(@mls_snapshot_keys) do
      {:ok, snapshot}
    else
      :none
    end
  end

  defp normalize_mls_snapshot(_), do: :none

  defp snapshot_value(payload, key) do
    case key do
      "session_sender_storage" ->
        Map.get(payload, "session_sender_storage") ||
          Map.get(payload, :session_sender_storage)

      "session_recipient_storage" ->
        Map.get(payload, "session_recipient_storage") ||
          Map.get(payload, :session_recipient_storage)

      "session_sender_signer" ->
        Map.get(payload, "session_sender_signer") ||
          Map.get(payload, :session_sender_signer)

      "session_recipient_signer" ->
        Map.get(payload, "session_recipient_signer") ||
          Map.get(payload, :session_recipient_signer)

      "session_cache" ->
        Map.get(payload, "session_cache") || Map.get(payload, :session_cache)

      _ ->
        nil
    end
  end

  defp emit_mls_failure(action, code, details, state, message \\ nil) do
    params = Map.get(state, :params, %{})

    metadata = %{
      action: action,
      error_code: code,
      conversation_id:
        Map.get(params, :conversation_id) ||
          Map.get(params, "conversation_id") || Map.get(state, :conversation_id)
    }

    metadata =
      if message do
        Map.put(metadata, :message_id, message.id)
      else
        metadata
      end

    metadata =
      case Map.get(details, :reason) || Map.get(details, "reason") do
        reason when is_atom(reason) or is_binary(reason) ->
          Map.put(metadata, :reason, reason)

        _ ->
          metadata
      end

    :telemetry.execute(
      [:famichat, :message, :mls_failure],
      %{count: 1},
      metadata
    )
  end

  defp mls_enforcement_enabled? do
    Application.get_env(:famichat, :mls_enforcement, false)
  end

  defp ensure_mls_runtime_ready do
    case MLS.nif_health() do
      {:ok, payload} ->
        status = Map.get(payload, :status) || Map.get(payload, "status")

        if status in [:ok, :healthy, "ok", "healthy"] do
          :ok
        else
          {:error, :unsupported_capability,
           %{
             operation: :nif_health,
             reason: :mls_runtime_not_ready,
             status: status
           }}
        end

      {:error, code, details} ->
        {:error, code, Map.put_new(details, :operation, :nif_health)}
    end
  end
end
