defmodule Famichat.Chat.MessageService do
  @moduledoc """
  Message handling pipeline implementing:
  1. Validation -> 2. Authorization -> 3. Persistence -> 4. Notification
  """
  import Ecto.Query, warn: false
  import Ecto.Changeset
  alias Famichat.Repo

  alias Famichat.Chat.{
    Conversation,
    ConversationAccess,
    ConversationSecurityPolicy,
    ConversationSecurityStateStore,
    Message
  }

  alias Famichat.Crypto.MLS
  alias Famichat.Crypto.MLS.SnapshotMac
  alias Famichat.Vault
  alias Famichat.Ecto.Pagination
  require Logger

  @default_preloads [:sender, :conversation]

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
  @mls_state_protocol "mls"
  @mls_recovery_required_reasons [
    "missing_group_state",
    "incomplete_session_snapshot",
    "group_load_failed",
    "deleted_key_material",
    "state_decode_failed"
  ]

  @allowed_encryption_metadata_keys ~w(key_id algorithm version version_tag encryption_flag ciphersuite epoch)

  # Snapshot persistence invariant:
  #
  # MLS snapshots are persisted to the database ONLY on epoch-advancing
  # operations (Add, Remove, Commit via ConversationSecurityLifecycle). Between
  # epoch advances, the in-memory DashMap in the Rust NIF (`GROUP_SESSIONS`) is
  # the authoritative live state.
  #
  # Application messages (send_message/1) do NOT advance the MLS epoch and
  # therefore do NOT write the snapshot to the database. Writing a 10-80 KB
  # TOAST-encoded encrypted blob per application message would produce
  # pathological write amplification (20 MB+ per conversation per day at
  # typical family-scale traffic).
  #
  # Recovery path: if the server restarts between epoch advances, the NIF state
  # is lost but the database holds the last epoch-advancing snapshot.
  # ConversationSecurityRecoveryLifecycle reloads from that snapshot and
  # re-establishes the group session before any subsequent message operations.

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
    case get_conversation_messages_page(conversation_id, opts) do
      {:ok, %{messages: messages}} -> {:ok, messages}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cursor-aware message retrieval that returns page metadata for reconnect/catch-up.
  """
  @spec get_conversation_messages_page(Ecto.UUID.t(), Keyword.t()) ::
          {:ok,
           %{
             messages: [Message.t()],
             has_more: boolean(),
             next_cursor: Ecto.UUID.t() | nil
           }}
          | {:error, atom()}
          | {:error, {:invalid_pagination, Ecto.Changeset.t()}}
  def get_conversation_messages_page(conversation_id, opts \\ []) do
    initial_state = %{
      conversation_id: conversation_id,
      opts: opts,
      query: nil,
      base_query: nil,
      mode: :page,
      after_cursor_id: nil,
      page_limit: nil,
      page_offset: nil
    }

    initial_state
    |> validate_conversation_id()
    |> validate_cursor_option()
    |> validate_cursor_offset_combination()
    |> check_conversation_exists()
    |> build_base_query()
    |> apply_after_cursor()
    |> apply_pagination()
    |> execute_query()
    |> compute_has_more()
    |> preload_associations()
    |> decrypt_messages_if_required()
    |> assign_next_cursor()
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
        order_by: [asc: m.inserted_at, asc: m.id]

    Map.put(state, :query, query)
  end

  defp validate_cursor_option(%{error: _} = state), do: state

  defp validate_cursor_option(%{opts: opts} = state) do
    after_value = opts[:after]

    case normalize_after_cursor(after_value) do
      {:ok, after_cursor_id} ->
        Map.put(state, :after_cursor_id, after_cursor_id)

      {:error, changeset} ->
        Map.put(state, :error, {:invalid_pagination, changeset})
    end
  end

  defp validate_cursor_offset_combination(%{error: _} = state), do: state

  defp validate_cursor_offset_combination(%{after_cursor_id: nil} = state),
    do: state

  defp validate_cursor_offset_combination(%{opts: opts} = state) do
    if Keyword.has_key?(opts, :offset) and not is_nil(opts[:offset]) do
      Map.put(
        state,
        :error,
        {:invalid_pagination,
         pagination_error_changeset(
           :offset,
           "must be empty when after is provided"
         )}
      )
    else
      state
    end
  end

  defp apply_after_cursor(%{error: _} = state), do: state
  defp apply_after_cursor(%{after_cursor_id: nil} = state), do: state

  defp apply_after_cursor(
         %{after_cursor_id: after_cursor_id, query: query, conversation_id: cid} =
           state
       ) do
    case cursor_for_conversation(after_cursor_id, cid) do
      {:ok, %{id: cursor_id, inserted_at: inserted_at}} ->
        filtered_query =
          from m in query,
            where:
              m.inserted_at > ^inserted_at or
                (m.inserted_at == ^inserted_at and m.id > ^cursor_id)

        %{state | query: filtered_query}

      :error ->
        Map.put(
          state,
          :error,
          {:invalid_pagination,
           pagination_error_changeset(
             :after,
             "does not belong to this conversation"
           )}
        )
    end
  end

  defp apply_pagination(%{error: _} = state), do: state

  defp apply_pagination(%{query: query, opts: opts} = state) do
    params =
      opts
      |> Keyword.take([:limit, :offset])
      |> Enum.into(%{})

    case Pagination.apply_or_default(query, params) do
      {:ok, paginated_query} ->
        %{
          state
          | query: paginated_query,
            base_query: query,
            page_limit: pagination_limit(params),
            page_offset: pagination_offset(params)
        }

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

  defp compute_has_more(%{error: _} = state), do: state

  defp compute_has_more(
         %{
           mode: :page,
           result: result,
           page_limit: limit,
           page_offset: offset,
           base_query: base_query
         } = state
       )
       when is_list(result) and is_integer(limit) and is_integer(offset) do
    has_more =
      if length(result) < limit do
        false
      else
        Repo.exists?(from m in base_query, offset: ^(offset + limit), limit: 1)
      end

    Map.put(state, :has_more, has_more)
  end

  defp compute_has_more(state), do: Map.put(state, :has_more, false)

  defp preload_associations(%{error: _} = state), do: state

  defp preload_associations(state) do
    # Always include :conversation in the preload list so that
    # deserialize_message/1 can read conversation_type for telemetry without
    # issuing a per-message Repo.get (N+1). Caller-supplied preloads are
    # merged with this requirement; duplicates are deduplicated.
    requested = state.opts[:preload] || @default_preloads
    preloads = Enum.uniq([:conversation | requested])
    Map.update!(state, :result, &Repo.preload(&1, preloads))
  end

  defp assign_next_cursor(%{error: _} = state), do: state

  defp assign_next_cursor(%{mode: :page, result: result} = state)
       when is_list(result) do
    next_cursor =
      case List.last(result) do
        %Message{id: id} -> id
        _ -> nil
      end

    Map.put(state, :next_cursor, next_cursor)
  end

  defp assign_next_cursor(state), do: state

  defp handle_result(%{error: error}), do: {:error, error}

  defp handle_result(%{mode: :page, result: messages} = state) do
    {:ok,
     %{
       messages: messages,
       has_more: Map.get(state, :has_more, false),
       next_cursor: Map.get(state, :next_cursor)
     }}
  end

  defp handle_result(%{message: message}), do: {:ok, message}
  defp handle_result(%{result: result}), do: {:ok, result}

  defp normalize_after_cursor(value) when value in [nil, ""], do: {:ok, nil}

  defp normalize_after_cursor(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      {:ok, nil}
    else
      case Ecto.UUID.cast(value) do
        {:ok, uuid} ->
          {:ok, uuid}

        :error ->
          {:error, pagination_error_changeset(:after, "is invalid")}
      end
    end
  end

  defp normalize_after_cursor(_value) do
    {:error, pagination_error_changeset(:after, "is invalid")}
  end

  defp cursor_for_conversation(message_id, conversation_id) do
    query =
      from m in Message,
        where: m.id == ^message_id and m.conversation_id == ^conversation_id,
        select: %{id: m.id, inserted_at: m.inserted_at}

    case Repo.one(query) do
      nil -> :error
      cursor -> {:ok, cursor}
    end
  end

  defp pagination_limit(params) do
    params
    |> get_param(:limit)
    |> normalize_positive_integer(20)
  end

  defp pagination_offset(params) do
    params
    |> get_param(:offset)
    |> normalize_non_negative_integer(0)
  end

  defp get_param(params, key) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  defp normalize_positive_integer(nil, default), do: default

  defp normalize_positive_integer(value, _default) when is_integer(value),
    do: value

  defp normalize_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp normalize_positive_integer(_value, default), do: default

  defp normalize_non_negative_integer(nil, default), do: default

  defp normalize_non_negative_integer(value, _default) when is_integer(value),
    do: value

  defp normalize_non_negative_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp normalize_non_negative_integer(_value, default), do: default

  defp pagination_error_changeset(field, message) do
    {%{}, %{after: :string, offset: :integer}}
    |> cast(%{}, [:after, :offset])
    |> add_error(field, message)
  end

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
      mls_session_snapshot: nil,
      mls_state_lock_version: nil,
      mls_state_epoch: 0,
      mls_pending_commit: nil
    }

    initial_state
    |> validate_required_fields()
    |> validate_sender()
    |> validate_conversation()
    |> verify_sender_in_conversation()
    |> load_mls_state_for_send()
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

  defp load_mls_state_for_send(%{error: _} = state), do: state

  defp load_mls_state_for_send(
         %{conversation: %Conversation{conversation_type: conversation_type}} =
           state
       ) do
    if mls_enforcement_enabled?() and requires_encryption?(conversation_type) do
      case load_mls_snapshot_with_lock(state.conversation) do
        {:ok, loaded_state} ->
          state
          |> Map.put(:mls_session_snapshot, loaded_state.snapshot)
          |> Map.put(:mls_state_lock_version, loaded_state.lock_version)
          |> Map.put(:mls_state_epoch, loaded_state.epoch)
          |> Map.put(:mls_pending_commit, loaded_state.pending_commit)

        {:error, code, details} ->
          emit_mls_failure(:load_state, code, details, state)
          Map.put(state, :error, {:mls_encryption_failed, code, details})
      end
    else
      state
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
    # Application messages do NOT persist the MLS snapshot (see invariant comment
    # near @allowed_encryption_metadata_keys). Only the message row itself is
    # written here. Snapshot persistence happens exclusively in epoch-advancing
    # paths (ConversationSecurityLifecycle.merge_pending_commit/2).
    case Repo.insert(state.changeset) do
      {:ok, message} ->
        Map.put(state, :message, message)

      {:error, changeset} ->
        Map.put(state, :error, changeset)
    end
  end

  # persist_mls_session_snapshot/1 is intentionally a no-op for the send path.
  # Application messages do not advance the MLS epoch; the NIF DashMap holds
  # the authoritative in-memory state between epoch advances. Persisting the
  # snapshot on every send would write 10-80 KB of TOAST-encoded encrypted data
  # per message — pathological write amplification at family-scale traffic.
  # Snapshot writes happen only in ConversationSecurityLifecycle.merge_pending_commit/2.
  defp persist_mls_session_snapshot(%{error: _} = state), do: state
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
    ConversationSecurityPolicy.requires_encryption?(conversation_type)
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
        encryption_metadata =
          encryption_from_metadata
          |> Map.take(@allowed_encryption_metadata_keys)
          |> Map.new(fn {key, value} -> {String.to_atom(key), value} end)

        # Build the result with encryption metadata
        deserialized =
          Map.put(message, :encryption_metadata, encryption_metadata)

        {{:ok, deserialized}, "enabled"}
      else
        {{:ok, message}, "disabled"}
      end

    # Extract conversation type for telemetry.
    # The conversation association MUST be preloaded before calling this
    # function. A fallback Repo.get is intentionally not provided here —
    # if the association is not loaded we raise immediately so the N+1
    # surfaces at development time rather than silently in production.
    conversation_type =
      case message.conversation do
        %Conversation{conversation_type: type} ->
          type

        %Ecto.Association.NotLoaded{} ->
          raise ArgumentError,
                "deserialize_message/1 requires :conversation to be preloaded " <>
                  "(message id=#{message.id}). Add :conversation to the preload list " <>
                  "in the caller to avoid N+1 queries."

        _ ->
          nil
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
            |> maybe_put_mls_snapshot(state.mls_session_snapshot)
            |> maybe_put_pending_proposals(state.mls_pending_commit)

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
              {normalized_code, normalized_details} =
                normalize_mls_error(code, details)

              emit_mls_failure(
                :encrypt,
                normalized_code,
                normalized_details,
                state
              )

              Map.put(
                state,
                :error,
                {:mls_encryption_failed, normalized_code, normalized_details}
              )
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
      case load_mls_snapshot_with_lock(conversation) do
        {:ok, loaded_state} ->
          initial_snapshot = loaded_state.snapshot
          initial_lock_version = loaded_state.lock_version
          initial_epoch = loaded_state.epoch

          # R2: Normalize the snapshot once before entering the reduce loop.
          # normalize_mls_snapshot/1 only validates the presence of 5 required
          # keys (~50µs); it does NOT do binary_to_term or large deserialization.
          # The actual saving is ~950µs of CPU validation time per 20-message page
          # (19 × 50µs avoided). Each iteration receives the already-normalized
          # map via the accumulator. When the MLS epoch advances mid-loop we reload
          # the snapshot from the DB (the only path that triggers re-normalization)
          # so the rest of the loop uses fresh state without redundant key checks.
          initial_decoded_snapshot =
            case initial_snapshot do
              s when is_map(s) and s != %{} ->
                case normalize_mls_snapshot(s) do
                  {:ok, decoded} -> decoded
                  :none -> nil
                end

              _ ->
                nil
            end

          case ensure_mls_runtime_ready() do
            :ok ->
              # R4: Parallelize the decrypt loop.  All messages in a page
              # share the same snapshot/epoch at the point of fetching, so
              # each task receives a copy of initial_decoded_snapshot and
              # calls MLS.process_incoming independently.  Task.async_stream
              # preserves input order in its result stream.
              #
              # Eagerly materialise the stream into a list so we can do two
              # cheap passes (error-check + epoch-scan) without re-running
              # the tasks.
              raw_results =
                messages
                |> Task.async_stream(
                  fn message ->
                    decrypt_one_message(
                      message,
                      conversation_id,
                      initial_decoded_snapshot,
                      initial_epoch
                    )
                  end,
                  max_concurrency: 4,
                  # A single NIF decrypt takes ~7ms; 500ms is a 70× safety
                  # margin.  Timeouts here indicate process failures, not
                  # slow crypto.
                  timeout: 500,
                  on_timeout: :kill_task,
                  ordered: true
                )
                # Materialize all task results eagerly before inspecting:
                # tasks already ran in parallel; Enum.to_list() just collects
                # results.  This lets reduce_while short-circuit without
                # re-spawning tasks.
                |> Enum.to_list()

              # First pass: collect decrypted messages in order; halt on the
              # first error to preserve the reduce_while short-circuit
              # contract.
              collected =
                Enum.reduce_while(raw_results, {:ok, []}, fn
                  {:ok, {:ok, decrypted_msg, _msg_epoch, _msg_snapshot}},
                  {:ok, acc} ->
                    {:cont, {:ok, [decrypted_msg | acc]}}

                  {:ok, {:error, code, details, message}}, {:ok, _acc} ->
                    {:halt, {:error, code, details, message}}

                  {:exit, reason}, {:ok, _acc} ->
                    # Task exited (timeout, crash, or kill) — not a crypto
                    # error.  Use :process_failed to distinguish a task-level
                    # failure from :crypto_failure returned by the NIF itself.
                    {:halt,
                     {:error, :process_failed,
                      %{operation: :process_incoming, reason: reason}, nil}}
                end)

              case collected do
                {:ok, decrypted_reversed} ->
                  # Second pass: determine final epoch and snapshot.  If any
                  # message advanced the epoch, reload from DB once (same
                  # semantics as the sequential loop's epoch-advance branch).
                  {final_epoch, final_snapshot} =
                    resolve_final_epoch_and_snapshot(
                      raw_results,
                      initial_epoch,
                      initial_decoded_snapshot,
                      conversation
                    )

                  updated_state =
                    %{state | result: Enum.reverse(decrypted_reversed)}

                  # Use initial_decoded_snapshot as the baseline for change
                  # detection so the comparison is always between two values
                  # that went through the same normalize_mls_snapshot path.
                  baseline_snapshot =
                    initial_decoded_snapshot || initial_snapshot

                  maybe_persist_decrypt_snapshot(
                    updated_state,
                    conversation,
                    baseline_snapshot,
                    final_snapshot,
                    initial_lock_version,
                    initial_epoch,
                    final_epoch
                  )

                {:error, code, details, message} ->
                  emit_mls_failure(:decrypt, code, details, state, message)

                  Map.put(
                    state,
                    :error,
                    {:mls_decryption_failed, code, details}
                  )
              end

            {:error, code, details} ->
              emit_mls_failure(:decrypt, code, details, state)
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

  # R4: Per-message decrypt worker.  Each Task.async_stream task calls this
  # function with the *same* initial_decoded_snapshot so all tasks can run
  # concurrently.  The NIF operates on per-message context inside Rust's
  # DashMap, so concurrent calls for different message_ids of the same group
  # are safe.
  #
  # Returns:
  #   {:ok, decrypted_message, msg_epoch, msg_snapshot}
  #   {:error, code, details, message}
  defp decrypt_one_message(message, conversation_id, snapshot, initial_epoch) do
    request =
      %{
        group_id: conversation_id,
        message_id: message.id,
        ciphertext: message.content
      }
      |> maybe_put_mls_snapshot(snapshot)

    # Safe to run concurrently for different message_ids of the same group:
    # the Rust NIF uses DashMap (per-shard locking) and releases the shard
    # lock before serialization work (N6 pattern).  Concurrent tasks
    # serialize only on the sub-millisecond extract phase, not the slow
    # hex-encode phase.
    case MLS.process_incoming(request) do
      {:ok, payload} ->
        case extract_mls_plaintext(payload) do
          {:ok, plaintext} ->
            msg_epoch = extract_mls_epoch(payload) || initial_epoch

            msg_snapshot =
              case extract_mls_snapshot(payload) do
                {:ok, restored} -> restored
                :none -> snapshot
              end

            {:ok, %{message | content: plaintext}, msg_epoch, msg_snapshot}

          {:error, details} ->
            {:error, :crypto_failure, details, message}
        end

      {:error, code, details} ->
        {normalized_code, normalized_details} =
          normalize_mls_error(code, details)

        {:error, normalized_code, normalized_details, message}
    end
  end

  # R4: After a parallel decrypt pass, determine the final epoch and snapshot
  # to use for persisting state.  raw_results is the already-materialised
  # list from Enum.to_list(Task.async_stream(...)).  If any message advanced
  # the epoch relative to initial_epoch, reload from DB once (same semantics
  # as the sequential loop's epoch-advance branch).  Otherwise, take the last
  # per-message snapshot from the list.
  defp resolve_final_epoch_and_snapshot(
         raw_results,
         initial_epoch,
         initial_decoded_snapshot,
         conversation
       ) do
    # Walk results to find the max epoch and the last per-message snapshot.
    {max_epoch, last_snapshot} =
      Enum.reduce(raw_results, {initial_epoch, initial_decoded_snapshot}, fn
        {:ok, {:ok, _msg, msg_epoch, msg_snapshot}}, {acc_epoch, _acc_snap} ->
          new_epoch = if msg_epoch > acc_epoch, do: msg_epoch, else: acc_epoch
          {new_epoch, msg_snapshot}

        _other, acc ->
          acc
      end)

    if max_epoch != initial_epoch do
      # Epoch advanced somewhere in the batch: reload snapshot from DB once,
      # matching the sequential loop's behaviour.
      case load_mls_snapshot_with_lock(conversation) do
        {:ok, refreshed} -> {max_epoch, refreshed.snapshot}
        _ -> {max_epoch, last_snapshot}
      end
    else
      {max_epoch, last_snapshot}
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
        state
        |> Map.put(:mls_session_snapshot, snapshot)
        |> maybe_store_mls_epoch(payload)

      :none ->
        maybe_store_mls_epoch(state, payload)
    end
  end

  defp maybe_store_mls_epoch(state, payload) do
    case extract_mls_epoch(payload) do
      epoch when is_integer(epoch) and epoch >= 0 ->
        Map.put(state, :mls_state_epoch, epoch)

      _ ->
        state
    end
  end

  defp maybe_put_mls_snapshot(request, snapshot)
       when is_map(snapshot) and snapshot != %{} do
    case Enum.find(@mls_snapshot_keys, fn k ->
           not is_binary(Map.get(snapshot, k))
         end) do
      nil ->
        Map.merge(request, snapshot)

      missing_key ->
        Logger.error(
          "MLS snapshot failed key/type validation before NIF call; " <>
            "missing_or_invalid=#{inspect(missing_key)}"
        )

        {:error, :invalid_snapshot, %{missing_or_invalid: missing_key}}
    end
  end

  defp maybe_put_mls_snapshot(request, _snapshot), do: request

  defp maybe_put_pending_proposals(request, pending_commit)
       when is_map(pending_commit) do
    Map.put(request, :pending_proposals, true)
  end

  defp maybe_put_pending_proposals(request, _pending_commit), do: request

  defp load_mls_snapshot_with_lock(%Conversation{} = conversation) do
    case ConversationSecurityStateStore.load(conversation.id) do
      {:ok, persisted} ->
        case verify_snapshot_mac(conversation.id, persisted) do
          :ok ->
            {:ok,
             %{
               snapshot: persisted.state,
               lock_version: persisted.lock_version,
               epoch: persisted.epoch,
               pending_commit: persisted.pending_commit
             }}

          {:error, reason} ->
            Logger.error(
              "Snapshot MAC verification failed for conversation #{conversation.id}: #{inspect(reason)}"
            )

            {:error, :snapshot_integrity_failed,
             %{reason: reason, conversation_id: conversation.id}}
        end

      {:error, :not_found, _details} ->
        case legacy_mls_snapshot_from_conversation_metadata(conversation) do
          %{} = legacy_snapshot ->
            migrate_legacy_snapshot_if_present(conversation, legacy_snapshot)

          _ ->
            {:ok,
             %{
               snapshot: nil,
               lock_version: nil,
               epoch: 0,
               pending_commit: nil
             }}
        end

      {:error, code, details} ->
        {:error, map_state_store_error_code(code), details}
    end
  end

  defp migrate_legacy_snapshot_if_present(
         %Conversation{} = conversation,
         snapshot
       )
       when is_map(snapshot) and snapshot != %{} do
    attrs = %{protocol: @mls_state_protocol, state: snapshot, epoch: 0}
    migrate_snapshot_with_retries(conversation, attrs, 0)
  end

  defp migrate_snapshot_with_retries(
         %Conversation{} = conversation,
         attrs,
         attempt
       )
       when attempt < 5 do
    case ConversationSecurityStateStore.upsert(conversation.id, attrs, nil) do
      {:ok, persisted} ->
        {:ok,
         %{
           snapshot: persisted.state,
           lock_version: persisted.lock_version,
           epoch: persisted.epoch,
           pending_commit: persisted.pending_commit
         }}

      {:error, :stale_state, _details} when attempt < 4 ->
        backoff_ms = trunc(:math.pow(2, attempt) * 50)
        Process.sleep(backoff_ms)
        migrate_snapshot_with_retries(conversation, attrs, attempt + 1)

      {:error, :stale_state, _details} ->
        case ConversationSecurityStateStore.load(conversation.id) do
          {:ok, persisted} ->
            {:ok,
             %{
               snapshot: persisted.state,
               lock_version: persisted.lock_version,
               epoch: persisted.epoch,
               pending_commit: persisted.pending_commit
             }}

          {:error, code, details} ->
            {:error, map_state_store_error_code(code), details}
        end

      {:error, code, details} ->
        {:error, map_state_store_error_code(code), details}
    end
  end

  defp migrate_snapshot_with_retries(_conversation, _attrs, _attempt) do
    {:error, :max_retries_exceeded,
     %{reason: :migrate_snapshot_retries_exhausted}}
  end

  # Verifies the snapshot MAC stored alongside the persisted state.
  # nil MAC (rows written before the migration) are rejected with a warning
  # to prevent tampered or pre-migration snapshots from being silently accepted.
  defp verify_snapshot_mac(
         conversation_id,
         %{snapshot_mac: nil, epoch: epoch} = persisted
       ) do
    Logger.warning(
      "Snapshot MAC is nil for conversation #{conversation_id} epoch=#{epoch}; " <>
        "rejecting — row predates MAC migration or key is unconfigured"
    )

    _ = persisted
    {:error, :snapshot_mac_missing}
  end

  defp verify_snapshot_mac(conversation_id, %{
         snapshot_mac: stored_mac,
         state: state,
         epoch: epoch
       })
       when is_binary(stored_mac) and is_map(state) do
    mac_payload =
      state
      |> Map.put("group_id", conversation_id)
      |> Map.put("epoch", to_string(epoch))

    case SnapshotMac.verify(
           mac_payload,
           stored_mac,
           SnapshotMac.configured_key!()
         ) do
      :ok ->
        :ok

      {:error, :mac_mismatch} ->
        {:error, :snapshot_integrity_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_snapshot_mac(_conversation_id, _persisted), do: :ok

  defp map_state_store_error_code(:stale_state), do: :storage_inconsistent

  defp map_state_store_error_code(:state_encode_failed),
    do: :storage_inconsistent

  defp map_state_store_error_code(:state_decode_failed),
    do: :storage_inconsistent

  defp map_state_store_error_code(:invalid_input), do: :storage_inconsistent
  defp map_state_store_error_code(code), do: code

  defp normalize_mls_error(code, details) when is_map(details) do
    reason = Map.get(details, :reason) || Map.get(details, "reason")

    if code == :storage_inconsistent and recovery_required_reason?(reason) do
      {:recovery_required, details}
    else
      {code, details}
    end
  end

  defp normalize_mls_error(code, details), do: {code, details}

  defp recovery_required_reason?(reason) when is_atom(reason) do
    Atom.to_string(reason) in @mls_recovery_required_reasons
  end

  defp recovery_required_reason?(reason) when is_binary(reason) do
    reason in @mls_recovery_required_reasons
  end

  defp recovery_required_reason?(_reason), do: false

  defp legacy_mls_snapshot_from_conversation_metadata(%Conversation{
         metadata: metadata
       }) do
    with %{} = mls <- Map.get(metadata || %{}, "mls") do
      case Map.get(mls, @mls_snapshot_envelope_key) do
        envelope when is_binary(envelope) and envelope != "" ->
          envelope_format =
            Map.get(mls, @mls_snapshot_envelope_format_key)

          case decode_mls_snapshot_envelope(
                 envelope,
                 envelope_format
               ) do
            {:ok, snapshot} -> snapshot
            :none -> legacy_mls_snapshot_from_metadata(mls)
          end

        _ ->
          legacy_mls_snapshot_from_metadata(mls)
      end
    else
      _ -> nil
    end
  end

  defp extract_mls_snapshot(payload) do
    normalize_mls_snapshot(payload)
  end

  defp extract_mls_epoch(payload) when is_map(payload) do
    value = Map.get(payload, :epoch) || Map.get(payload, "epoch")

    if is_integer(value) and value >= 0 do
      value
    else
      nil
    end
  end

  defp extract_mls_epoch(_), do: nil

  defp maybe_persist_decrypt_snapshot(
         state,
         %Conversation{} = conversation,
         initial_snapshot,
         final_snapshot,
         initial_lock_version,
         initial_epoch,
         final_epoch
       ) do
    should_persist_snapshot =
      is_map(final_snapshot) and
        (final_snapshot != initial_snapshot or final_epoch != initial_epoch)

    if should_persist_snapshot do
      attrs = %{
        protocol: @mls_state_protocol,
        state: final_snapshot,
        epoch: final_epoch || initial_epoch || 0,
        pending_commit: Map.get(state, :mls_pending_commit)
      }

      case ConversationSecurityStateStore.upsert(
             conversation.id,
             attrs,
             initial_lock_version
           ) do
        {:ok, persisted} ->
          state
          |> Map.put(:mls_session_snapshot, persisted.state)
          |> Map.put(:mls_state_lock_version, persisted.lock_version)
          |> Map.put(:mls_state_epoch, persisted.epoch)

        {:error, code, details} ->
          mapped_code = map_state_store_error_code(code)
          emit_mls_failure(:persist_state, mapped_code, details, state)

          Map.put(
            state,
            :error,
            {:mls_decryption_failed, mapped_code, details}
          )
      end
    else
      state
    end
  end

  defp decode_mls_snapshot_envelope(envelope, envelope_format)
       when is_binary(envelope) do
    if envelope_format in [nil, @mls_snapshot_envelope_format] do
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
    else
      :none
    end
  end

  defp decode_mls_snapshot_envelope(_envelope, _envelope_format), do: :none

  defp legacy_mls_snapshot_from_metadata(mls) when is_map(mls) do
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

  defp legacy_mls_snapshot_from_metadata(_), do: nil

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
