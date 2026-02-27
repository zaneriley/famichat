defmodule FamichatWeb.AdminMessageRoutesTest do
  use FamichatWeb.ConnCase, async: true

  describe "admin message tester routes" do
    test "serves canonical /admin/message and compatibility alias", %{
      conn: conn
    } do
      spike = get(conn, "/admin/spike")
      assert html_response(spike, 200) =~ "Design Spike Launcher"

      canonical = get(conn, "/admin/message")
      assert html_response(canonical, 200) =~ "message-test"

      alias_route = get(recycle(canonical), "/admin/message-test")
      assert html_response(alias_route, 200) =~ "message-test"
    end
  end
end
