defmodule FamichatWeb.Plugs.ValidateFamilySetupToken do
  @moduledoc """
  Validates the family setup token in the URL before the LiveView mounts.

  This plug runs during the HTTP phase (before WebSocket upgrade), so it can
  return non-200 HTTP status codes. It only applies to routes that match the
  family setup pattern: /:locale/families/start/:token.

  Behavior:
  - Token structurally malformed (nil, empty, or not a valid token format): 404
  - Token invalid (not in DB): 404
  - Token expired or used: pass through to FamilySetupLive, which shows
    friendly error UI with its :invalid step
  - Token valid: pass through, LiveView mounts normally
  """

  import Plug.Conn

  import Phoenix.Controller,
    only: [put_layout: 2, put_root_layout: 2, put_view: 2, render: 2]

  alias Famichat.Auth.Onboarding

  @behaviour Plug
  @token_pattern ~r/^[A-Za-z0-9_-]+$/
  @max_token_length 256

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    token = conn.path_params["token"]

    if structurally_valid_token?(token) do
      validate_and_gate(conn, token)
    else
      halt_with(conn, 404)
    end
  end

  defp validate_and_gate(conn, raw_token) do
    case Onboarding.validate_family_setup_token(raw_token) do
      {:ok, _payload} ->
        conn

      {:error, :invalid} ->
        halt_with(conn, 404)

      # Expired and used tokens pass through to FamilySetupLive,
      # which renders friendly error UI via its :invalid step.
      {:error, :expired} ->
        conn

      {:error, :used} ->
        conn
    end
  end

  defp halt_with(conn, status) do
    locale = conn.path_params["locale"] || "en"

    conn
    |> assign(:user_locale, locale)
    |> put_status(status)
    |> put_root_layout(false)
    |> put_layout(false)
    |> put_view(FamichatWeb.ErrorHTML)
    |> render("#{status}.html")
    |> halt()
  end

  defp structurally_valid_token?(token)
       when is_binary(token) and token != "" do
    byte_size(token) <= @max_token_length and
      Regex.match?(@token_pattern, token)
  end

  defp structurally_valid_token?(_), do: false
end
