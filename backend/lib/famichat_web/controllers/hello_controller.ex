defmodule FamichatWeb.HelloController do
  use FamichatWeb, :controller

  def index(conn, _params) do
    json(conn, %{message: "Hello from Famichat!"})
  end
end
