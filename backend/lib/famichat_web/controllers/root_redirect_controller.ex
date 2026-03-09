defmodule FamichatWeb.RootRedirectController do
  use FamichatWeb, :controller

  def index(conn, _params) do
    locale = FamichatWeb.Plugs.SetLocale.extract_preferred_locale(conn)
    redirect(conn, to: "/#{locale}/")
  end
end
