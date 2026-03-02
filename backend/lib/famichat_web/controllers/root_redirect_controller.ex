defmodule FamichatWeb.RootRedirectController do
  use FamichatWeb, :controller

  def index(conn, _params) do
    locale = Application.get_env(:famichat, :default_locale, "en")
    redirect(conn, to: "/#{locale}")
  end
end
