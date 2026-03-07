defmodule FamichatWeb.Plugs.SessionRefresh do
  @moduledoc """
  Transparently refreshes an expired access token using the refresh token
  stored in the Plug session.

  When the access_token in the session is expired (or missing) but a valid
  refresh_token + device_id pair exists, this plug calls
  `Sessions.refresh_session/2` and writes the new tokens back into the
  session cookie. Downstream LiveViews then see a valid access_token on
  mount without needing to redirect to login.

  Place this plug in the `:browser` pipeline, after `:fetch_session`.
  """

  import Plug.Conn
  require Logger

  alias Famichat.Auth.Sessions

  def init(opts), do: opts

  def call(conn, _opts) do
    access_token = get_session(conn, "access_token")

    if is_binary(access_token) do
      case Sessions.verify_access_token(access_token) do
        {:ok, _} ->
          conn

        {:error, _} ->
          maybe_refresh(conn)
      end
    else
      # No access token in session — try refresh if we have credentials.
      maybe_refresh(conn)
    end
  end

  defp maybe_refresh(conn) do
    refresh_token = get_session(conn, "refresh_token")
    device_id = get_session(conn, "device_id")

    if is_binary(refresh_token) and is_binary(device_id) do
      case Sessions.refresh_session(device_id, refresh_token) do
        {:ok, new_tokens} ->
          Logger.info("[SessionRefresh] Auto-refreshed session for device #{device_id}")

          conn
          |> put_session(:access_token, new_tokens.access_token)
          |> put_session(:refresh_token, new_tokens.refresh_token)
          |> put_session(:device_id, new_tokens.device_id)

        {:error, reason} ->
          Logger.debug("[SessionRefresh] Refresh failed: #{inspect(reason)}")
          conn
      end
    else
      conn
    end
  end
end
