defmodule FamichatWeb.Plugs.BearerAuth do
  @moduledoc """
  Verifies a Bearer access token and assigns the authenticated user/device IDs.
  """
  import Plug.Conn

  alias Famichat.Auth.Sessions

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{user_id: user_id, device_id: device_id}} <-
           Sessions.verify_access_token(token) do
      conn
      |> assign(:current_user_id, user_id)
      |> assign(:current_device_id, device_id)
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    body = Jason.encode!(%{error: "unauthorized"})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:unauthorized, body)
    |> halt()
  end
end
