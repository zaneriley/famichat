defmodule FamichatWeb.ConnHelpersTest do
  use FamichatWeb.ConnCase, async: true

  import Plug.Conn

  alias FamichatWeb.ConnHelpers
  alias FamichatWeb.SessionKeys

  test "put_session_from_issued/2 stores the issued session keys", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> ConnHelpers.put_session_from_issued(%{
        access_token: "access-token",
        refresh_token: "refresh-token",
        device_id: "device-id"
      })

    assert get_session(conn, SessionKeys.access_token()) == "access-token"
    assert get_session(conn, SessionKeys.refresh_token()) == "refresh-token"
    assert get_session(conn, SessionKeys.device_id()) == "device-id"
  end
end
