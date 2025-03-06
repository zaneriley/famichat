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
     let channel = socket.channel("message:lobby");
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

  @encryption_metadata_fields ~w(version_tag encryption_flag key_id)

  @doc """
  Handles joining the message channel.

  Requires a valid user token in the socket assigns. The token is verified during
  socket connection, and the user_id is stored in the socket assigns.

  ## Examples

      {:ok, socket} = join("message:lobby", %{}, socket)
      {:error, %{reason: "unauthorized"}} = join("message:lobby", %{}, socket_without_user)

  ## Telemetry

  Emits [:famichat, :message_channel, :join] event with the following metadata:
  - On success: %{encryption_status: "enabled"}
  - On failure: %{}
  """
  @impl true
  def join("message:" <> rest, _payload, socket) do
    user_id = socket.assigns[:user_id]
    start_time = System.monotonic_time()

    measurements = %{
      start_time: start_time,
      system_time: System.system_time(),
      monotonic_time: System.monotonic_time()
    }

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
        # Legacy format - just a room ID
        [room_id] when room_id not in ["invalid"] ->
          handle_legacy_join(socket, room_id, user_id, measurements)

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

  # Helper function to handle legacy topic format
  defp handle_legacy_join(socket, room_id, user_id, measurements) do
    # For legacy format, we don't do type-specific authorization
    Logger.debug(
      "User authorized for legacy room, joining channel with user_id: #{user_id}"
    )

    emit_join_telemetry(measurements, %{
      user_id: user_id,
      room_id: room_id,
      encryption_status: "enabled",
      status: :success
    })

    {:ok, socket}
  end

  # Helper function to authorize and join based on conversation type
  defp handle_type_aware_join(socket, type, id, user_id, measurements) do
    # Perform type-specific authorization checks
    authorized =
      case type do
        "self" ->
          # For self conversations, only the creator can access
          # In a real implementation, this would query the database
          # For now, we'll assume the ID contains the user_id for demo purposes
          id == user_id

        "direct" ->
          # For direct conversations, only the two participants can access
          # In a real implementation, this would query the database
          # For now, we'll authorize all for demo purposes
          true

        "group" ->
          # For group conversations, only active members can access
          # In a real implementation, this would query the database
          # For now, we'll authorize all for demo purposes
          true

        "family" ->
          # For family conversations, all family members have access
          # In a real implementation, this would query the database
          # For now, we'll authorize all for demo purposes
          true
      end

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
    Logger.debug("Emitting telemetry event with metadata: #{inspect(metadata)}")

    # Calculate duration in milliseconds
    duration_ms =
      System.convert_time_unit(
        System.monotonic_time() - measurements.start_time,
        :native,
        :millisecond
      )

    # Add duration to measurements
    measurements = Map.put(measurements, :duration_ms, duration_ms)

    # Add timestamp to metadata
    metadata = Map.put(metadata, :timestamp, DateTime.utc_now())

    # Filter out sensitive encryption metadata fields
    # For failed joins, remove all encryption-related fields
    # For successful joins, only keep the encryption_status field
    filtered_metadata =
      if metadata[:status] == :success do
        # For successful joins, only keep encryption_status
        Map.drop(metadata, @encryption_metadata_fields)
      else
        # For failed joins, remove all encryption-related fields including encryption_status
        Map.drop(metadata, @encryption_metadata_fields ++ ["encryption_status"])
      end

    # Emit telemetry event with filtered metadata
    :telemetry.execute(
      [:famichat, :message_channel, :join],
      measurements,
      filtered_metadata
    )

    # Log performance budget warning if join takes too long
    if duration_ms > 200 do
      Logger.warning(
        "Channel join exceeded performance budget: #{duration_ms}ms"
      )
    end
  end

  @doc """
  Handles incoming messages on the channel.

  Supports both plain text and encrypted messages. For encrypted messages,
  additional metadata fields (version_tag, encryption_flag, key_id) are preserved
  and broadcast to all channel subscribers.

  ## Examples

      # Plain text message
      handle_in("new_msg", %{"body" => "Hello!"}, socket)

      # Encrypted message
      handle_in("new_msg", %{
        "body" => "encrypted_content",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_USER_v1"
      }, socket)

  ## Telemetry

  Emits [:famichat, :message_channel, :broadcast] event with the following metadata:
  - user_id: The ID of the user sending the message
  - room_id: The room the message was sent to
  - encryption_status: Whether the message was encrypted
  """
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
      # Legacy format
      ["message", room_id] ->
        measurements = %{
          start_time: start_time,
          system_time: System.system_time(),
          monotonic_time: System.monotonic_time()
        }

        metadata = %{
          user_id: socket.assigns.user_id,
          room_id: room_id,
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

      # Type-aware format
      ["message", type, id] when type in ["self", "direct", "group", "family"] ->
        measurements = %{
          start_time: start_time,
          system_time: System.system_time(),
          monotonic_time: System.monotonic_time()
        }

        metadata = %{
          user_id: socket.assigns.user_id,
          conversation_type: type,
          conversation_id: id,
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

  def handle_in("new_msg", _invalid_payload, socket) do
    {:reply, {:error, %{reason: "invalid_message"}}, socket}
  end

  # Helper function to emit broadcast telemetry
  defp emit_broadcast_telemetry(measurements, metadata) do
    Logger.debug(
      "Emitting broadcast telemetry event with metadata: #{inspect(metadata)}"
    )

    # Calculate duration in milliseconds
    duration_ms =
      System.convert_time_unit(
        System.monotonic_time() - measurements.start_time,
        :native,
        :millisecond
      )

    # Add duration to measurements
    measurements = Map.put(measurements, :duration_ms, duration_ms)

    # Add timestamp to metadata
    metadata = Map.put(metadata, :timestamp, DateTime.utc_now())

    # Add message size to metadata if available
    metadata =
      if Map.has_key?(metadata, :message_size) do
        metadata
      else
        Map.put(metadata, :message_size, 0)
      end

    # Filter out sensitive encryption metadata fields
    # Only keep the encryption_status field, remove all other encryption-related fields
    filtered_metadata = Map.drop(metadata, @encryption_metadata_fields)

    # Emit telemetry event with filtered metadata
    :telemetry.execute(
      [:famichat, :message_channel, :broadcast],
      measurements,
      filtered_metadata
    )

    # Log performance budget warning if broadcast takes too long
    if duration_ms > 200 do
      Logger.warning(
        "Channel broadcast exceeded performance budget: #{duration_ms}ms"
      )
    end
  end
end
