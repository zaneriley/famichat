defmodule FamichatWeb.AuthLive.InviteLive do
  @moduledoc """
  LiveView for the invite acceptance and passkey registration flow.

  ## Steps

    1. `:loading` — SSR-only placeholder rendered during the disconnected mount.
       No DB calls are made. Replaced immediately by the connected mount.
    2. `:accept` — connected mount consumes the invite token via
       `Onboarding.accept_invite/1` and shows the username form. On reconnect,
       recovers state from the session via `Onboarding.peek_invite/1` without
       re-consuming the token.
    3. `:register` — after username submission, shows the passkey registration
       button. A JS hook (`PasskeyRegister`) drives the WebAuthn flow entirely
       client-side, then pushes `"register-success"` or `"register-error"` back
       to this LiveView. The hook may also push `"step1-complete"` with a
       `passkey_register_token` once the invite is consumed server-side, enabling
       token-skip on retry.
    4. `:success` — shown for 1.5 s after successful registration before
       `Process.send_after/3` fires `:redirect_home` and navigates to `/locale/`.

  ## Error taxonomy

  `register-error` events carry a `code` field that classifies the failure:

    * Recoverable — `"cancelled"`, `"aborted"`, `"network"`,
      `"passkey_registration_failed"`, `"challenge_failed"`,
      `"invalid_challenge"`, `"expired"`, `"used"` — the error is shown and
      the registration button remains visible so the user can try again.

    * Fatal — `"unsupported"`, `"already_registered"`,
      `"missing_registration_token"` — the button is hidden and a message
      with a Go back option is shown instead.
  """

  use FamichatWeb, :live_view

  require Logger

  alias Famichat.Auth.Identity
  alias Famichat.Auth.Onboarding

  @recoverable_codes ~w(cancelled aborted network passkey_registration_failed
                        challenge_failed invalid_challenge expired used)

  @fatal_codes ~w(unsupported already_registered missing_registration_token)

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if connected?(socket) do
      mount_connected(token, socket)
    else
      # Disconnected (SSR) phase: render a neutral loading state.
      # No DB calls, no side effects. The connected mount does the real work.
      {:ok,
       socket
       |> assign(:step, :loading)
       |> assign(:registration_token, nil)
       |> assign(:passkey_register_token, nil)
       |> assign(:payload, %{})
       |> assign(:username, "")
       |> assign(:error, nil)
       |> assign_page_metadata("Join your family")}
    end
  end

  defp mount_connected(token, socket) do
    case Onboarding.accept_invite(token) do
      {:ok, %{payload: payload, registration_token: registration_token}} ->
        # First mount — normal happy path.
        {:ok, assign_accept_step(socket, payload, registration_token)}

      {:error, :used} ->
        # Reconnect after the invite was already consumed (AUDIT-010). Recover
        # payload and re-issue a registration token without re-consuming.
        case Onboarding.peek_invite(token) do
          {:ok, payload, registration_token} ->
            {:ok, assign_accept_step(socket, payload, registration_token)}

          {:error, reason} ->
            {:ok, mount_invalid(socket, reason)}
        end

      {:error, :expired} ->
        {:ok, mount_invalid(socket, :expired)}

      {:error, :invalid} ->
        {:ok, mount_invalid(socket, :invalid)}

      {:error, {:rate_limited, _}} ->
        {:ok, mount_invalid(socket, :rate_limited)}

      {:error, reason} ->
        Logger.warning("[InviteLive] Unexpected error accepting invite: #{inspect(reason)}")
        {:ok, mount_invalid(socket, :unknown)}
    end
  end

  defp assign_accept_step(socket, payload, registration_token) do
    socket
    |> assign(:step, :accept)
    |> assign(:registration_token, registration_token)
    |> assign(:passkey_register_token, nil)
    |> assign(:payload, payload)
    |> assign(:username, "")
    |> assign(:error, nil)
    |> assign_page_metadata("Join your family")
  end

  defp mount_invalid(socket, error_atom) do
    socket
    |> assign(:step, :invalid)
    |> assign(:registration_token, nil)
    |> assign(:passkey_register_token, nil)
    |> assign(:payload, %{})
    |> assign(:username, "")
    |> assign(:error, error_atom)
    |> assign_page_metadata("Invite not valid")
  end

  @impl true
  def handle_event("submit-username", %{"username" => username}, socket) do
    username = String.trim(username)

    cond do
      username == "" ->
        {:noreply, assign(socket, :error, :username_required)}

      String.length(username) < 2 ->
        {:noreply, socket |> assign(:error, :username_too_short) |> assign(:username, username)}

      username_taken?(username) ->
        {:noreply, socket |> assign(:error, :username_taken) |> assign(:username, username)}

      true ->
        {:noreply,
         socket
         |> assign(:step, :register)
         |> assign(:username, username)
         |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_event("go-back", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :accept)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("register-success", _params, socket) do
    Process.send_after(self(), :redirect_home, 1500)
    {:noreply, assign(socket, :step, :success)}
  end

  # Fired by the PasskeyRegister hook after complete_invite succeeds
  # server-side. Stores the token so the hook can skip Step 1 on retry
  # without hitting the server again.
  @impl true
  def handle_event("step1-complete", %{"passkey_register_token" => token}, socket) do
    {:noreply, assign(socket, :passkey_register_token, token)}
  end

  @impl true
  def handle_event("register-error", %{"code" => "username_taken"}, socket) do
    {:noreply,
     socket
     |> assign(:step, :accept)
     |> assign(:error, :username_taken)}
  end

  # Recoverable errors — show the message, keep the button visible.
  @impl true
  def handle_event(
        "register-error",
        %{"code" => code, "message" => message},
        socket
      )
      when code in @recoverable_codes do
    Logger.info("[InviteLive] Recoverable passkey error (#{code}): #{message}")
    {:noreply, assign(socket, :error, {:recoverable, message})}
  end

  # Fatal errors — replace the button with a permanent error + go-back.
  def handle_event("register-error", %{"code" => code}, socket)
      when code in @fatal_codes do
    Logger.warning("[InviteLive] Fatal passkey error: #{inspect(code)}")
    {:noreply, assign(socket, :error, {:fatal, code})}
  end

  # Fallback for events that carry only a message and no known code.
  def handle_event("register-error", %{"message" => message}, socket) do
    Logger.warning("[InviteLive] Passkey registration error (no code): #{message}")
    {:noreply, assign(socket, :error, {:recoverable, message})}
  end

  # Bare catch-all.
  def handle_event("register-error", _params, socket) do
    {:noreply, assign(socket, :error, {:recoverable, gettext("Unknown error")})}
  end

  @impl true
  def handle_info(:redirect_home, socket) do
    {:noreply, push_navigate(socket, to: locale_path(socket, "/"))}
  end

  defp username_taken?(username) do
    case Identity.fetch_user_by_username(username) do
      {:ok, _} -> true
      {:error, :user_not_found} -> false
    end
  end

  defp error_message(:expired), do: gettext("This invite link has expired. Ask for a new one.")
  defp error_message(:used), do: gettext("This invite link has already been used.")
  defp error_message(:invalid), do: gettext("This invite link is not valid.")
  defp error_message(:rate_limited), do: gettext("Too many attempts. Please try again later.")
  defp error_message(:unknown), do: gettext("Something went wrong. Please try again.")
  defp error_message(:username_required), do: gettext("Please enter a username.")
  defp error_message(:username_too_short), do: gettext("Username must be at least 2 characters.")

  defp error_message(:username_taken),
    do: gettext("That name is already taken. Please choose a different one.")

  defp error_message({:recoverable, msg}) when is_binary(msg), do: msg
  defp error_message({:fatal, "missing_registration_token"}),
    do: gettext("Registration token missing. Please go back and try again.")

  defp error_message({:fatal, _code}), do: gettext("Something went wrong. Please go back and try again.")
  defp error_message(_), do: gettext("Something went wrong.")
end
