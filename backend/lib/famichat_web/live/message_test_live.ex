defmodule FamichatWeb.MessageTestLive do
  @moduledoc """
  LiveView for testing real-time messaging via Phoenix Channels.

  This LiveView provides a simple interface for connecting to and testing
  the MessageChannel functionality, including:

  - Connecting to different conversation types (self, direct, group, family)
  - Sending messages with optional encryption
  - Viewing received messages in real-time
  - Testing encryption metadata fields
  """
  use FamichatWeb, :live_view
  require Logger

  @salt "user_auth"
  @test_user_id "test-user-123"
  @default_conversation_id "test-conversation-123"

  @impl true
  def mount(_params, _session, socket) do
    # Generate a token for the test user - this would typically come from auth
    token = Phoenix.Token.sign(FamichatWeb.Endpoint, @salt, @test_user_id)

    # Initialize state with default values
    {:ok,
     assign(socket,
       channel_joined: false,
       conversation_type: "direct",
       conversation_id: @default_conversation_id,
       messages: [],
       current_message: "",
       encryption_enabled: false,
       key_id: "KEY_TEST_v1",
       version_tag: "v1.0.0",
       user_id: @test_user_id,
       error_message: nil,
       show_options: false,
       auth_token: token,
       topic: nil
     )}
  end

  @impl true
  def handle_event("toggle-options", _params, socket) do
    {:noreply, assign(socket, show_options: !socket.assigns.show_options)}
  end

  @impl true
  def handle_event("connect-channel", _params, socket) do
    if socket.assigns.channel_joined do
      # If already connected, send disconnect event to the hook
      {:noreply, push_event(socket, "disconnect_channel", %{})}
    else
      # Connect to the channel via the hook
      {:noreply, push_event(socket, "connect_channel", %{})}
    end
  end

  @impl true
  def handle_event("update-conversation-type", %{"value" => type}, socket) do
    {:noreply, assign(socket, conversation_type: type)}
  end

  @impl true
  def handle_event("update-conversation-id", %{"value" => id}, socket) do
    {:noreply, assign(socket, conversation_id: id)}
  end

  @impl true
  def handle_event("toggle-encryption", _params, socket) do
    {:noreply,
     assign(socket, encryption_enabled: !socket.assigns.encryption_enabled)}
  end

  @impl true
  def handle_event("update-key-id", %{"value" => key_id}, socket) do
    {:noreply, assign(socket, key_id: key_id)}
  end

  @impl true
  def handle_event("update-version-tag", %{"value" => version_tag}, socket) do
    {:noreply, assign(socket, version_tag: version_tag)}
  end

  @impl true
  def handle_event("update-message", %{"value" => message}, socket) do
    {:noreply, assign(socket, current_message: message)}
  end

  @impl true
  def handle_event("send-message", _params, socket) do
    if socket.assigns.channel_joined && socket.assigns.current_message != "" do
      # Prepare the message payload
      payload = %{
        "body" => socket.assigns.current_message,
        "user_id" => socket.assigns.user_id
      }

      # Add encryption metadata if enabled
      payload =
        if socket.assigns.encryption_enabled do
          Map.merge(payload, %{
            "encryption_flag" => true,
            "key_id" => socket.assigns.key_id,
            "version_tag" => socket.assigns.version_tag
          })
        else
          payload
        end

      # Send the message to the hook
      socket = push_event(socket, "send_message", payload)

      # Add the message to our local list
      sent_message = %{
        body: socket.assigns.current_message,
        timestamp: DateTime.utc_now(),
        outgoing: true,
        encrypted: socket.assigns.encryption_enabled
      }

      messages = socket.assigns.messages ++ [sent_message]

      {:noreply, assign(socket, messages: messages, current_message: "")}
    else
      {:noreply, socket}
    end
  end

  # Handle channel join success event from the hook
  @impl true
  def handle_event("channel_joined", %{"topic" => topic}, socket) do
    Logger.info("Successfully joined channel: #{topic}")

    messages =
      socket.assigns.messages ++
        [
          %{
            body: "Successfully connected to #{topic}",
            timestamp: DateTime.utc_now(),
            system_message: true
          }
        ]

    {:noreply,
     assign(socket,
       channel_joined: true,
       messages: messages,
       error_message: nil,
       topic: topic
     )}
  end

  # Handle channel join error event from the hook
  @impl true
  def handle_event("join_error", %{"reason" => reason}, socket) do
    Logger.error("Failed to join channel: #{inspect(reason)}")

    {:noreply,
     assign(socket,
       channel_joined: false,
       error_message: "Failed to join channel: #{inspect(reason)}"
     )}
  end

  # Handle channel leave event from the hook
  @impl true
  def handle_event("channel_left", _params, socket) do
    messages =
      socket.assigns.messages ++
        [
          %{
            body: "Disconnected from #{socket.assigns.topic}",
            timestamp: DateTime.utc_now(),
            system_message: true
          }
        ]

    {:noreply,
     assign(socket,
       channel_joined: false,
       messages: messages,
       topic: nil
     )}
  end

  # Handle message received event from the hook
  @impl true
  def handle_event("message_received", payload, socket) do
    # Skip messages sent by ourselves (they're already in the list)
    if payload["user_id"] != socket.assigns.user_id do
      received_message = %{
        body: payload["body"],
        timestamp:
          case DateTime.from_iso8601(payload["timestamp"]) do
            {:ok, datetime, _offset} -> datetime
            _error -> DateTime.utc_now()
          end,
        outgoing: false,
        encrypted: Map.get(payload, "encrypted", false)
      }

      messages = socket.assigns.messages ++ [received_message]

      {:noreply, assign(socket, messages: messages)}
    else
      {:noreply, socket}
    end
  end

  # Handle message error event from the hook
  @impl true
  def handle_event("message_error", %{"reason" => reason}, socket) do
    Logger.error("Message error: #{inspect(reason)}")

    messages =
      socket.assigns.messages ++
        [
          %{
            body: "Error sending message: #{inspect(reason)}",
            timestamp: DateTime.utc_now(),
            system_message: true
          }
        ]

    {:noreply, assign(socket, messages: messages)}
  end

  # Helper function to format message timestamps
  defp format_time(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end

  defp handle_info({:channel_push_confirmed, _ref}, socket) do
    {:noreply, socket}
  end

  # Helper to generate a stable message ID based on timestamp and body
  defp message_id(message) do
    :erlang.phash2({message.timestamp, message.body})
  end
end
