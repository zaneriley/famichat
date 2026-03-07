defmodule FamichatWeb.SessionRefreshTest do
  use FamichatWeb.ConnCase, async: false

  alias Famichat.Accounts.FirstRun
  alias Famichat.Auth.Sessions
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.TelemetryHelpers
  alias FamichatWeb.ConnHelpers

  @event [:famichat, :plug, :session_refresh, :call]

  test "public browser routes do not emit session_refresh telemetry", %{
    conn: conn
  } do
    events =
      TelemetryHelpers.capture([@event], fn ->
        assert get(conn, "/").status == 302
        assert get(build_conn(), "/en/login").status in [200, 302]
        assert get(build_conn(), "/en/setup").status in [200, 302]

        assert get(build_conn(), "/en/invites/invalid-token").status in [
                 200,
                 302
               ]

        assert get(build_conn(), "/en/does-not-exist").status == 302
      end)

    assert events == []
  end

  test "setup route redirects once the instance is bootstrapped" do
    FirstRun.reset_cache()

    on_exit(fn ->
      FirstRun.reset_cache()
    end)

    family = ChatFixtures.family_fixture()

    user =
      ChatFixtures.user_fixture(%{
        household_id: family.id,
        role: :admin,
        username: "setup_redirect_test_user"
      })

    ChatFixtures.membership_fixture(user, family, :admin)

    assert get(build_conn(), "/en/setup").status == 302
  end

  test "authenticated home route emits session_refresh telemetry and cache hits on repeat" do
    session = issued_session()

    first_events =
      TelemetryHelpers.capture([@event], fn ->
        assert get(session_conn(session), "/en").status == 200
      end)

    second_events =
      TelemetryHelpers.capture([@event], fn ->
        assert get(session_conn(session), "/en").status == 200
      end)

    assert [%{metadata: first_metadata}] = first_events

    assert [
             %{
               measurements: %{duration_ms: duration_ms},
               metadata: second_metadata
             }
           ] = second_events

    assert first_metadata[:result] == :verified
    assert first_metadata[:cache_status] == :miss
    assert second_metadata[:result] == :verified
    assert second_metadata[:cache_status] == :hit
    assert duration_ms < 50
  end

  defp issued_session do
    family = ChatFixtures.family_fixture()

    user =
      ChatFixtures.user_fixture(%{
        household_id: family.id,
        role: :member,
        username: "session_refresh_test_user"
      })

    ChatFixtures.membership_fixture(user, family, :member)

    {:ok, session} =
      Sessions.start_session(
        user,
        %{id: Ecto.UUID.generate(), user_agent: "test-agent", ip: "127.0.0.1"},
        remember_device?: true
      )

    session
  end

  defp session_conn(session) do
    build_conn()
    |> Plug.Test.init_test_session(%{})
    |> ConnHelpers.put_session_from_issued(session)
  end
end
