defmodule FamichatWeb.LocaleCatchAllController do
  use FamichatWeb, :controller

  @doc """
  Redirects any unknown locale-scoped path to the login page for that locale.
  This handles paths like /en/home that have no declared route, preventing the
  Phoenix debug page from appearing in dev and a 500 in prod.
  """
  def redirect_to_login(conn, %{"locale" => locale}) do
    redirect(conn, to: "/#{locale}/login")
  end
end
