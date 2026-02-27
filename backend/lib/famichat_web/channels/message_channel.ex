defmodule FamichatWeb.MessageChannel do
  @moduledoc """
  Real-time messaging channel for Famichat.

  ## Channel Subscription Process

  To connect to the messaging channel, clients must:

  1. Obtain an authentication token via the Auth session API:
     ```elixir
     {:ok, session} =
       Famichat.Auth.Sessions.start_session(current_user, %{
         id: "browser-session-uuid",
         user_agent: "Famichat Web Client",
         ip: "127.0.0.1"
       })

     token = session.access_token
     ```

  2. Connect to the socket with the token:
     ```javascript
     let socket = new Socket("/socket", {params: {token: authToken}});
     socket.connect();
     ```

  3. Join the message channel:
     ```javascript
     let channel = socket.channel("message:direct:user123");
     channel.join()
       .receive("ok", resp => console.log("Joined successfully", resp))
       .receive("error", resp => console.log("Join failed", resp));
     ```

  Access tokens are verified server-side via `Famichat.Auth.Sessions.verify_access_token/1`.
  Treat the token as a short-lived bearer credential tied to a specific device session.

  ## Message Payload Format

  Messages sent through the channel must follow this format:

  ```javascript
  {
    "body": "message content",
    "version_tag": "v1.0.0",      // Optional: For encryption versioning
    "encryption_flag": true,       // Optional: Indicates if content is encrypted
    "key_id": "KEY_USER_v1"       // Optional: For key rotation/management
  }
  ```

  ### Encryption-Aware Fields

  The channel supports end-to-end encryption with the following metadata fields:
  - `version_tag`: String matching pattern "v[0-9]+\\.[0-9]+\\.[0-9]+"
  - `encryption_flag`: Boolean indicating if the message is encrypted
  - `key_id`: String matching pattern "KEY_[A-Z]+_v[0-9]+"

  ## Mobile Background Handling

  Note: Due to platform limitations, message delivery may be affected when apps are in the background:
  - iOS: Background connections limited to ~30 seconds
  - Android: Doze mode may delay message delivery

  ## Telemetry and Performance Monitoring

  This module emits telemetry events for critical operations:
  - Channel joins: `[:famichat, :message_channel, :join]`
  - Message broadcasts: `[:famichat, :message_channel, :broadcast]`
  - Message acknowledgments: `[:famichat, :message_channel, :ack]`

  Each event includes standard measurements (duration, timestamps) and contextual metadata.
  Performance budgets are enforced (default: 200ms) and exceeded thresholds are logged.

  For sensitive operations, encryption-related metadata is filtered from telemetry events
  to prevent leakage of security information.

  ## Examples

  Sending a message:
  ```javascript
  channel.push("new_msg", {body: "Hello!"});
  ```

  Sending an encrypted message:
  ```javascript
  channel.push("new_msg", {
    body: encryptedContent,
    version_tag: "v1.0.0",
    encryption_flag: true,
    key_id: "KEY_USER_v1"
  });
  ```

  Receiving messages:
  ```javascript
  channel.on("new_msg", payload => {
    console.log("Received message:", payload);
  });
  ```
  """

  use Phoenix.Channel
  import Ecto.Query
  require Logger

  alias Famichat.Chat.{
    Conversation,
    ConversationSecurityPolicy,
    ConversationQueries,
    Self
  }

  alias Famichat.Auth.{Identity, Sessions}
  alias FamichatWeb.MessagingDispatch

  alias Famichat.Repo

  @encryption_metadata_fields ~w(version_tag encryption_flag key_id)
  @default_perf_budget 200
  intercept(["new_msg"])

  @doc """
  Handles joining the message channel.

  Requires a valid user token in the socket assigns. The token is verified during
  socket connection, and the user_id is stored in the socket assigns.

  ## Examples

      {:ok, socket} = join("message:direct:123", %{}, socket)
      {:error, %{reason: "unauthorized"}} = join("message:direct:123", %{}, socket_without_user)

  ## Telemetry

  Emits [:famichat, :message_channel, :join] event with the following metadata:
  - On success: %{encryption_status: "enabled"}
  - On failure: %{}
  """
  @impl true
  def join("message:" <> rest, _payload, socket) do
    user_id = socket.assigns[:user_id]
    start_time = System.monotonic_time()

    measurements = compute_measurements(start_time)

    if is_nil(user_id) do
      Logger.debug("User ID missing from socket assigns, rejecting join")

      emit_join_telemetry(measurements, %{
        status: :error,
        error_reason: :unauthorized
      })

      {:error, %{reason: "unauthorized"}}
    else
      case ensure_socket_device_active(socket) do
        :ok ->
          topic_parts = String.split(rest, ":")
          Logger.debug("Topic parts: #{inspect(topic_parts)}")

          case topic_parts do
            ["self", topic_user_id] ->
              handle_self_join(
                socket,
                user_id,
                topic_user_id,
                measurements
              )

            # Type-aware format - conversation type and ID
            [type, id] when type in ["direct", "group", "family"] ->
              handle_type_aware_join(socket, type, id, user_id, measurements)

            # Invalid format
            _ ->
              Logger.warning("Invalid topic format: #{inspect(topic_parts)}")

              emit_join_telemetry(measurements, %{
                user_id: user_id,
                status: :error,
                error_reason: :invalid_topic_format
              })

              {:error, %{reason: "invalid_topic_format"}}
          end

        {:error, reason} ->
          emit_join_telemetry(measurements, %{
            user_id: user_id,
            status: :error,
            error_reason: reason
          })

          {:error, %{reason: reason_to_string(reason)}}
      end
    end
  end

  defp handle_self_join(socket, user_id, topic_user_id, measurements) do
    with true <- topic_user_id == user_id,
         {:ok, conversation} <- Self.get_or_create(user_id) do
      emit_join_telemetry(measurements, %{
        user_id: user_id,
        conversation_type: "self",
        conversation_id: conversation.id,
        encryption_status: encryption_status(conversation),
        status: :success
      })

      {:ok, assign(socket, :conversation_id, conversation.id)}
    else
      false ->
        emit_join_telemetry(measurements, %{
          user_id: user_id,
          conversation_type: "self",
          status: :error,
          error_reason: :unauthorized
        })

        {:error, %{reason: "unauthorized"}}

      {:error, reason} ->
        emit_join_telemetry(measurements, %{
          user_id: user_id,
          conversation_type: "self",
          status: :error,
          error_reason: reason
        })

        {:error, %{reason: reason_to_string(reason)}}
    end
  end

  # Helper function to authorize and join based on conversation type
  defp handle_type_aware_join(socket, type, id, user_id, measurements) do
    type_atom =
      case type do
        "direct" -> :direct
        "group" -> :group
        "family" -> :family
      end

    with {:ok, _uuid} <- validate_conversation_id(id),
         {:ok, user} <- fetch_user(user_id),
         {:ok, conversation} <- fetch_conversation(id),
         :ok <- authorize_conversation(conversation, user, type_atom),
         :ok <- ensure_conversation_type(conversation, type_atom) do
      Logger.debug(
        "User authorized for #{type} conversation, joining channel with user_id: #{user_id}"
      )

      emit_join_telemetry(measurements, %{
        user_id: user_id,
        conversation_type: type,
        conversation_id: id,
        encryption_status: encryption_status(conversation),
        status: :success
      })

      {:ok, assign(socket, :conversation_id, id)}
    else
      {:error, reason} ->
        Logger.debug(
          "Join rejected for #{type} conversation id=#{id} reason=#{inspect(reason)}"
        )

        emit_join_telemetry(measurements, %{
          user_id: user_id,
          conversation_type: type,
          conversation_id: id,
          status: :error,
          error_reason: reason
        })

        {:error, %{reason: reason_to_string(public_join_reason(reason))}}
    end
  end

  # Helper function to emit join telemetry
  defp emit_join_telemetry(measurements, metadata) do
    Logger.debug(
      "Emitting join telemetry event with metadata: #{inspect(metadata)}"
    )

    emit_telemetry(
      [:famichat, :message_channel, :join],
      measurements.start_time,
      metadata,
      filter_sensitive_metadata: true
    )
  end

  @impl true
  def handle_in("new_msg", %{"body" => _body} = payload, socket) do
    case ensure_socket_device_active(socket) do
      :ok ->
        start_time = System.monotonic_time()

        case topic_context(socket) do
          {:ok, type, id} ->
            message_params =
              build_message_params(
                payload,
                socket.assigns.user_id,
                id
              )

            case MessagingDispatch.send_message(
                   message_params,
                   socket.assigns.device_id
                 ) do
              {:ok, broadcast_payload} ->
                measurements = compute_measurements(start_time)

                # Calculate message size for metrics
                message_size =
                  if is_binary(payload["body"]) do
                    byte_size(payload["body"])
                  else
                    0
                  end

                metadata = %{
                  user_id: socket.assigns.user_id,
                  conversation_type: type,
                  conversation_id: id,
                  message_size: message_size,
                  encryption_status:
                    if(Map.get(payload, "encryption_flag"),
                      do: "enabled",
                      else: "disabled"
                    )
                }

                # Broadcast the message
                broadcast!(socket, "new_msg", broadcast_payload)

                # Emit telemetry for the broadcast
                emit_broadcast_telemetry(measurements, metadata)

                {:noreply, socket}

              {:error, reason} ->
                {:reply, {:error, message_send_error_payload(reason)}, socket}
            end

          {:error, reason} ->
            {:reply, {:error, %{reason: reason_to_string(reason)}}, socket}
        end

      {:error, reason} ->
        {:reply, {:error, %{reason: reason_to_string(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("new_msg", _invalid_payload, socket) do
    {:reply, {:error, %{reason: "invalid_message"}}, socket}
  end

  @doc """
  Handles acknowledgments from clients that they've received a message.

  This implements a basic client ACK mechanism to track message delivery.
  The client should send a "message_ack" event after successfully receiving
  and processing a "new_msg" event.

  ## Parameters
    * `payload` - Map containing message details for acknowledgment:
      * `message_id` - Unique identifier for the message being acknowledged
      * Other optional metadata

  ## Examples

      # Client acknowledging receipt of a message
      handle_in("message_ack", %{"message_id" => "msg-123"}, socket)

  ## Telemetry

  Emits [:famichat, :message_channel, :ack] event with the following metadata:
  - user_id: The ID of the user acknowledging the message
  - conversation_type: The type of conversation
  - conversation_id: The ID of the conversation
  - message_id: The ID of the acknowledged message
  """
  @impl true
  def handle_in("message_ack", payload, socket) do
    handle_message_ack(payload, socket)
  end

  @impl true
  def handle_out("new_msg", payload, socket) do
    case ensure_socket_device_active(socket) do
      :ok ->
        push(socket, "new_msg", payload)
        {:noreply, socket}

      {:error, reason} ->
        push(socket, "security_state", %{
          reason: reason_to_string(reason),
          action: "reauth_required"
        })

        {:stop, :normal, socket}
    end
  end

  defp build_message_params(payload, sender_id, conversation_id) do
    params = %{
      sender_id: sender_id,
      conversation_id: conversation_id,
      content: payload["body"]
    }

    case extract_encryption_metadata(payload) do
      nil ->
        params

      encryption_metadata ->
        Map.put(params, :encryption_metadata, encryption_metadata)
    end
  end

  defp extract_encryption_metadata(payload) do
    encryption_metadata =
      payload
      |> Map.take(@encryption_metadata_fields)
      |> Enum.reject(fn {_field, value} -> is_nil(value) end)
      |> Map.new()

    if map_size(encryption_metadata) > 0 do
      encryption_metadata
    else
      nil
    end
  end

  defp message_send_error(%Ecto.Changeset{} = changeset) do
    if message_too_large_changeset?(changeset) do
      "message_too_large"
    else
      "invalid_message"
    end
  end

  defp message_send_error(
         {:mls_encryption_failed, :recovery_required, _details}
       ),
       do: "recovery_required"

  defp message_send_error({:mls_encryption_failed, code, _details})
       when is_atom(code),
       do: reason_to_string(code)

  defp message_send_error({:rate_limited, _retry_in}), do: "rate_limited"
  defp message_send_error({:missing_fields, _missing}), do: "invalid_message"
  defp message_send_error(:not_participant), do: "unauthorized"
  defp message_send_error(:wrong_family), do: "unauthorized"

  defp message_send_error(reason) when is_atom(reason),
    do: reason_to_string(reason)

  defp message_send_error(_reason), do: "invalid_message"

  defp message_send_error_payload({:rate_limited, retry_in})
       when is_integer(retry_in) and retry_in > 0 do
    %{reason: "rate_limited", retry_in: retry_in}
  end

  defp message_send_error_payload(
         {:mls_encryption_failed, :recovery_required, details}
       ) do
    %{
      reason: "recovery_required",
      action: "recover_conversation_security_state",
      recovery_reason: mls_error_reason(details)
    }
  end

  defp message_send_error_payload(reason) do
    %{reason: message_send_error(reason)}
  end

  defp message_too_large_changeset?(changeset) do
    Enum.any?(changeset.errors, fn
      {:content, {_message, opts}} ->
        Keyword.get(opts, :validation) == :length and
          Keyword.get(opts, :kind) == :max

      _ ->
        false
    end)
  end

  # Private helper function that processes message acknowledgments.
  # See the @doc for handle_in("message_ack") for full documentation.
  defp handle_message_ack(payload, socket) do
    case ensure_socket_device_active(socket) do
      :ok ->
        start_time = System.monotonic_time()

        case topic_context(socket) do
          {:ok, type, id} ->
            message_id = Map.get(payload, "message_id", "unknown")

            # Create measurements for telemetry
            measurements = compute_measurements(start_time)

            # Metadata for the acknowledgment
            metadata = %{
              user_id: socket.assigns.user_id,
              conversation_type: type,
              conversation_id: id,
              message_id: message_id
            }

            # Log the acknowledgment
            Logger.info(
              "[MessageChannel] Message acknowledgment: " <>
                "conversation_type=#{type} " <>
                "conversation_id=#{id} " <>
                "user_id=#{socket.assigns.user_id} " <>
                "message_id=#{message_id}"
            )

            # Emit telemetry for the acknowledgment
            emit_ack_telemetry(measurements, metadata)

            {:reply, :ok, socket}

          {:error, reason} ->
            {:reply, {:error, %{reason: reason_to_string(reason)}}, socket}
        end

      {:error, reason} ->
        {:reply, {:error, %{reason: reason_to_string(reason)}}, socket}
    end
  end

  # Helper function to emit broadcast telemetry
  @spec emit_broadcast_telemetry(map(), map()) :: :ok
  defp emit_broadcast_telemetry(measurements, metadata) do
    Logger.debug(
      "Emitting broadcast telemetry event with metadata: #{inspect(metadata)}"
    )

    emit_telemetry(
      [:famichat, :message_channel, :broadcast],
      measurements.start_time,
      metadata,
      filter_sensitive_metadata: true
    )
  end

  # Helper function to emit acknowledgment telemetry
  @spec emit_ack_telemetry(map(), map()) :: :ok
  defp emit_ack_telemetry(measurements, metadata) do
    emit_telemetry(
      [:famichat, :message_channel, :ack],
      measurements.start_time,
      metadata
    )
  end

  # New helper to centralize telemetry emission
  defp emit_telemetry(event_name, start_time, metadata, opts \\ []) do
    FamichatWeb.Telemetry.emit_event(
      event_name,
      start_time,
      metadata,
      filter_sensitive_metadata:
        Keyword.get(opts, :filter_sensitive_metadata, false),
      performance_budget_ms:
        Keyword.get(opts, :performance_budget_ms, @default_perf_budget)
    )
  end

  # New helper to compute common telemetry measurements
  defp compute_measurements(start_time) do
    %{
      start_time: start_time,
      system_time: System.system_time(),
      monotonic_time: System.monotonic_time()
    }
  end

  defp validate_conversation_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} -> {:ok, id}
      :error -> {:error, :invalid_conversation_id}
    end
  end

  defp fetch_conversation(id) do
    case Repo.get(Conversation, id) do
      %Conversation{} = conversation ->
        {:ok, conversation}

      nil ->
        {:error, :conversation_not_found}
    end
  end

  defp fetch_user(user_id), do: Identity.fetch_user(user_id)

  defp ensure_socket_device_active(socket) do
    user_id = socket.assigns[:user_id]
    device_id = socket.assigns[:device_id]

    if is_binary(user_id) and is_binary(device_id) do
      case Sessions.device_access_state(user_id, device_id) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid}
    end
  end

  defp authorize_conversation(conversation, user, _type) do
    authorized? =
      conversation
      |> ConversationQueries.members()
      |> where([u], u.id == ^user.id)
      |> Repo.exists?()

    if authorized?, do: :ok, else: {:error, :unauthorized}
  end

  defp ensure_conversation_type(
         %Conversation{conversation_type: conversation_type},
         expected_type
       )
       when conversation_type == expected_type,
       do: :ok

  defp ensure_conversation_type(_conversation, _expected_type),
    do: {:error, :invalid_conversation_type}

  defp encryption_status(%Conversation{conversation_type: type}) do
    ConversationSecurityPolicy.status(type)
  end

  defp reason_to_string(:invalid_conversation_id), do: "invalid_conversation_id"
  defp reason_to_string(:conversation_not_found), do: "conversation_not_found"
  defp reason_to_string(:not_found), do: "not_found"
  defp reason_to_string(:revoked), do: "device_revoked"
  defp reason_to_string(:trust_required), do: "reauth_required"
  defp reason_to_string(:trust_expired), do: "reauth_required"
  defp reason_to_string(:device_not_found), do: "invalid_token"
  defp reason_to_string(:invalid), do: "invalid_token"

  defp reason_to_string(:invalid_conversation_type),
    do: "invalid_conversation_type"

  defp reason_to_string(:user_not_found), do: "unauthorized"
  defp reason_to_string(:not_in_family), do: "unauthorized"

  defp reason_to_string(:invalid_self_conversation),
    do: "invalid_self_conversation"

  defp reason_to_string(:lock_failed), do: "temporary_failure"
  defp reason_to_string(:unauthorized), do: "unauthorized"
  defp reason_to_string(:invalid_topic_format), do: "invalid_topic_format"
  defp reason_to_string(other), do: to_string(other)

  defp mls_error_reason(details) when is_map(details) do
    case Map.get(details, :reason) || Map.get(details, "reason") do
      reason when is_atom(reason) -> Atom.to_string(reason)
      reason when is_binary(reason) -> reason
      _ -> "unspecified"
    end
  end

  defp mls_error_reason(_details), do: "unspecified"

  defp public_join_reason(:invalid_conversation_id), do: :not_found

  defp public_join_reason(:conversation_not_found), do: :not_found
  defp public_join_reason(:invalid_conversation_type), do: :not_found
  defp public_join_reason(:unauthorized), do: :not_found
  defp public_join_reason(:user_not_found), do: :not_found
  defp public_join_reason(:wrong_family), do: :not_found
  defp public_join_reason(:revoked), do: :revoked
  defp public_join_reason(:trust_required), do: :trust_required
  defp public_join_reason(:trust_expired), do: :trust_expired
  defp public_join_reason(reason), do: reason

  defp topic_context(%{
         topic: "message:self:" <> topic_user_id,
         assigns: %{conversation_id: id, user_id: user_id}
       })
       when is_binary(id) and topic_user_id == user_id do
    {:ok, "self", id}
  end

  defp topic_context(%{topic: "message:self:" <> _topic_user_id}),
    do: {:error, :unauthorized}

  defp topic_context(%{topic: "message:" <> rest}) do
    case String.split(rest, ":") do
      [type, id] when type in ["direct", "group", "family"] ->
        {:ok, type, id}

      _ ->
        {:error, :invalid_topic_format}
    end
  end

  defp topic_context(_), do: {:error, :invalid_topic_format}
end
