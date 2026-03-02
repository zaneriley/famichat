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
       to this LiveView.
  """

  use FamichatWeb, :live_view

  require Logger

  alias Famichat.Auth.Onboarding

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
    |> assign(:payload, payload)
    |> assign(:username, "")
    |> assign(:error, nil)
    |> assign_page_metadata("Join your family")
  end

  defp mount_invalid(socket, error_atom) do
    socket
    |> assign(:step, :invalid)
    |> assign(:registration_token, nil)
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
        {:noreply, assign(socket, :error, :username_too_short)}

      true ->
        {:noreply,
         socket
         |> assign(:step, :register)
         |> assign(:username, username)
         |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_event("register-success", _params, socket) do
    locale = socket.assigns[:user_locale] || "en"
    {:noreply, push_navigate(socket, to: "/#{locale}/login")}
  end

  @impl true
  def handle_event("register-error", %{"message" => message}, socket) do
    Logger.warning("[InviteLive] Passkey registration error: #{inspect(message)}")
    {:noreply, assign(socket, :error, {:register_failed, message})}
  end

  @impl true
  def handle_event("register-error", _params, socket) do
    {:noreply, assign(socket, :error, {:register_failed, "Unknown error"})}
  end

  defp error_message(:expired), do: "This invite link has expired. Ask for a new one."
  defp error_message(:used), do: "This invite link has already been used."
  defp error_message(:invalid), do: "This invite link is not valid."
  defp error_message(:rate_limited), do: "Too many attempts. Please try again later."
  defp error_message(:unknown), do: "Something went wrong. Please try again."
  defp error_message(:username_required), do: "Please enter a username."
  defp error_message(:username_too_short), do: "Username must be at least 2 characters."
  defp error_message({:register_failed, msg}) when is_binary(msg), do: msg
  defp error_message(_), do: "Something went wrong."
end
