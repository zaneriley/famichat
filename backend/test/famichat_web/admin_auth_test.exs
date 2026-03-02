defmodule FamichatWeb.AdminAuthTest do
  use FamichatWeb.ConnCase, async: true

  import Plug.Conn, only: [put_req_header: 3]

  defp with_credentials(conn, username, password) do
    put_req_header(
      conn,
      "authorization",
      Plug.BasicAuth.encode_basic_auth(username, password)
    )
  end

  describe "GET /admin/spike" do
    test "returns 401 without credentials", %{conn: conn} do
      conn = get(conn, "/admin/spike")
      assert conn.status == 401
    end

    test "returns 200 with correct credentials", %{conn: conn} do
      conn =
        conn
        |> with_credentials("test-admin", "test-secret")
        |> get("/admin/spike")

      assert conn.status == 200
    end

    test "returns 401 with wrong password", %{conn: conn} do
      conn =
        conn
        |> with_credentials("test-admin", "wrong")
        |> get("/admin/spike")

      assert conn.status == 401
    end
  end
end
