defmodule FamichatWeb.SessionRefreshTest do
  use FamichatWeb.ConnCase, async: false

  alias Famichat.Accounts.FirstRun
  alias Famichat.Auth.{Onboarding, Sessions}
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.TelemetryHelpers
  alias FamichatWeb.ConnHelpers

  @event [:famichat, :plug, :session_refresh, :call]

  test "public browser routes do not emit session_refresh telemetry", %{
    conn: conn
  } do
    events =
      TelemetryHelpers.capture([@event], fn ->
        root_conn = get(conn, "/")
        assert root_conn.status == 302
        assert redirected_to(root_conn, 302) == "/en/"

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

  test "setup route redirects once incomplete-bootstrap recovery no longer applies" do
    FirstRun.reset_cache()

    on_exit(fn ->
      FirstRun.reset_cache()
    end)

    family = ChatFixtures.family_fixture()

    user =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        role: :admin,
        username: "setup_redirect_test_user"
      })

    ChatFixtures.membership_fixture(user, family, :admin)

    other_family = ChatFixtures.family_fixture()

    other_user =
      ChatFixtures.user_fixture(%{
        family_id: other_family.id,
        role: :member,
        username: "setup_redirect_other_user"
      })

    ChatFixtures.membership_fixture(other_user, other_family, :member)

    setup_conn = get(build_conn(), "/en/setup")
    assert setup_conn.status == 302
    assert redirected_to(setup_conn, 302) == "/en/login"
  end

  test "incomplete bootstrap redirects public entry points back to /setup" do
    FirstRun.reset_cache()

    on_exit(fn ->
      FirstRun.reset_cache()
    end)

    assert {:ok, %{user: _user, family: _family, passkey_register_token: _}} =
             Onboarding.bootstrap_admin("setup_resume_public_route_user", %{
               "family_name" => "Setup Resume Family"
             })

    root_conn = get(build_conn(), "/en")
    assert redirected_to(root_conn, 302) == "/en/setup"

    login_conn = get(build_conn(), "/en/login")
    assert redirected_to(login_conn, 302) == "/en/setup"

    assert get(build_conn(), "/en/setup").status == 200
  end

  test "malformed invite tokens return a standalone 404 page" do
    family = ChatFixtures.family_fixture()

    _user =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        role: :admin,
        username: "malformed_invite_bootstrapped_user"
      })

    other_family = ChatFixtures.family_fixture()

    _other_user =
      ChatFixtures.user_fixture(%{
        family_id: other_family.id,
        role: :member,
        username: "malformed_invite_other_user"
      })

    invalid_format_conn = get(build_conn(), "/en/invites/not.valid")
    invalid_length_conn = get(build_conn(), "/en/invites/#{String.duplicate("a", 257)}")

    assert invalid_format_conn.status == 404
    assert invalid_length_conn.status == 404

    invalid_format_body = html_response(invalid_format_conn, 404)

    assert count_occurrences(invalid_format_body, "<html") == 1
    assert count_occurrences(invalid_format_body, "js/app.js") == 1
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
        family_id: family.id,
        role: :member,
        username: "session_refresh_test_user"
      })

    ChatFixtures.membership_fixture(user, family, :member)

    other_family = ChatFixtures.family_fixture()

    other_user =
      ChatFixtures.user_fixture(%{
        family_id: other_family.id,
        role: :member,
        username: "session_refresh_other_user"
      })

    ChatFixtures.membership_fixture(other_user, other_family, :member)

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

  defp count_occurrences(body, fragment) do
    body
    |> String.split(fragment)
    |> length()
    |> Kernel.-(1)
  end
end
