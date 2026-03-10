defmodule FamichatWeb.HomeLive do
  use FamichatWeb, :live_view
  import Ecto.Query
  require Logger

  alias Famichat.Auth.{Identity, Sessions}

  alias Famichat.Chat.{
    Conversation,
    ConversationParticipant,
    ConversationSecurityStateStore
  }

  alias Famichat.Accounts.{FamilyContext, HouseholdMembership, User}
  alias Famichat.Chat
  alias Famichat.Auth.Onboarding
  alias Famichat.Repo

  @impl true
  def mount(params, session, socket) do
    token = session["access_token"] || params["token"]
    candidate_family_id = params["switch_family"] || session["active_family_id"]

    with {:ok, {user_id, device_id}} <- ensure_token_valid(token),
         {:ok, user} <- Identity.fetch_user(user_id) do
      case FamilyContext.resolve(user_id, candidate_family_id) do
        {:ok, family, source} ->
          mount_with_family(socket, user, device_id, token, params, family, source)

        {:error, :no_family} ->
          mount_without_family(socket, user, device_id, token, params)
      end
    else
      {:error, reason} -> assign_auth_error(socket, reason)
    end
  end

  defp mount_with_family(socket, user, device_id, token, params, family, source) do
    family_members = load_family_members(family.id, user.id)
    is_admin = load_is_admin(user.id, family.id)
    all_memberships = FamilyContext.all_memberships(user.id)
    show_family_switcher = length(all_memberships) > 1

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Famichat.PubSub, "family:#{family.id}:member_joined")
    end

    {:ok, conversations} = get_user_conversations(user.id, family.id)

    base_socket =
      socket
      |> assign_socket_state(user, device_id, token, params)
      |> assign(
        current_user: user,
        family: family,
        active_family_id: family.id,
        family_members: family_members,
        is_admin: is_admin,
        all_memberships: all_memberships,
        show_family_switcher: show_family_switcher,
        family_source: source,
        conversations: conversations,
        invite_url: nil,
        no_family: false
      )

    case conversations do
      [conversation | _] ->
        page_title =
          case family_members do
            [other] -> other.username
            _ -> family.name
          end

        conv_type = Atom.to_string(conversation.conversation_type)

        result_socket =
          base_socket
          |> assign(conversation_id: conversation.id, conversation_type: conv_type)
          |> load_messages(conversation.id, user.id)
          |> assign_page_metadata(page_title)

        if connected?(result_socket) do
          send(self(), :auto_connect)
        end

        {:ok, result_socket}

      [] ->
        {:ok,
         base_socket
         |> assign(
           conversation_id: nil,
           error_message: nil
         )
         |> assign_page_metadata(family.name)
         |> stream(:messages, [], reset: true)}
    end
  end

  defp mount_without_family(socket, user, device_id, token, params) do
    {:ok,
     socket
     |> assign_socket_state(user, device_id, token, params)
     |> assign(
       current_user: user,
       family: nil,
       active_family_id: nil,
       family_members: [],
       is_admin: false,
       all_memberships: [],
       show_family_switcher: false,
       family_source: nil,
       conversations: [],
       invite_url: nil,
       no_family: true,
       conversation_id: nil,
       error_message: nil
     )
     |> stream(:messages, [], reset: true)}
  end

  # Sets all common socket assigns shared across every mount path (success and
  # empty-conversations). Keeping this in one place means adding a new assign
  # only requires touching this function and assign_auth_error/2.
  defp assign_socket_state(socket, user, device_id, _token, params) do
    assign(socket,
      channel_joined: false,
      conversation_type: nil,
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
      mls_enforcement_enabled:
        Application.get_env(:famichat, :mls_enforcement, false),
      dev_mode: Application.get_env(:famichat, :environment) == :dev,
      show_welcome_prompt: false,
      welcome_message: "",
      pending_welcome_message: nil
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

  defp get_user_conversations(user_id, family_id) do
    explicit_ids =
      from p in ConversationParticipant,
        join: c in Conversation,
        on: c.id == p.conversation_id,
        where: p.user_id == ^user_id and c.family_id == ^family_id,
        select: p.conversation_id

    implicit_ids =
      from c in Conversation,
        join: m in HouseholdMembership,
        on: m.family_id == c.family_id,
        where:
          c.conversation_type == :family and
            m.user_id == ^user_id and
            c.family_id == ^family_id,
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
        "Query error loading conversations for user #{user_id} family #{family_id}: #{Exception.message(e)}"
      )

      {:error, :db_error}
  end

  defp assign_auth_error(socket, reason) do
    {:ok,
     socket
     |> assign(
       current_user: nil,
       user_id: nil,
       device_id: nil,
       auth_error: reason,
       error_message: nil,
       family: nil,
       active_family_id: nil,
       family_members: [],
       is_admin: false,
       all_memberships: [],
       show_family_switcher: false,
       family_source: nil,
       conversations: [],
       conversation_id: nil,
       invite_url: nil,
       no_family: true,
       channel_joined: false,
       conversation_type: nil,
       current_message: "",
       topic: nil,
       security_reason: nil,
       security_action: nil,
       revoke_target: "",
       recovery_ref: nil,
       recovery_last_status: nil,
       last_seen_message_id: nil,
       mls_enforcement_enabled: false,
       dev_mode: false,
       show_welcome_prompt: false,
       welcome_message: "",
       pending_welcome_message: nil
     )
     |> stream(:messages, [], reset: true)
     |> push_navigate(to: locale_path(socket, "/login"))}
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
          {:noreply,
           push_event(socket, "connect_channel", %{channel_token: channel_token})}

        {:error, reason}
        when reason in [
               :revoked,
               :device_not_found,
               :trust_required,
               :trust_expired
             ] ->
          reason_text = reason_to_string(reason)

          {:noreply,
           socket
           |> assign(
             channel_joined: false,
             topic: nil,
             security_reason: reason_text,
             security_action: security_action_for_reason(reason_text),
             error_message: message_error_text(reason_text)
           )
           |> put_system_notice("Connection blocked: #{reason_text}.")}

        {:error, _reason} ->
          {:noreply,
           assign(socket,
             error_message: gettext("Something went wrong connecting. Try refreshing.")
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
         assign(socket,
           error_message: gettext("Still connecting. Try again in a moment.")
         )}
    end
  end

  @impl true
  def handle_event("revoke-target-device", _params, socket) do
    target = socket.assigns.revoke_target |> to_string() |> String.trim()

    cond do
      target == "" ->
        {:noreply,
         assign(socket, error_message: gettext("Enter a device id to revoke."))}

      true ->
        case Sessions.revoke_device(socket.assigns.user_id, target) do
          {:ok, :revoked} ->
            {:noreply,
             socket
             |> assign(error_message: nil)
             |> put_system_notice(gettext("Revoked device %{device}.", device: target))}

          {:error, :not_found} ->
            {:noreply,
             assign(
               socket,
               error_message: gettext("Device %{device} not found for this user.", device: target)
             )}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               error_message: gettext("Device revoke failed: %{reason}", reason: inspect(reason))
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
  def handle_event("sign-out", _params, socket) do
    {:noreply, redirect(socket, to: locale_path(socket, "/logout"))}
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
        gettext("This device has been removed. Please sign in again.")
      else
        gettext("Something went wrong with the connection. Try refreshing.")
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
  def handle_event("copied", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("join_error", %{"reason" => reason}, socket) do
    Logger.error("Failed to join channel: #{inspect(reason)}")

    {:noreply,
     assign(
       socket,
       channel_joined: false,
       topic: nil,
       error_message: gettext("Something went wrong connecting. Try refreshing.")
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
       |> assign(error_message: nil)
       |> put_system_notice("A message could not be displayed.")}
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
       error_message: message_error_text(reason)
     )
     |> put_system_notice("Security state changed: #{reason} (#{action}).")}
  end

  @impl true
  def handle_event("generate_invite", _params, socket) do
    user = socket.assigns[:current_user]
    family = socket.assigns[:family]

    cond do
      is_nil(user) or is_nil(family) ->
        {:noreply,
         assign(socket,
           error_message: gettext("You must be in a family to generate an invite.")
         )}

      true ->
        case Onboarding.issue_invite(user.id, nil, %{
               household_id: family.id,
               role: "member"
             }) do
          {:ok, %{invite: invite_token}} ->
            invite_url =
              "#{FamichatWeb.Endpoint.url()}/#{socket.assigns[:user_locale] || "en"}/invites/#{invite_token}"

            {:noreply,
             socket
             |> assign(invite_url: invite_url, error_message: nil)
             |> assign(show_welcome_prompt: true, welcome_message: "")}

          {:error, reason} ->
            Logger.warning("[HomeLive] issue_invite error: #{inspect(reason)}")

            {:noreply,
             assign(socket, error_message: gettext("Could not generate invite link."))}
        end
    end
  end

  @impl true
  def handle_event("submit-welcome-message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, assign(socket, show_welcome_prompt: false)}
    else
      {:noreply,
       socket
       |> assign(show_welcome_prompt: false)
       |> assign(pending_welcome_message: message)}
    end
  end

  @impl true
  def handle_event("skip-welcome-prompt", _params, socket) do
    {:noreply, assign(socket, show_welcome_prompt: false)}
  end

  @impl true
  def handle_info(:auto_connect, socket) do
    # Triggered on connected mount to join the channel without user interaction.
    # Reuses the same logic as handle_event("connect-channel").
    if socket.assigns.channel_joined do
      {:noreply, socket}
    else
      user_id = socket.assigns.user_id
      device_id = socket.assigns.device_id
      live_socket_id = socket.id

      case Sessions.issue_channel_token(user_id, device_id, live_socket_id) do
        {:ok, channel_token} ->
          {:noreply,
           push_event(socket, "connect_channel", %{channel_token: channel_token})}

        {:error, reason}
        when reason in [
               :revoked,
               :device_not_found,
               :trust_required,
               :trust_expired
             ] ->
          reason_text = reason_to_string(reason)

          {:noreply,
           socket
           |> assign(
             channel_joined: false,
             topic: nil,
             security_reason: reason_text,
             security_action: security_action_for_reason(reason_text),
             error_message: message_error_text(reason_text)
           )
           |> put_system_notice("Connection blocked: #{reason_text}.")}

        {:error, _reason} ->
          {:noreply,
           assign(socket,
             error_message: gettext("Something went wrong connecting. Try refreshing.")
           )}
      end
    end
  end

  @impl true
  def handle_info({:channel_push_confirmed, _ref}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "member_joined"}, socket) do
    if socket.assigns.conversation_id != nil do
      {:noreply, socket}
    else
      user_id = socket.assigns.user_id
      family_id = socket.assigns.active_family_id

      case get_user_conversations(user_id, family_id) do
        {:ok, [conversation | _]} ->
          conv_type = Atom.to_string(conversation.conversation_type)
          family_members = load_family_members(family_id, user_id)

          page_title =
            case family_members do
              [other] -> other.username
              _ -> socket.assigns.family && socket.assigns.family.name
            end

          result_socket =
            socket
            |> assign(
              conversation_id: conversation.id,
              conversation_type: conv_type,
              show_welcome_prompt: false,
              family_members: family_members
            )
            |> maybe_inject_welcome_message(conversation.id, user_id)
            |> load_messages(conversation.id, user_id)
            |> assign_page_metadata(page_title)

          send(self(), :auto_connect)

          {:noreply, result_socket}

        _ ->
          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  ## -- Welcome message injection ---------------------------------------------

  defp maybe_inject_welcome_message(socket, conversation_id, user_id) do
    case socket.assigns[:pending_welcome_message] do
      nil ->
        socket

      "" ->
        socket

      message when is_binary(message) ->
        case Famichat.Chat.MessageService.send_message(%{
               conversation_id: conversation_id,
               sender_id: user_id,
               content: message
             }) do
          {:ok, _msg} ->
            socket
            |> assign(pending_welcome_message: nil)
            |> load_messages(conversation_id, user_id)

          {:error, reason} ->
            Logger.warning("[HomeLive] Failed to inject welcome message: #{inspect(reason)}")
            assign(socket, pending_welcome_message: nil)
        end
    end
  end

  ## -- Family data loading ---------------------------------------------------

  defp load_family_members(family_id, current_user_id) do
    from(u in User,
      join: m in HouseholdMembership,
      on: m.user_id == u.id,
      where: m.family_id == ^family_id and u.id != ^current_user_id,
      select: %{id: u.id, username: u.username}
    )
    |> Repo.all()
  rescue
    e ->
      Logger.error(
        "Failed to load family members for family #{family_id}: #{Exception.message(e)}"
      )

      []
  end

  defp load_is_admin(user_id, family_id) do
    case Repo.get_by(HouseholdMembership, user_id: user_id, family_id: family_id) do
      %{role: :admin} -> true
      _ -> false
    end
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
    cond do
      payload["user_id"] == assigns.user_id -> "Me"
      is_binary(payload["sender_name"]) and payload["sender_name"] != "" -> payload["sender_name"]
      true -> "Family Member"
    end
  end

  defp message_error_text("recovery_required"),
    do: gettext("Something went wrong with this session. Try refreshing.")

  defp message_error_text("device_revoked"),
    do: gettext("This device has been removed. Please sign in again.")

  defp message_error_text("revoked"),
    do: gettext("This device has been removed. Please sign in again.")

  defp message_error_text("pending_proposals"),
    do: gettext("Setting things up. This should only take a moment.")

  defp message_error_text(_reason), do: gettext("Something went wrong. Try refreshing.")

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

  # Human-friendly labels for security state banners shown to end users.
  defp security_reason_display("recovery_required"),
    do: gettext("Something needs attention. Try refreshing.")

  defp security_reason_display("device_revoked"),
    do: gettext("This device has been removed. Please sign in again.")

  defp security_reason_display("revoked"),
    do: gettext("This device has been removed. Please sign in again.")

  defp security_reason_display("epoch_too_low"),
    do: gettext("Your session is out of date. Try refreshing.")

  defp security_reason_display("epoch_too_high"),
    do: gettext("Your session is out of date. Try refreshing.")

  defp security_reason_display("pending_proposals"),
    do: gettext("Setting things up. This should only take a moment.")

  defp security_reason_display(_),
    do: gettext("Something needs attention. Try refreshing.")

  defp maybe_put_after(opts, nil), do: opts
  defp maybe_put_after(opts, ""), do: opts

  defp maybe_put_after(opts, after_cursor),
    do: Keyword.put(opts, :after, after_cursor)

  defp build_localized_path(current_path, locale) do
    base_path = FamichatWeb.Layouts.remove_locale_from_path(current_path)

    if base_path == "/" do
      "/#{locale}"
    else
      "/#{locale}#{base_path}"
    end
  end
end
