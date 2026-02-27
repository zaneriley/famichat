defmodule FamichatWeb.HomeLiveTest do
  use FamichatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    previous = Application.get_env(:famichat, :mls_enforcement, false)

    on_exit(fn ->
      Application.put_env(:famichat, :mls_enforcement, previous)
    end)

    :ok
  end

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

    test "uses message_id for deterministic stream identity", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/en?user=alice")

      payload = %{
        "message_id" => "msg-123",
        "body" => "hello from other device",
        "timestamp" => "2026-02-27T00:00:00Z",
        "user_id" => "other-user"
      }

      _ = render_hook(view, "message_received", payload)

      assert has_element?(view, "#messages-msg-msg-123")
      assert render(view) =~ "hello from other device"
    end

    test "does not render raw MLS wire payload in spike UI", %{conn: conn} do
      Application.put_env(:famichat, :mls_enforcement, true)
      {:ok, view, _html} = live(conn, "/en?user=alice")

      raw_hex_payload = String.duplicate("ab", 70)

      payload = %{
        "message_id" => "missing-message-id",
        "body" => raw_hex_payload,
        "timestamp" => "2026-02-27T00:00:00Z",
        "user_id" => "other-user"
      }

      _ = render_hook(view, "message_received", payload)

      refute render(view) =~ raw_hex_payload
      assert render(view) =~ "[Encrypted MLS payload]"
    end

    test "drops channel payloads without message_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/en?user=alice")

      payload = %{
        "body" => "missing-id-body",
        "timestamp" => "2026-02-27T00:00:00Z",
        "user_id" => "other-user"
      }

      _ = render_hook(view, "message_received", payload)

      refute render(view) =~ "missing-id-body"
      assert render(view) =~ "Dropped message missing message_id."
    end
  end
end
