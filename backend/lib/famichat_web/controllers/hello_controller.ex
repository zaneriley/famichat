defmodule FamichatWeb.HelloController do
  use FamichatWeb, :controller

  def index(conn, _params) do
    json(conn, %{message: gettext("Hello from %{app_name}!", app_name: app_name())})
  end
end
