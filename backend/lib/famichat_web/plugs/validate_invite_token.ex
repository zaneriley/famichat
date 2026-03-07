defmodule FamichatWeb.Plugs.ValidateInviteToken do
  @moduledoc """
  Validates the invite token in the URL before the LiveView mounts.

  This plug runs during the HTTP phase (before WebSocket upgrade), so it can
  return non-200 HTTP status codes. It only applies to routes that match the
  invite pattern: /:locale/invites/:token.

  Behavior:
  - Token structurally malformed (nil, empty, or not a valid token format): 404
  - Token invalid, expired, or used: pass through to InviteLive, which shows
    friendly error UI with its :invalid step
  - Token valid: pass through, LiveView mounts normally
  - Session already has this token (reconnect after consume): pass through

  Rate limiting is intentionally NOT enforced here — the plug only reads the
  token's DB state. Rate limiting lives in Onboarding.accept_invite, which
  runs in the LiveView's connected mount for valid tokens.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [render: 2, put_view: 2]

  alias Famichat.Auth.Onboarding
  alias FamichatWeb.SessionKeys

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    token = conn.path_params["token"]

    if is_binary(token) and token != "" do
      validate_and_gate(conn, token)
    else
      halt_with(conn, 404)
    end
  end

  defp validate_and_gate(conn, raw_token) do
    # If this browser session already accepted this token (reconnect path from
    # AUDIT-010 fix), pass through so the LiveView can recover from session.
    stored_invite = get_session(conn, SessionKeys.invite_token())

    if stored_invite == raw_token do
      conn
    else
      case Onboarding.validate_invite_token(raw_token) do
        :ok ->
          conn

        # Invalid, expired, and used tokens all pass through to InviteLive,
        # which renders friendly error UI via its :invalid step.
        {:error, :invalid} ->
          conn

        {:error, :expired} ->
          conn

        {:error, :used} ->
          conn
      end
    end
  end

  defp halt_with(conn, status) do
    locale = conn.path_params["locale"] || "en"

    conn
    |> assign(:user_locale, locale)
    |> put_status(status)
    |> put_view(FamichatWeb.ErrorHTML)
    |> render("#{status}.html")
    |> halt()
  end
end
