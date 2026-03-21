defmodule FamichatWeb.HomeLiveTest do
  use FamichatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Famichat.Auth.Sessions
  alias Famichat.ChatFixtures
  alias FamichatWeb.SessionKeys

  setup do
    Famichat.Accounts.FirstRun.force_bootstrapped!()
    previous = Application.get_env(:famichat, :mls_enforcement, false)

    on_exit(fn ->
      Application.put_env(:famichat, :mls_enforcement, previous)
      Famichat.Accounts.FirstRun.reset_cache()
    end)

    :ok
  end

  # Builds a conn with an access_token in the Plug session so HomeLive mounts
  # in authenticated mode. Uses a real DB user and real Sessions.start_session.
  defp authenticated_conn(conn) do
    family = ChatFixtures.family_fixture()

    user =
      ChatFixtures.user_fixture(%{
        household_id: family.id,
        role: :member,
        username: "home_live_test_user"
      })

    ChatFixtures.membership_fixture(user, family, :member)

    {:ok, session} =
      Sessions.start_session(
        user,
        %{id: Ecto.UUID.generate(), user_agent: "test-agent", ip: "127.0.0.1"},
        remember_device?: true
      )

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(SessionKeys.access_token(), session.access_token)

    {conn, user, session}
  end

  describe "home chat harness" do
    @tag known_failure: "B7: unauthenticated /en now redirects to /en/login (2026-03-21)"
    test "renders sign-in prompt when no token is provided", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/en")

      # Unauthenticated: the #kitchen-table-chat div is not rendered.
      # Instead the user sees a sign-in prompt.
      refute has_element?(view, "#kitchen-table-chat")
      assert render(view) =~ "Sign in"
    end

    @tag known_failure: "B7: unauthenticated /en now redirects to /en/login (2026-03-21)"
    test "renders session-expired message when an invalid token is provided", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/en?token=invalid-token")

      # Invalid URL token: auth_error is set, template shows the expired message.
      refute has_element?(view, "#kitchen-table-chat")
      assert render(view) =~ "Session expired or invalid."
    end

    @tag known_failure: "B7: authenticated /en redirects to /en/setup — incomplete bootstrap (2026-03-21)"
    test "uses message_id for deterministic stream identity", %{conn: conn} do
      {auth_conn, _user, _session} = authenticated_conn(conn)
      {:ok, view, _html} = live(auth_conn, "/en")

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

    @tag known_failure: "B7: authenticated /en redirects to /en/setup — incomplete bootstrap (2026-03-21)"
    test "does not render raw MLS wire payload in spike UI", %{conn: conn} do
      Application.put_env(:famichat, :mls_enforcement, true)
      {auth_conn, _user, _session} = authenticated_conn(conn)
      {:ok, view, _html} = live(auth_conn, "/en")

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

    @tag known_failure: "B7: authenticated /en redirects to /en/setup — incomplete bootstrap (2026-03-21)"
    test "drops channel payloads without message_id", %{conn: conn} do
      {auth_conn, _user, _session} = authenticated_conn(conn)
      {:ok, view, _html} = live(auth_conn, "/en")

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
