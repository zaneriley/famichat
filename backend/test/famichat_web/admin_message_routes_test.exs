defmodule FamichatWeb.AdminMessageRoutesTest do
  use FamichatWeb.ConnCase, async: true

  import Plug.Conn, only: [put_req_header: 3]

  defp with_admin_auth(conn) do
    put_req_header(
      conn,
      "authorization",
      Plug.BasicAuth.encode_basic_auth("test-admin", "test-secret")
    )
  end

  describe "admin message tester routes" do
    test "serves canonical /admin/message and compatibility alias", %{
      conn: conn
    } do
      spike = conn |> with_admin_auth() |> get("/admin/spike")
      assert html_response(spike, 200) =~ "Design Spike Launcher"

      canonical = conn |> with_admin_auth() |> get("/admin/message")
      assert html_response(canonical, 200) =~ "message-test"

      alias_route =
        canonical
        |> recycle()
        |> with_admin_auth()
        |> get("/admin/message-test")

      assert html_response(alias_route, 200) =~ "message-test"
    end
  end
end
