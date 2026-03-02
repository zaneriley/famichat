defmodule FamichatWeb.HomeLive do
  use FamichatWeb, :live_view
  import Ecto.Query
  require Logger

  alias Famichat.Auth.{Identity, Sessions}
  alias Famichat.Chat.{Conversation, ConversationParticipant, ConversationSecurityStateStore}
  alias Famichat.Accounts.HouseholdMembership
  alias Famichat.Chat
  alias Famichat.Repo

  @impl true
  def mount(params, session, socket) do
    token = session["access_token"] || params["token"]

    with {:ok, {user_id, device_id}} <- ensure_token_valid(token),
         {:ok, user} <- Identity.fetch_user(user_id),
         {:ok, conversations} <- get_user_conversations(user_id) do
      base_socket = assign_socket_state(socket, user, device_id, token, params)

      case conversations do
        [conversation | _] ->
          {:ok,
           base_socket
           |> assign(conversation_id: conversation.id)
           |> load_messages(conversation.id, user.id)}

        [] ->
          {:ok,
           base_socket
           |> assign(
             conversation_id: nil,
             error_message: "No conversations found for this user."
           )
           |> stream(:messages, [], reset: true)}
      end
    else
      {:error, reason} -> assign_auth_error(socket, reason)
    end
  end

  # Sets all common socket assigns shared across every mount path (success and
  # empty-conversations). Keeping this in one place means adding a new assign
  # only requires touching this function and assign_auth_error/2.
  defp assign_socket_state(socket, user, device_id, _token, params) do
    assign(socket,
      channel_joined: false,
      conversation_type: "family",
      current_message: "",
      user_id: user.id,
      device_id: device_id,
      test_username: nil,
      error_message: nil,
      auth_error: nil,
      # auth_token is intentionally NOT assigned — it must not appear in the DOM.
      # The channel bootstrap token is issued on demand via handle_event("connect-channel").
      topic: nil,
      security_reason: nil,
      security_action: nil,
      revoke_target: params["revoke_target"] |> to_string() |> String.trim(),
      recovery_ref: default_recovery_ref(),
      recovery_last_status: nil,
      last_seen_message_id: nil,
      mls_enforcement_enabled: Application.get_env(:famichat, :mls_enforcement, false)
    )
  end

  # NOTE: verify_access_token/1 already checks device existence, user_id
  # ownership, revocation status, and trust window in a single DeviceStore
  # lookup. A second call to device_access_state/2 at mount time would fetch
  # the same DB row again with identical checks — so it is omitted here.
  #
  # device_access_state/2 is still used in handle_event("connect-channel")
  # because that check happens later at channel-join time, after the initial
  # mount, when the device state may have changed (e.g. revoked mid-session).
  defp ensure_token_valid(token) when is_binary(token) do
    with {:ok, %{user_id: user_id, device_id: device_id}} <-
           Sessions.verify_access_token(token) do
      {:ok, {user_id, device_id}}
    end
  end

  defp ensure_token_valid(_), do: {:error, :missing_token}

  defp get_user_conversations(user_id) do
    explicit_ids =
      from p in ConversationParticipant,
        where: p.user_id == ^user_id,
        select: p.conversation_id

    implicit_ids =
      from c in Conversation,
        join: m in HouseholdMembership,
        on: m.family_id == c.family_id,
        where: c.conversation_type == :family and m.user_id == ^user_id,
        select: c.id

    query =
      from c in Conversation,
        distinct: true,
        where:
          c.id in subquery(explicit_ids) or
            c.id in subquery(implicit_ids),
        order_by: [desc: c.inserted_at]

    {:ok, Repo.all(query)}
  rescue
    e in Ecto.QueryError ->
      Logger.error(
        "Query error loading conversations for user #{user_id}: #{Exception.message(e)}"
      )

      {:error, :db_error}
  end

  # NOTE: Ideally this would redirect to the login page, but the login page
  # doesn't exist yet (L1 work in progress). Until then, render inline error.
  # TODO: Replace with push_navigate(socket, to: "/login") once login page exists.
  defp assign_auth_error(socket, reason) do
    {:ok,
     socket
     |> assign(
       channel_joined: false,
       conversation_type: "family",
       conversation_id: nil,
       current_message: "",
       user_id: nil,
       device_id: nil,
       test_username: nil,
       error_message: "Authentication failed: #{inspect(reason)}",
       auth_error: reason,
       topic: nil,
       security_reason: nil,
       security_action: nil,
       revoke_target: "",
       recovery_ref: default_recovery_ref(),
       recovery_last_status: nil,
       last_seen_message_id: nil,
       mls_enforcement_enabled: Application.get_env(:famichat, :mls_enforcement, false)
     )
     |> stream(:messages, [], reset: true)}
  end

  @impl true
  def handle_event("connect-channel", _params, socket) do
    if socket.assigns.channel_joined do
      {:noreply, push_event(socket, "disconnect_channel", %{})}
    else
      user_id = socket.assigns.user_id
      device_id = socket.assigns.device_id
      # socket.id is the LiveView socket ID — a stable identifier for this
      # specific LiveView process. Scoping the channel token to it means
      # the token cannot be replayed in a different LiveView session.
      live_socket_id = socket.id

      case Sessions.issue_channel_token(user_id, device_id, live_socket_id) do
        {:ok, channel_token} ->
          # Push the token to the hook. It is delivered over the
          # already-authenticated LiveView WebSocket — not in the DOM.
          {:noreply, push_event(socket, "connect_channel", %{channel_token: channel_token})}

        {:error, reason} when reason in [:revoked, :device_not_found, :trust_required, :trust_expired] ->
          reason_text = reason_to_string(reason)

          {:noreply,
           socket
           |> assign(
             channel_joined: false,
             topic: nil,
             security_reason: reason_text,
             security_action: security_action_for_reason(reason_text),
             error_message: "Cannot connect: #{message_error_text(reason_text)}"
           )
           |> put_system_notice("Connection blocked: #{reason_text}.")}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             error_message: "Cannot issue channel token: #{inspect(reason)}"
           )}
      end
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
  def handle_event("revoke-target-device", _params, socket) do
    target = socket.assigns.revoke_target |> to_string() |> String.trim()

    cond do
      target == "" ->
        {:noreply,
         assign(socket, error_message: "Enter a device id to revoke.")}

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
             assign(socket,
               error_message: "Device revoke failed: #{inspect(reason)}"
             )}
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
         assign(socket,
           error_message: "Enter a recovery ref before recovering."
         )}

      true ->
        case Chat.recover_conversation_security_state(
               socket.assigns.conversation_id,
               recovery_ref,
               %{
                 rejoin_token:
                   "spike-rejoin-#{System.unique_integer([:positive])}"
               }
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
             assign(socket,
               error_message: "Recovery failed: #{inspect(reason)}"
             )}
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

    reason_text = reason_to_string(reason)

    error_text =
      if reason_text == "connection_error" and
           socket.assigns.security_reason == "revoked" do
        "This device is revoked. Open a fresh link from /admin/spike."
      else
        "Socket error: #{reason_text}"
      end

    {:noreply,
     assign(
       socket,
       channel_joined: false,
       topic: nil,
       error_message: error_text
     )}
  end

  @impl true
  def handle_event("channel_joined", %{"topic" => topic}, socket) do
    Logger.info("Successfully joined channel: #{topic}")

    {:noreply,
     socket
     |> assign(channel_joined: true, error_message: nil, topic: topic)
     |> sync_incremental_messages(
       socket.assigns.conversation_id,
       socket.assigns.user_id
     )}
  end

  @impl true
  def handle_event("join_error", %{"reason" => reason}, socket) do
    Logger.error("Failed to join channel: #{inspect(reason)}")

    {:noreply,
     assign(
       socket,
       channel_joined: false,
       topic: nil,
       error_message: "Failed to join: #{reason_to_string(reason)}"
     )}
  end

  @impl true
  def handle_event("channel_left", _params, socket) do
    {:noreply, assign(socket, channel_joined: false, topic: nil)}
  end

  @impl true
  def handle_event("message_received", payload, socket) do
    message_id = payload["message_id"]

    if not is_binary(message_id) or String.trim(message_id) == "" do
      {:noreply,
       socket
       |> assign(error_message: "Dropped message missing message_id.")
       |> put_system_notice("Dropped message: missing message_id in payload.")}
    else
      received_message = %{
        id: "msg-#{message_id}",
        body: resolve_display_body(payload, socket.assigns),
        timestamp:
          case DateTime.from_iso8601(payload["timestamp"]) do
            {:ok, datetime, _offset} -> datetime
            _error -> DateTime.utc_now()
          end,
        outgoing: payload["user_id"] == socket.assigns.user_id,
        system_message: false,
        sender_name: sender_name_for_payload(payload, socket.assigns)
      }

      {:noreply,
       socket
       |> assign(last_seen_message_id: message_id)
       |> stream_insert(:messages, received_message)}
    end
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

  defp default_recovery_ref do
    "spike-recovery-#{System.unique_integer([:positive])}"
  end

  defp load_messages(socket, nil, _user_id) do
    socket
    |> stream(:messages, [], reset: true)
    |> assign(last_seen_message_id: nil)
  end

  defp load_messages(socket, conversation_id, user_id) do
    case Famichat.Chat.MessageService.get_conversation_messages_page(
           conversation_id,
           limit: 50
         ) do
      {:ok, %{messages: messages, next_cursor: next_cursor}} ->
        rendered =
          Enum.map(messages, fn msg ->
            %{
              id: "msg-#{msg.id}",
              body: msg.content,
              timestamp: msg.inserted_at,
              outgoing: msg.sender_id == user_id,
              system_message: false,
              sender_name: sender_name_for_record(msg, user_id)
            }
          end)

        socket
        |> stream(:messages, rendered, reset: true)
        |> assign(last_seen_message_id: next_cursor)

      {:error, _reason} ->
        socket
        |> stream(:messages, [], reset: true)
        |> assign(last_seen_message_id: nil)
    end
  end

  defp sync_incremental_messages(socket, conversation_id, user_id)
       when is_binary(conversation_id) and is_binary(user_id) do
    opts =
      [limit: 50]
      |> maybe_put_after(socket.assigns.last_seen_message_id)

    case Famichat.Chat.MessageService.get_conversation_messages_page(
           conversation_id,
           opts
         ) do
      {:ok, %{messages: [], next_cursor: _next_cursor}} ->
        socket

      {:ok, %{messages: messages, next_cursor: next_cursor}} ->
        updated_socket =
          Enum.reduce(messages, socket, fn msg, acc ->
            stream_insert(acc, :messages, %{
              id: "msg-#{msg.id}",
              body: msg.content,
              timestamp: msg.inserted_at,
              outgoing: msg.sender_id == user_id,
              system_message: false,
              sender_name: sender_name_for_record(msg, user_id)
            })
          end)

        assign(updated_socket,
          last_seen_message_id:
            next_cursor || socket.assigns.last_seen_message_id
        )

      {:error, _reason} ->
        socket
    end
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

  defp resolve_display_body(payload, assigns) do
    body = Map.get(payload, "body", "")
    message_id = Map.get(payload, "message_id")

    if assigns.mls_enforcement_enabled and encrypted_wire_payload?(body) do
      fetch_decrypted_body(assigns.conversation_id, message_id) ||
        "[Encrypted MLS payload]"
    else
      body
    end
  end

  defp encrypted_wire_payload?(value) when is_binary(value) do
    String.match?(value, ~r/\A[0-9a-fA-F]{120,}\z/)
  end

  defp encrypted_wire_payload?(_), do: false

  defp fetch_decrypted_body(conversation_id, message_id)
       when is_binary(conversation_id) and is_binary(message_id) do
    case Famichat.Chat.MessageService.get_conversation_messages(conversation_id,
           limit: 50
         ) do
      {:ok, messages} ->
        messages
        |> Enum.find(fn message -> message.id == message_id end)
        |> case do
          nil -> nil
          message -> message.content
        end

      _ ->
        nil
    end
  end

  defp fetch_decrypted_body(_conversation_id, _message_id), do: nil

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

  defp message_error_text("revoked"),
    do: "This device is revoked. Open a fresh actor link."

  defp message_error_text("pending_proposals"),
    do: "Conversation is waiting for pending commit to finish."

  defp message_error_text(reason), do: "Message failed: #{reason}"

  defp security_action_for_reason("recovery_required"),
    do: "recover_conversation_security_state"

  defp security_action_for_reason("device_revoked"), do: "reauth_required"
  defp security_action_for_reason("revoked"), do: "reauth_required"

  defp security_action_for_reason("pending_proposals"),
    do: "wait_for_pending_commit"

  defp security_action_for_reason(_), do: nil

  defp reason_to_string(nil), do: ""
  defp reason_to_string(reason) when is_binary(reason), do: reason
  defp reason_to_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_to_string(reason), do: inspect(reason)

  defp maybe_put_after(opts, nil), do: opts
  defp maybe_put_after(opts, ""), do: opts

  defp maybe_put_after(opts, after_cursor),
    do: Keyword.put(opts, :after, after_cursor)
end
