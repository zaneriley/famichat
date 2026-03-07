defmodule FamichatWeb.ConnHelpers do
  @moduledoc """
  Shared connection helpers for web controllers and plugs.
  """

  import Plug.Conn

  alias FamichatWeb.SessionKeys

  @spec put_session_from_issued(Plug.Conn.t(), %{
          access_token: String.t(),
          refresh_token: String.t(),
          device_id: String.t()
        }) :: Plug.Conn.t()
  def put_session_from_issued(
        conn,
        %{
          access_token: access_token,
          refresh_token: refresh_token,
          device_id: device_id
        }
      ) do
    conn
    |> put_session(SessionKeys.access_token(), access_token)
    |> put_session(SessionKeys.refresh_token(), refresh_token)
    |> put_session(SessionKeys.device_id(), device_id)
  end
end
