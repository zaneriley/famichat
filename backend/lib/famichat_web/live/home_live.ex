defmodule FamichatWeb.HomeLive do
  use FamichatWeb, :live_view
  import Ecto.Query
  require Logger

  alias Famichat.Auth.{Households, Identity, Sessions}
  alias Famichat.Chat
  alias Famichat.Chat.{Conversation, ConversationSecurityStateStore, Family}
  alias Famichat.Repo

  @default_test_username_prefix "ac-user"
  @default_device_prefix "device"
  @default_recovery_ref_prefix "spike-recovery"

  @impl true
  def mount(params, _session, socket) do
    test_username = resolve_test_username(params)
    device_label = resolve_device_label(params)
    revoke_target = resolve_revoke_target(params)
    recovery_ref = default_recovery_ref()

    case ensure_test_user_and_session(test_username, device_label) do
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
           device_label: device_label,
           test_username: test_username,
           actor_tag: "#{test_username}/#{device_label}",
           error_message: nil,
           auth_token: access_token,
           topic: nil,
           security_reason: nil,
           security_action: nil,
           revoke_target: revoke_target,
           recovery_ref: recovery_ref,
           recovery_last_status: nil,
           mls_enforcement_enabled:
             Application.get_env(:famichat, :mls_enforcement, false)
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
           device_label: device_label,
           test_username: test_username,
           actor_tag: "#{test_username}/#{device_label}",
           error_message: "Failed to initialize test session: #{inspect(reason)}",
           auth_token: nil,
           topic: nil,
           security_reason: nil,
           security_action: nil,
           revoke_target: revoke_target,
           recovery_ref: recovery_ref,
           recovery_last_status: nil,
           mls_enforcement_enabled:
             Application.get_env(:famichat, :mls_enforcement, false)
         )
         |> stream(:messages, [], reset: true)}
    end
  end

  defp ensure_test_user_and_session(test_username, device_label) do
    Repo.transaction(fn ->
      family = ensure_test_family!()
      user = ensure_test_user!(test_username)

      ensure_membership!(user.id, family.id)
      conversation = ensure_family_conversation!(family.id)

      session_data = start_test_session!(user, test_username, device_label)
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

  defp start_test_session!(user, test_username, device_label) do
    device_info = %{
      id: stable_device_id(test_username, device_label),
      user_agent: "HomeLive/#{device_label}",
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
  def handle_event("update-revoke-target", %{"value" => target}, socket) do
    {:noreply, assign(socket, revoke_target: target)}
  end

  @impl true
  def handle_event("update-recovery-ref", %{"value" => ref}, socket) do
    {:noreply, assign(socket, recovery_ref: ref)}
  end

  @impl true
  def handle_event("send-message", _params, socket) do
    message_body = socket.assigns.current_message |> to_string() |> String.trim()

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
        {:noreply, assign(socket, error_message: "Connect channel before sending.")}
    end
  end

  @impl true
  def handle_event("revoke-target-device", _params, socket) do
    target = socket.assigns.revoke_target |> to_string() |> String.trim()

    cond do
      target == "" ->
        {:noreply, assign(socket, error_message: "Enter a device id to revoke.")}

      true ->
        case Sessions.revoke_device(socket.assigns.user_id, target) do
          {:ok, :revoked} ->
            {:noreply,
             socket
             |> assign(error_message: nil)
             |> put_system_notice("Revoked device #{target}.")}

          {:error, :not_found} ->
            {:noreply,
             assign(
               socket,
               error_message: "Device #{target} not found for this user."
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket, error_message: "Device revoke failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("reset-conversation-security-state", _params, socket) do
    case ConversationSecurityStateStore.delete(socket.assigns.conversation_id) do
      :ok ->
        {:noreply,
         socket
         |> assign(
           error_message: nil,
           security_reason: nil,
           security_action: nil,
           recovery_last_status: "conversation_security_state reset"
         )
         |> put_system_notice(
          "Conversation security state reset. Next send may require recovery."
         )}

      {:error, :invalid_input, details} ->
        {:noreply,
         assign(
           socket,
           error_message: "Reset failed: #{inspect(details)}"
         )}
    end
  end

  @impl true
  def handle_event("recover-conversation-security-state", _params, socket) do
    recovery_ref = socket.assigns.recovery_ref |> to_string() |> String.trim()

    cond do
      recovery_ref == "" ->
        {:noreply,
         assign(socket, error_message: "Enter a recovery ref before recovering.")}

      true ->
        case Chat.recover_conversation_security_state(
               socket.assigns.conversation_id,
               recovery_ref,
               %{rejoin_token: "spike-rejoin-#{System.unique_integer([:positive])}"}
             ) do
          {:ok, result} ->
            description =
              if result.idempotent do
                "Recovery replay accepted (idempotent) for #{result.recovery_ref}."
              else
                "Recovery completed at epoch #{result.recovered_epoch} (ref #{result.recovery_ref})."
              end

            {:noreply,
             socket
             |> assign(
               error_message: nil,
               security_reason: nil,
               security_action: nil,
               recovery_last_status: description
             )
             |> put_system_notice(description)}

          {:error, reason} ->
            {:noreply,
             assign(socket, error_message: "Recovery failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("reload-history", _params, socket) do
    {:noreply,
     socket
     |> assign(error_message: nil)
     |> load_messages(socket.assigns.conversation_id, socket.assigns.user_id)}
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

    {:noreply, assign(socket, channel_joined: true, error_message: nil, topic: topic)}
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

    reason_text = reason_to_string(reason)

    {:noreply,
     socket
     |> assign(
       error_message: message_error_text(reason_text),
       security_reason: reason_text,
       security_action: security_action_for_reason(reason_text)
     )
     |> put_system_notice("Send blocked: #{reason_text}.")}
  end

  @impl true
  def handle_event("security_state_update", payload, socket) do
    reason = reason_to_string(payload["reason"])
    action = payload["action"] |> reason_to_string()

    {:noreply,
     socket
     |> assign(
       channel_joined: false,
       security_reason: reason,
       security_action: action,
       error_message: "Security state: #{reason} (#{action})"
     )
     |> put_system_notice("Security state changed: #{reason} (#{action}).")}
  end

  @impl true
  def handle_info({:channel_push_confirmed, _ref}, socket) do
    {:noreply, socket}
  end

  @impl true
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

  defp resolve_device_label(params) do
    params
    |> Map.get("device")
    |> normalize_device_label()
    |> case do
      nil -> "#{@default_device_prefix}-#{System.unique_integer([:positive])}"
      label -> label
    end
  end

  defp normalize_device_label(label) when is_binary(label) do
    label
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> nil
      sanitized -> sanitized
    end
  end

  defp normalize_device_label(_), do: nil

  defp resolve_revoke_target(params) do
    params
    |> Map.get("revoke_target", "")
    |> to_string()
    |> String.trim()
  end

  defp stable_device_id(test_username, device_label) do
    "spike-#{test_username}-#{device_label}"
  end

  defp default_recovery_ref do
    "#{@default_recovery_ref_prefix}-#{System.unique_integer([:positive])}"
  end

  defp load_messages(socket, nil, _user_id) do
    stream(socket, :messages, [], reset: true)
  end

  defp load_messages(socket, conversation_id, user_id) do
    messages =
      case Famichat.Chat.MessageService.get_conversation_messages(conversation_id,
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

  defp put_system_notice(socket, body) do
    stream_insert(socket, :messages, %{
      id: "sys-#{System.unique_integer([:positive])}",
      body: body,
      timestamp: DateTime.utc_now(),
      outgoing: false,
      system_message: true,
      sender_name: "System"
    })
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

  defp message_error_text("recovery_required"),
    do: "Recovery required before this device can send. Use Recover below."

  defp message_error_text("device_revoked"),
    do: "This device is revoked. Open a fresh actor link."

  defp message_error_text("pending_proposals"),
    do: "Conversation is waiting for pending commit to finish."

  defp message_error_text(reason), do: "Message failed: #{reason}"

  defp security_action_for_reason("recovery_required"),
    do: "recover_conversation_security_state"

  defp security_action_for_reason("device_revoked"), do: "reauth_required"
  defp security_action_for_reason("pending_proposals"), do: "wait_for_pending_commit"
  defp security_action_for_reason(_), do: nil

  defp reason_to_string(nil), do: ""
  defp reason_to_string(reason) when is_binary(reason), do: reason
  defp reason_to_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_to_string(reason), do: inspect(reason)
end
