defmodule FamichatWeb.HomeLiveTest do
  use FamichatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "home chat harness" do
    test "defaults to shared family conversation for cross-user QA", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/en?user=alice")

      assert has_element?(
               view,
               "#kitchen-table-chat[data-conversation-type='family']"
             )

      assert render(view) =~ "Actor:"
      assert render(view) =~ "alice"
      assert render(view) =~ "/admin/spike"
      assert render(view) =~ "Device:"
      assert has_element?(view, "#message-input:not([disabled])")
    end

    test "uses deterministic device id from query for shareable actor links", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/en?user=alice&device=device-2")

      assert render(view) =~ "spike-alice-device-2"
    end
  end
end
