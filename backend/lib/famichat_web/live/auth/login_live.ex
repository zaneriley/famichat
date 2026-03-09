defmodule FamichatWeb.AuthLive.LoginLive do
  use FamichatWeb, :live_view
  require Logger

  alias Famichat.Auth.Sessions

  @impl true
  def mount(_params, session, socket) do
    token = session["access_token"]

    if is_binary(token) and match?({:ok, _}, Sessions.verify_access_token(token)) do
      {:ok, push_navigate(socket, to: locale_path(socket, "/"))}
    else
      {:ok,
       socket
       |> assign(:error, nil)
       |> assign(:loading, false)}
    end
  end

  @impl true
  def handle_event("passkey-result", %{"token" => token}, socket) do
    # The access_token is now stored in the Plug session cookie (set by the
    # passkey assert endpoint). Navigate without the token in the URL so it
    # is not exposed in browser history or server logs. HomeLive reads the
    # token from the session. The URL param is kept as a fallback only.
    _ = token
    {:noreply, push_navigate(socket, to: locale_path(socket, "/"))}
  end

  @impl true
  def handle_event("passkey-error", %{"code" => code} = params, socket) when is_binary(code) do
    Logger.warning("[LoginLive] passkey-error: #{code} — #{Map.get(params, "message", "")}")
    {:noreply, assign(socket, error: normalize_passkey_error(code), loading: false)}
  end

  # Fallback for events that carry only a message and no code (e.g. legacy hooks).
  @impl true
  def handle_event("passkey-error", %{"message" => msg}, socket) do
    Logger.warning("[LoginLive] passkey-error (no code): #{msg}")
    {:noreply, assign(socket, error: normalize_passkey_error(msg), loading: false)}
  end

  @impl true
  def handle_event("passkey-loading", _params, socket) do
    {:noreply, assign(socket, loading: true, error: nil)}
  end

  defp normalize_passkey_error(raw) when is_binary(raw) do
    cond do
      String.contains?(raw, "NotAllowedError") -> :cancelled
      String.contains?(raw, "cancelled") -> :cancelled
      String.contains?(raw, "AbortError") -> :cancelled
      String.contains?(raw, "SecurityError") -> :security_error
      String.contains?(raw, "NotSupportedError") -> :not_supported
      String.contains?(raw, "InvalidStateError") -> :invalid_state
      String.contains?(raw, "invalid_credentials") -> :invalid_credentials
      String.contains?(raw, "invalid_challenge") -> :session_expired
      String.contains?(raw, "rate_limited") -> :rate_limited
      String.contains?(raw, "challenge_failed") -> :challenge_failed
      String.contains?(raw, "assert_failed") -> :assert_failed
      String.contains?(raw, "network") -> :network_error
      true -> :unknown
    end
  end

  # User cancelled or timed out the biometric/passkey prompt
  defp error_message(:cancelled),
    do: gettext("Sign-in was cancelled or timed out. Tap the button and follow your device's prompt.")

  # Browser blocked the request (wrong origin, insecure context, etc.)
  defp error_message(:security_error),
    do: gettext("Something went wrong connecting securely. Try a different browser or check your URL.")

  # Browser lacks WebAuthn support
  defp error_message(:not_supported),
    do: gettext("Your browser doesn't support passkeys. Try Safari, Chrome, or Edge.")

  # Authenticator already registered / conflicting state
  defp error_message(:invalid_state),
    do: gettext("Something went wrong with your passkey. Try refreshing the page.")

  # Server could not verify the passkey credential
  defp error_message(:invalid_credentials),
    do: gettext("Something went wrong verifying your passkey. Try again.")

  # Challenge expired before completion
  defp error_message(:session_expired),
    do: gettext("Your sign-in session expired. Tap the button to start again.")

  # Too many sign-in attempts
  defp error_message(:rate_limited),
    do: gettext("Too many attempts. Wait a moment and try again.")

  # Could not obtain a challenge from the server
  defp error_message(:challenge_failed),
    do: gettext("Something went wrong starting sign-in. Try again.")

  # Server assertion verification failed
  defp error_message(:assert_failed),
    do: gettext("Something went wrong signing in. Try again.")

  # Network connectivity issue
  defp error_message(:network_error),
    do: gettext("Something went wrong connecting. Check your connection and try again.")

  # Catch-all
  defp error_message(:unknown),
    do: gettext("Something went wrong signing in. Try again.")

  defp error_message(msg) when is_binary(msg), do: msg
  defp error_message(_), do: gettext("Something went wrong signing in. Try again.")
end
