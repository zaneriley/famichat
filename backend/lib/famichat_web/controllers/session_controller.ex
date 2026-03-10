defmodule FamichatWeb.SessionController do
  @moduledoc """
  Handles browser session lifecycle operations that require a Plug pipeline.

  LiveView cannot call clear_session/1 directly. Any action that must write
  or clear the Plug session cookie must go through a controller action so it
  runs inside the Plug pipeline.
  """

  use FamichatWeb, :controller
  require Logger

  alias Famichat.Auth.Sessions
  alias FamichatWeb.SessionKeys

  @doc """
  Revokes the current device and clears all session data, then redirects to
  the login page.

  Called via GET /:locale/logout from a LiveView redirect. GET is used
  because Phoenix.LiveView.redirect/2 only generates GET navigations.
  """
  def delete(conn, %{"locale" => locale}) do
    device_id = get_session(conn, SessionKeys.device_id())
    access_token = get_session(conn, SessionKeys.access_token())

    with true <- is_binary(device_id) and is_binary(access_token),
         {:ok, %{user_id: user_id}} <- Sessions.verify_access_token(access_token) do
      case Sessions.revoke_device(user_id, device_id) do
        {:ok, :revoked} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "[SessionController.delete] Failed to revoke device: #{inspect(reason)}",
            user_id: user_id,
            device_id: device_id
          )
      end
    else
      _ -> :ok
    end

    conn
    |> clear_session()
    |> redirect(to: "/#{locale}/login")
  end
end
