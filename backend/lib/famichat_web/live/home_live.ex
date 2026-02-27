defmodule FamichatWeb.HomeLive do
  use FamichatWeb, :live_view
  import Ecto.Query
  require Logger

  alias Famichat.Auth.{Households, Identity, Sessions}
  alias Famichat.Chat.{Conversation, Family}
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
        {:ok,
         socket
         |> assign(
           channel_joined: false,
           conversation_type: "family",
           conversation_id: conversation_id,
           current_message: "",
           user_id: user.id,
           device_id: device_id,
           test_username: test_username,
           error_message: nil,
           auth_token: access_token,
           topic: nil
         )
         |> load_messages(conversation_id, user.id)}

      {:error, reason} ->
        Logger.error("Failed to create test session: #{inspect(reason)}")

        {:ok,
         socket
         |> assign(
           channel_joined: false,
           conversation_type: "family",
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
         |> stream(:messages, [], reset: true)}
    end
  end

  defp ensure_test_user_and_session(test_username) do
    Repo.transaction(fn ->
      family = ensure_test_family!()
      user = ensure_test_user!(test_username)

      ensure_membership!(user.id, family.id)
      conversation = ensure_family_conversation!(family.id)

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

  defp ensure_family_conversation!(family_id) do
    query =
      from c in Conversation,
        where: c.family_id == ^family_id and c.conversation_type == :family,
        order_by: [asc: c.inserted_at],
        limit: 1

    case Repo.one(query) do
      %Conversation{} = conversation ->
        conversation

      nil ->
        %Conversation{}
        |> Conversation.create_changeset(%{
          family_id: family_id,
          conversation_type: :family,
          metadata: %{"name" => "Family Chat"}
        })
        |> Repo.insert!()
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

    cond do
      message_body == "" ->
        {:noreply, socket}

      socket.assigns.channel_joined ->
        payload = %{
          "body" => message_body,
          "user_id" => socket.assigns.user_id
        }

        {:noreply,
         socket
         |> push_event("send_message", payload)
         |> assign(current_message: "", error_message: nil)}

      true ->
        {:noreply,
         assign(socket, error_message: "Connect channel before sending.")}
    end
  end

  @impl true
  def handle_event("socket_error", %{"reason" => reason}, socket) do
    Logger.error("Socket error: #{inspect(reason)}")

    {:noreply,
     assign(
       socket,
       channel_joined: false,
       error_message: "Socket error: #{reason_to_string(reason)}"
     )}
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
     assign(
       socket,
       channel_joined: false,
       error_message: "Failed to join: #{reason_to_string(reason)}"
     )}
  end

  @impl true
  def handle_event("channel_left", _params, socket) do
    {:noreply, assign(socket, channel_joined: false, topic: nil)}
  end

  @impl true
  def handle_event("message_received", payload, socket) do
    received_message = %{
      id: "msg-#{:erlang.unique_integer()}",
      body: payload["body"],
      timestamp:
        case DateTime.from_iso8601(payload["timestamp"]) do
          {:ok, datetime, _offset} -> datetime
          _error -> DateTime.utc_now()
        end,
      outgoing: payload["user_id"] == socket.assigns.user_id,
      system_message: false,
      sender_name: sender_name_for_payload(payload, socket.assigns)
    }

    {:noreply, stream_insert(socket, :messages, received_message)}
  end

  @impl true
  def handle_event("message_error", %{"reason" => reason}, socket) do
    Logger.error("Message error: #{inspect(reason)}")

    {:noreply,
     assign(
       socket,
       error_message: "Message failed: #{reason_to_string(reason)}"
     )}
  end

  @impl true
  def handle_info({:channel_push_confirmed, _ref}, socket) do
    {:noreply, socket}
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

  defp load_messages(socket, nil, _user_id) do
    stream(socket, :messages, [], reset: true)
  end

  defp load_messages(socket, conversation_id, user_id) do
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
              outgoing: msg.sender_id == user_id,
              system_message: false,
              sender_name: sender_name_for_record(msg, user_id)
            }
          end)

        _ ->
          []
      end

    stream(socket, :messages, messages, reset: true)
  end

  defp sender_name_for_record(msg, user_id) do
    cond do
      msg.sender_id == user_id ->
        "Me"

      is_map(msg.sender) and is_binary(msg.sender.username) ->
        msg.sender.username

      true ->
        "Family Member"
    end
  end

  defp sender_name_for_payload(payload, assigns) do
    if payload["user_id"] == assigns.user_id do
      "Me"
    else
      "Family Member"
    end
  end

  defp reason_to_string(reason) when is_binary(reason), do: reason
  defp reason_to_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_to_string(reason), do: inspect(reason)
end
