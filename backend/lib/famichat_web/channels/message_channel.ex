defmodule FamichatWeb.MessageChannel do
  @moduledoc """
  Real-time messaging channel for Famichat.

  ## Channel Subscription Process

  To connect to the messaging channel, clients must:

  1. Obtain an authentication token:
     ```elixir
     token = Phoenix.Token.sign(FamichatWeb.Endpoint, "user_auth", user_id)
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
  require Logger
  alias Famichat.Chat

  @encryption_metadata_fields ~w(version_tag encryption_flag key_id)
  @default_perf_budget 50

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
      topic_parts = String.split(rest, ":")
      Logger.debug("Topic parts: #{inspect(topic_parts)}")

      case topic_parts do
        # Type-aware format - conversation type and ID
        [type, id] when type in ["self", "direct", "group", "family"] ->
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
    end
  end

  # Helper function to authorize and join based on conversation type
  defp handle_type_aware_join(socket, type, id, user_id, measurements) do
    # Perform type-specific authorization checks
    authorized =
      FamichatWeb.Telemetry.with_telemetry(
        [:famichat, :message_channel, :join, :authorize_conversation_access],
        %{user_id: user_id, conversation_id: id, conversation_type: type},
        fn ->
          Famichat.Chat.user_authorized_for_conversation?(
            socket,
            user_id,
            id,
            type
          )
        end
      )

    if authorized do
      Logger.debug(
        "User authorized for #{type} conversation, joining channel with user_id: #{user_id}"
      )

      emit_join_telemetry(measurements, %{
        user_id: user_id,
        conversation_type: type,
        conversation_id: id,
        encryption_status: "enabled",
        status: :success
      })

      {:ok, socket}
    else
      Logger.debug(
        "User not authorized for #{type} conversation, rejecting join"
      )

      emit_join_telemetry(measurements, %{
        user_id: user_id,
        conversation_type: type,
        conversation_id: id,
        status: :error,
        error_reason: :unauthorized
      })

      {:error, %{reason: "unauthorized"}}
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
    start_time = System.monotonic_time()

    broadcast_payload =
      payload
      |> Map.take(["body"] ++ @encryption_metadata_fields)
      |> Map.put("user_id", socket.assigns.user_id)

    topic_parts = String.split(socket.topic, ":")
    Logger.debug("Topic parts: #{inspect(topic_parts)}")

    case topic_parts do
      # Type-aware format
      ["message", type, id] when type in ["self", "direct", "group", "family"] ->
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

      # Invalid format
      _ ->
        Logger.error("Unexpected topic format: #{inspect(topic_parts)}")
        {:reply, {:error, %{reason: "invalid_topic_format"}}, socket}
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

  # Private helper function that processes message acknowledgments.
  # See the @doc for handle_in("message_ack") for full documentation.
  defp handle_message_ack(payload, socket) do
    start_time = System.monotonic_time()
    topic_parts = String.split(socket.topic, ":")

    case topic_parts do
      ["message", type, id]
      when type in ["self", "direct", "group", "family"] ->
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

      _ ->
        Logger.error("Unexpected topic format for ACK: #{inspect(topic_parts)}")
        {:reply, {:error, %{reason: "invalid_topic_format"}}, socket}
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
end
