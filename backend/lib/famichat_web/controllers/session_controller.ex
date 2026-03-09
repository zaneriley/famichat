defmodule FamichatWeb.SessionController do
  @moduledoc """
  Handles browser session lifecycle operations that require a Plug pipeline.

  LiveView cannot call clear_session/1 directly. Any action that must write
  or clear the Plug session cookie must go through a controller action so it
  runs inside the Plug pipeline.
  """

  use FamichatWeb, :controller

  @doc """
  Clears all session data and redirects to the login page.

  Called via GET /:locale/logout from a LiveView redirect. GET is used
  because Phoenix.LiveView.redirect/2 only generates GET navigations.
  """
  def delete(conn, %{"locale" => locale}) do
    conn
    |> clear_session()
    |> redirect(to: "/#{locale}/login")
  end
end
