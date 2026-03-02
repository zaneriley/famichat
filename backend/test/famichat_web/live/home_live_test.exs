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
    test "renders auth error when no token is provided", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/en")

      assert has_element?(
               view,
               "#kitchen-table-chat[data-conversation-type='family']"
             )

      assert render(view) =~ "Authentication failed"
      assert render(view) =~ "/admin/spike"
      assert render(view) =~ "Device:"
    end

    test "renders auth error when an invalid token is provided", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/en?token=invalid-token")

      assert render(view) =~ "Authentication failed"
    end

    test "uses message_id for deterministic stream identity", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/en")

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
      {:ok, view, _html} = live(conn, "/en")

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
      {:ok, view, _html} = live(conn, "/en")

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
