defmodule FamichatWeb.Plugs.BearerAuth do
  @moduledoc """
  Verifies a Bearer access token and assigns the authenticated user/device IDs.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

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
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "unauthorized"}})
    |> halt()
  end
end
