defmodule FamichatWeb.FrontDoorLiveTest do
  use FamichatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Famichat.Accounts.FirstRun
  alias Famichat.Auth.{Onboarding, Sessions}
  alias Famichat.ChatFixtures
  alias FamichatWeb.SessionKeys

  setup do
    FirstRun.reset_cache()

    on_exit(fn ->
      FirstRun.reset_cache()
    end)

    :ok
  end

  describe "login front door" do
    test "renders the passkey sign-in button for unauthenticated users", %{
      conn: conn
    } do
      family = ChatFixtures.family_fixture()

      _user =
        ChatFixtures.user_fixture(%{
          family_id: family.id,
          role: :admin,
          username: "login_page_bootstrapped_user"
        })

      other_family = ChatFixtures.family_fixture()

      _other_user =
        ChatFixtures.user_fixture(%{
          family_id: other_family.id,
          role: :member,
          username: "login_page_other_user"
        })

      {:ok, view, _html} = live(conn, "/en/login")

      assert has_element?(view, "#passkey-login-btn")
      assert render(view) =~ "Sign in with passkey"
    end

    test "redirects authenticated users away from /login", %{conn: conn} do
      family = ChatFixtures.family_fixture()

      user =
        ChatFixtures.user_fixture(%{
          family_id: family.id,
          role: :member,
          username: "front_door_login_user"
        })

      other_family = ChatFixtures.family_fixture()

      _other_user =
        ChatFixtures.user_fixture(%{
          family_id: other_family.id,
          role: :member,
          username: "front_door_login_other_user"
        })

      conn = authenticated_conn(conn, user)

      assert {:error, {redirect_kind, %{to: to}}} = live(conn, "/en/login")
      assert redirect_kind in [:redirect, :live_redirect]
      assert to in ["/en", "/en/"]
    end
  end

  describe "setup front door" do
    test "renders the bootstrap form on an empty instance", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/en/setup")

      assert has_element?(view, "form[phx-submit='submit-bootstrap']")
      assert has_element?(view, "#username")
      assert render(view) =~ "Welcome to your family space."
    end

    test "submitting bootstrap advances to passkey registration", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/en/setup")

      html =
        view
        |> form("form[phx-submit='submit-bootstrap']", %{
          "username" => "Bootstrap Admin",
          "family_name" => "The Bootstraps"
        })
        |> render_submit()

      assert html =~ "Secure your account with a passkey."
      assert has_element?(view, "#passkey-admin-setup-btn")
    end

    test "recovers an incomplete bootstrap and resumes at passkey registration",
         %{conn: conn} do
      assert {:ok, %{user: _user, family: _family, passkey_register_token: _}} =
               Onboarding.bootstrap_admin("bootstrap_resume_user", %{
                 "family_name" => "Bootstrap Resume Family"
               })

      {:ok, view, _html} = live(conn, "/en/setup")

      assert has_element?(view, "#passkey-admin-setup-btn")
      assert render(view) =~ "Secure your account with a passkey."
      refute render(view) =~ "This family space is already set up."
    end
  end

  describe "invite front door" do
    test "valid invite renders the username form", %{conn: conn} do
      family = ChatFixtures.family_fixture()

      admin =
        ChatFixtures.user_fixture(%{
          family_id: family.id,
          role: :admin,
          username: "invite_happy_admin"
        })

      other_family = ChatFixtures.family_fixture()

      _other_user =
        ChatFixtures.user_fixture(%{
          family_id: other_family.id,
          role: :member,
          username: "invite_happy_other_user"
        })

      {:ok, %{invite: invite_token}} =
        Onboarding.issue_invite(admin.id, ChatFixtures.unique_user_email(), %{
          household_id: family.id,
          role: :member
        })

      {:ok, view, _html} = live(conn, "/en/invites/#{invite_token}")

      assert has_element?(view, "#username")
      assert render(view) =~ "invite_happy_admin invited you"
      assert render(view) =~ "Continue — set up your passkey next"
    end

    test "username validation errors keep invite users on the accept step", %{
      conn: conn
    } do
      family = ChatFixtures.family_fixture()

      admin =
        ChatFixtures.user_fixture(%{
          family_id: family.id,
          role: :admin,
          username: "invite_validation_admin"
        })

      other_family = ChatFixtures.family_fixture()

      _other_user =
        ChatFixtures.user_fixture(%{
          family_id: other_family.id,
          role: :member,
          username: "invite_validation_other_user"
        })

      {:ok, %{invite: invite_token}} =
        Onboarding.issue_invite(admin.id, ChatFixtures.unique_user_email(), %{
          household_id: family.id,
          role: :member
        })

      {:ok, view, _html} = live(conn, "/en/invites/#{invite_token}")

      html =
        view
        |> form("form[phx-submit='submit-username']", %{"username" => "A"})
        |> render_submit()

      assert html =~ "Username must be at least 2 characters."
      assert has_element?(view, "#username")
      refute has_element?(view, "#passkey-register-btn")
    end

    test "completed invite reuse points the user to sign in", %{conn: conn} do
      family = ChatFixtures.family_fixture()

      admin =
        ChatFixtures.user_fixture(%{
          family_id: family.id,
          role: :admin,
          username: "invite_reuse_admin"
        })

      {:ok, %{invite: invite_token}} =
        Onboarding.issue_invite(admin.id, nil, %{
          household_id: family.id,
          role: :member
        })

      {:ok, %{registration_token: registration_token}} =
        Onboarding.accept_invite(invite_token)

      assert {:ok, %{user: user, passkey_register_token: _token}} =
               Onboarding.complete_registration(registration_token, %{
                 "username" => "invite_reuse_member"
               })

      user
      |> Ecto.Changeset.change(
        status: :active,
        confirmed_at: DateTime.utc_now()
      )
      |> Famichat.Repo.update!()

      {:ok, view, _html} = live(conn, "/en/invites/#{invite_token}")

      assert has_element?(view, "a[href='/en/login']")
      assert render(view) =~ "Sign in"
      refute has_element?(view, "#passkey-register-btn")
    end
  end

  defp authenticated_conn(conn, user) do
    {:ok, session} =
      Sessions.start_session(
        user,
        %{id: Ecto.UUID.generate(), user_agent: "test-agent", ip: "127.0.0.1"},
        remember_device?: true
      )

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(SessionKeys.access_token(), session.access_token)
  end
end
