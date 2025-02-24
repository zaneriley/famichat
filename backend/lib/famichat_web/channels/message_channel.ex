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
  def join("message:" <> room_id, params, socket) do
    start_time = System.monotonic_time()
    Logger.debug("""
    MessageChannel join called:
    - room_id: #{inspect(room_id)}
    - params: #{inspect(params)}
    - socket assigns: #{inspect(socket.assigns)}
    """)

    measurements = %{
      start_time: start_time,
      system_time: System.system_time(),
      monotonic_time: System.monotonic_time()
    }

    try do
      if socket.assigns[:user_id] do
        Logger.debug("User authorized, joining channel with user_id: #{socket.assigns.user_id}")

        metadata = %{
          user_id: socket.assigns.user_id,
          room_id: room_id,
          encryption_status: "enabled",
          status: :success
        }

        Logger.debug("Emitting telemetry event with metadata: #{inspect(metadata)}")
        :telemetry.execute(
          [:famichat, :message_channel, :join],
          measurements,
          metadata
        )

        {:ok, socket}
      else
        Logger.debug("User unauthorized, rejecting join - no user_id in socket assigns")

        metadata = %{
          room_id: room_id,
          status: :error,
          error_reason: :unauthorized
        }

        Logger.debug("Emitting telemetry event with metadata: #{inspect(metadata)}")
        :telemetry.execute(
          [:famichat, :message_channel, :join],
          measurements,
          metadata
        )

        {:error, %{reason: "unauthorized"}}
      end
    rescue
      error ->
        Logger.error("Error in channel join: #{inspect(error)}")
        metadata = %{
          room_id: room_id,
          status: :error,
          error_reason: :internal_error,
          error_details: inspect(error)
        }
        :telemetry.execute(
          [:famichat, :message_channel, :join],
          measurements,
          metadata
        )
        {:error, %{reason: "internal_error"}}
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
      ["message", room_id, _extra] ->
        measurements = %{
          start_time: start_time,
          system_time: System.system_time(),
          monotonic_time: System.monotonic_time()
        }

        metadata = %{
          user_id: socket.assigns.user_id,
          room_id: room_id,
          encryption_status: if(Map.get(payload, "encryption_flag"), do: "enabled", else: "disabled")
        }

        :telemetry.execute(
          [:famichat, :message_channel, :broadcast],
          measurements,
          metadata
        )

        broadcast!(socket, "new_msg", broadcast_payload)

        {:noreply, socket}
      _ ->
        Logger.error("Unexpected topic format: #{inspect(topic_parts)}")
        {:error, %{reason: "invalid_topic_format"}}
    end
  end

  def handle_in("new_msg", _invalid_payload, socket) do
    {:reply, {:error, %{reason: "invalid_message"}}, socket}
  end
end
