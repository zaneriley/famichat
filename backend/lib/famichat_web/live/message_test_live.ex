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

  alias Famichat.Auth.{Households, Identity, Sessions}
  alias Famichat.Chat.{Conversation, ConversationParticipant, Family}
  alias Famichat.Repo

  @test_username "test-user"

  @impl true
  def mount(_params, _session, socket) do
    # Create or fetch test user and session with real auth tokens
    # This validates the auth refactor works end-to-end
    case ensure_test_user_and_session() do
      {:ok,
       %{
         access_token: access_token,
         user: user,
         conversation_id: conversation_id
       }} ->
        {:ok,
         assign(socket,
           channel_joined: false,
           conversation_type: "self",
           conversation_id: conversation_id,
           messages: [],
           current_message: "",
           encryption_enabled: false,
           key_id: "KEY_TEST_v1",
           version_tag: "v1.0.0",
           user_id: user.id,
           error_message: nil,
           show_options: false,
           auth_token: access_token,
           topic: nil
         )}

      {:error, reason} ->
        Logger.error("Failed to create test session: #{inspect(reason)}")

        {:ok,
         assign(socket,
           channel_joined: false,
           conversation_type: "self",
           conversation_id: nil,
           messages: [],
           current_message: "",
           encryption_enabled: false,
           key_id: "KEY_TEST_v1",
           version_tag: "v1.0.0",
           user_id: nil,
           error_message:
             "Failed to initialize test session: #{inspect(reason)}",
           show_options: false,
           auth_token: nil,
           topic: nil
         )}
    end
  end

  # Create test user and session using real auth system
  # This fires actual telemetry events visible in the dashboard
  defp ensure_test_user_and_session do
    Repo.transaction(fn ->
      family = ensure_test_family!()
      user = ensure_test_user!()

      ensure_membership!(user.id, family.id)
      conversation = ensure_self_conversation!(family, user)

      session_data = start_test_session!(user)
      Map.put(session_data, :conversation_id, conversation.id)
    end)
  end

  defp ensure_test_family! do
    Repo.get_by(Family, name: "Test Family") ||
      %Family{}
      |> Family.changeset(%{name: "Test Family"})
      |> Repo.insert!()
  end

  defp ensure_test_user! do
    case Identity.ensure_user(%{"username" => @test_username}) do
      {:ok, user} -> user
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_self_conversation!(family, user) do
    conversation =
      Repo.get_by(Conversation, conversation_type: :self, family_id: family.id) ||
        create_self_conversation!(family, user)

    ensure_participant!(conversation.id, user.id)
    conversation
  end

  defp create_self_conversation!(family, user) do
    {:ok, conversation} =
      %Conversation{}
      |> Conversation.changeset(%{
        conversation_type: :self,
        family_id: family.id,
        name: "Test Self Conversation"
      })
      |> Repo.insert()

    ensure_participant!(conversation.id, user.id)
    conversation
  end

  defp ensure_participant!(conversation_id, user_id) do
    case Repo.get_by(ConversationParticipant,
           conversation_id: conversation_id,
           user_id: user_id
         ) do
      %ConversationParticipant{} ->
        :ok

      nil ->
        %ConversationParticipant{}
        |> ConversationParticipant.changeset(%{
          conversation_id: conversation_id,
          user_id: user_id
        })
        |> Repo.insert!()

        :ok
    end
  end

  defp start_test_session!(user) do
    device_info = %{
      id: "test-device-#{System.unique_integer([:positive])}",
      user_agent: "MessageTestLive",
      ip: "127.0.0.1"
    }

    case Sessions.start_session(
           user,
           device_info,
           remember_device?: false
         ) do
      {:ok, %{access_token: access_token}} ->
        %{access_token: access_token, user: user}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp ensure_membership!(user_id, family_id) do
    case Households.upsert_membership(user_id, family_id, :admin) do
      {:ok, _membership} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
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

  @impl true
  def handle_info({:channel_push_confirmed, _ref}, socket) do
    {:noreply, socket}
  end

  # Helper to generate a stable message ID based on timestamp and body
  defp message_id(message) do
    :erlang.phash2({message.timestamp, message.body})
  end
end
