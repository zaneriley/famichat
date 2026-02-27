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
      assert render(view) =~ "History is loaded from storage on page load"
      assert has_element?(view, "#message-input:not([disabled])")
      refute has_element?(view, "[data-role='switch-self']")
    end
  end
end
