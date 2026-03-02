defmodule FamichatWeb.AuthLive.LoginLive do
  use FamichatWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:error, nil)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("passkey-result", %{"token" => token}, socket) do
    locale = socket.assigns[:user_locale] || "en"
    # The access_token is now stored in the Plug session cookie (set by the
    # passkey assert endpoint). Navigate without the token in the URL so it
    # is not exposed in browser history or server logs. HomeLive reads the
    # token from the session. The URL param is kept as a fallback only.
    _ = token
    {:noreply, push_navigate(socket, to: "/#{locale}/")}
  end

  @impl true
  def handle_event("passkey-error", %{"message" => msg}, socket) do
    Logger.warning("[LoginLive] passkey-error: #{inspect(msg)}")
    {:noreply, assign(socket, error: msg, loading: false)}
  end

  @impl true
  def handle_event("passkey-loading", _params, socket) do
    {:noreply, assign(socket, loading: true, error: nil)}
  end
end
