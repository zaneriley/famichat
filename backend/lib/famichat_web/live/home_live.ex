defmodule FamichatWeb.HomeLive do
  use FamichatWeb, :live_view
  require Logger

  alias Famichat.Auth.{Households, Identity, Sessions}
  alias Famichat.Chat.{Family, Self}
  alias Famichat.Repo

  @default_test_username_prefix "ac-user"

  @impl true
  def mount(params, _session, socket) do
    test_username = resolve_test_username(params)

    case ensure_test_user_and_session(test_username) do
      {:ok,
       %{
         access_token: access_token,
         device_id: device_id,
         user: user,
         conversation_id: conversation_id
       }} ->
        messages =
          case Famichat.Chat.MessageService.get_conversation_messages(
                 conversation_id,
                 limit: 50
               ) do
            {:ok, msgs} ->
              Enum.map(msgs, fn msg ->
                %{
                  id: "msg-#{msg.id}",
                  body: msg.content,
                  timestamp: msg.inserted_at,
                  outgoing: msg.sender_id == user.id,
                  system_message: false,
                  sender_name:
                    if(msg.sender_id == user.id,
                      do: "Me",
                      else: "Family Member"
                    )
                }
              end)

            _ ->
              []
          end

        # Subscribe to conversation topic for real-time updates
        Phoenix.PubSub.subscribe(
          Famichat.PubSub,
          "conversation:#{conversation_id}"
        )

        {:ok,
         socket
         |> assign(
           channel_joined: false,
           conversation_type: "self",
           conversation_id: conversation_id,
           current_message: "",
           encryption_enabled: false,
           key_id: "KEY_TEST_v1",
           version_tag: "v1.0.0",
           user_id: user.id,
           device_id: device_id,
           test_username: test_username,
           error_message: nil,
           auth_token: access_token,
           topic: nil
         )
         |> stream(:messages, messages)}

      {:error, reason} ->
        Logger.error("Failed to create test session: #{inspect(reason)}")

        {:ok,
         socket
         |> assign(
           channel_joined: false,
           conversation_type: "self",
           conversation_id: nil,
           current_message: "",
           user_id: nil,
           device_id: nil,
           test_username: test_username,
           error_message:
             "Failed to initialize test session: #{inspect(reason)}",
           auth_token: nil,
           topic: nil
         )
         |> stream(:messages, [])}
    end
  end

  defp ensure_test_user_and_session(test_username) do
    Repo.transaction(fn ->
      family = ensure_test_family!()
      user = ensure_test_user!(test_username)

      ensure_membership!(user.id, family.id)
      conversation = ensure_self_conversation!(user.id)

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

  defp ensure_test_user!(test_username) do
    case Identity.ensure_user(%{"username" => test_username}) do
      {:ok, user} -> user
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_self_conversation!(user_id) do
    case Self.get_or_create(user_id) do
      {:ok, conversation} -> conversation
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp start_test_session!(user) do
    device_info = %{
      id: "ac-device-#{System.unique_integer([:positive])}",
      user_agent: "HomeLive",
      ip: "127.0.0.1"
    }

    case Sessions.start_session(user, device_info, remember_device?: false) do
      {:ok, %{access_token: access_token, device_id: device_id}} ->
        %{access_token: access_token, device_id: device_id, user: user}

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
  def handle_event("connect-channel", _params, socket) do
    if socket.assigns.channel_joined do
      {:noreply, push_event(socket, "disconnect_channel", %{})}
    else
      {:noreply, push_event(socket, "connect_channel", %{})}
    end
  end

  @impl true
  def handle_event("update-message", %{"value" => message}, socket) do
    {:noreply, assign(socket, current_message: message)}
  end

  @impl true
  def handle_event("send-message", _params, socket) do
    message_body =
      socket.assigns.current_message |> to_string() |> String.trim()

    if socket.assigns.channel_joined && message_body != "" do
      payload = %{
        "body" => message_body,
        "user_id" => socket.assigns.user_id
      }

      socket = push_event(socket, "send_message", payload)

      sent_message = %{
        id: "msg-#{:erlang.unique_integer()}",
        body: message_body,
        timestamp: DateTime.utc_now(),
        outgoing: true,
        system_message: false,
        sender_name: "Me"
      }

      {:noreply,
       socket
       |> stream_insert(:messages, sent_message)
       |> assign(current_message: "")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("socket_error", %{"reason" => reason}, socket) do
    Logger.error("Socket error: #{inspect(reason)}")

    {:noreply,
     assign(socket, channel_joined: false, error_message: "Socket error")}
  end

  @impl true
  def handle_event("channel_joined", %{"topic" => topic}, socket) do
    Logger.info("Successfully joined channel: #{topic}")

    {:noreply,
     assign(socket, channel_joined: true, error_message: nil, topic: topic)}
  end

  @impl true
  def handle_event("join_error", %{"reason" => reason}, socket) do
    Logger.error("Failed to join channel: #{inspect(reason)}")

    {:noreply,
     assign(socket, channel_joined: false, error_message: "Failed to join")}
  end

  @impl true
  def handle_event("channel_left", _params, socket) do
    {:noreply, assign(socket, channel_joined: false, topic: nil)}
  end

  @impl true
  def handle_event("message_received", payload, socket) do
    if local_echo_on_same_device?(payload, socket.assigns) do
      {:noreply, socket}
    else
      received_message = %{
        id: "msg-#{:erlang.unique_integer()}",
        body: payload["body"],
        timestamp:
          case DateTime.from_iso8601(payload["timestamp"]) do
            {:ok, datetime, _offset} -> datetime
            _error -> DateTime.utc_now()
          end,
        outgoing: false,
        system_message: false,
        sender_name: "Family Member"
      }

      {:noreply, stream_insert(socket, :messages, received_message)}
    end
  end

  @impl true
  def handle_event("message_error", %{"reason" => reason}, socket) do
    Logger.error("Message error: #{inspect(reason)}")
    {:noreply, socket}
  end

  @impl true
  def handle_info({:channel_push_confirmed, _ref}, socket) do
    {:noreply, socket}
  end

  # Handle incoming messages from PubSub (e.g. from other users)
  @impl true
  def handle_info(
        %{__struct__: Phoenix.Socket.Broadcast, topic: _, payload: payload},
        socket
      ) do
    received_message = %{
      id: "msg-#{:erlang.unique_integer()}",
      body: payload.body || payload["body"],
      timestamp: DateTime.utc_now(),
      outgoing: false,
      system_message: false,
      sender_name: "Family Member"
    }

    {:noreply, stream_insert(socket, :messages, received_message)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp resolve_test_username(params) do
    params
    |> Map.get("user")
    |> normalize_test_username()
    |> case do
      nil -> unique_test_username()
      username -> username
    end
  end

  defp normalize_test_username(username) when is_binary(username) do
    username
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> nil
      sanitized -> sanitized
    end
  end

  defp normalize_test_username(_), do: nil

  defp unique_test_username do
    "#{@default_test_username_prefix}-#{System.unique_integer([:positive])}"
  end

  defp local_echo_on_same_device?(
         %{"user_id" => user_id, "device_id" => device_id},
         %{user_id: local_user_id, device_id: local_device_id}
       ) do
    user_id == local_user_id and device_id == local_device_id
  end

  defp local_echo_on_same_device?(_payload, _assigns), do: false
end
