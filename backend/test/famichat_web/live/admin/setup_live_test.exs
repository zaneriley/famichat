defmodule FamichatWeb.AdminLive.SetupLiveTest do
  @moduledoc """
  Tests for SetupLive, the first-run admin bootstrap flow.

  These tests exercise the reconnect-redirect bug (Hypothesis A) introduced
  in the `:issue_invite` step: after passkey registration completes, any
  WebSocket reconnect previously redirected the admin to /login because
  `fetch_incomplete_bootstrap/0` returns `{:error, :not_found}` once a passkey
  exists. The fix adds `fetch_admin_awaiting_first_invite/0` to detect and
  resume the `:issue_invite` step instead.
  """

  use FamichatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Famichat.Accounts.FirstRun
  alias Famichat.Accounts.Passkey
  alias Famichat.Auth.Onboarding
  alias Famichat.Repo

  setup do
    FirstRun.reset_cache()

    on_exit(fn ->
      FirstRun.reset_cache()
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Helper: build admin state with a registered passkey (bypasses WebAuthn)
  # ---------------------------------------------------------------------------

  defp bootstrap_admin_with_passkey(username) do
    {:ok, %{user: user, family: family}} =
      Onboarding.bootstrap_admin(username, %{
        "family_name" => "Setup Test Family"
      })

    # Insert a passkey record directly to simulate a completed WebAuthn ceremony,
    # without going through the real Wax registration flow.
    # Synthetic passkey — Passkeys.has_active_passkey?/1 only checks disabled_at IS NULL,
    # not key format, so random bytes satisfy the DB constraint without a real COSE key.
    credential_id = :crypto.strong_rand_bytes(32)
    public_key = :crypto.strong_rand_bytes(77)

    {:ok, _passkey} =
      %Passkey{}
      |> Passkey.changeset(%{
        user_id: user.id,
        credential_id: credential_id,
        public_key: public_key,
        sign_count: 0
      })
      |> Repo.insert()

    %{user: user, family: family}
  end

  # ---------------------------------------------------------------------------
  # Hypothesis A regression: reconnect redirect to /login
  # ---------------------------------------------------------------------------

  describe "mount after passkey registration (issue_invite step)" do
    test "initial LiveView mount resumes :issue_invite when admin has passkey but no invite yet",
         %{} do
      bootstrap_admin_with_passkey("reconnect_admin")

      # Opening /setup in a fresh browser session after passkey registration
      # simulates what happens on a WebSocket reconnect: connected?(socket) == true
      # causes mount_connected/1 to run. Before the fix, this redirected to /login.
      {:ok, view, html} = live(session_conn(), "/en/setup")

      # The `:issue_invite` step renders the "Generate invite link" button.
      assert html =~ "Generate invite link"
      assert has_element?(view, "button[phx-click='generate_invite']")

      # Must not show "sign in" or redirect to login — that was the P0 symptom.
      refute html =~ "already set up"
      refute html =~ "Sign in with passkey"
    end

    test "button is not missing after passkey completes", %{} do
      bootstrap_admin_with_passkey("button_present_admin")

      {:ok, view, _html} = live(session_conn(), "/en/setup")

      # The generate_invite button must be present and clickable.
      assert has_element?(view, "button[phx-click='generate_invite']")
      refute has_element?(view, "a[href='/en/login']")
    end

    test "second fresh-connection mount also resumes :issue_invite (simulates reconnect)",
         %{} do
      bootstrap_admin_with_passkey("reconnect_second_conn_admin")

      # First connection — establishes DB state (passkey exists, no invite).
      {:ok, _view1, _html1} = live(session_conn(), "/en/setup")

      # Second connection with a completely fresh conn — this is the closest
      # simulation of a WebSocket reconnect that Phoenix LiveView test helpers
      # support. A real reconnect drops the WebSocket and re-runs mount/3 with
      # connected?(socket) == true on a new process, which is exactly what
      # live(session_conn(), ...) does each call.
      {:ok, view2, html2} = live(session_conn(), "/en/setup")

      assert html2 =~ "Generate invite link"
      assert has_element?(view2, "button[phx-click='generate_invite']")
    end
  end

  # ---------------------------------------------------------------------------
  # Round-trip: issue_invite step → generate_invite → show_invite
  # ---------------------------------------------------------------------------

  describe "generate_invite round-trip after passkey registration" do
    test "clicking generate_invite advances to :show_invite with an invite URL",
         %{} do
      bootstrap_admin_with_passkey("roundtrip_admin")

      # Mount in :issue_invite state (passkey exists, no invite yet).
      {:ok, view, html} = live(session_conn(), "/en/setup")

      assert html =~ "Generate invite link"

      # Push the generate_invite event — this calls Onboarding.issue_invite/3.
      result_html = render_click(view, "generate_invite")

      # After the event the step advances to :show_invite.
      assert result_html =~ "/invites/"
    end
  end

  # ---------------------------------------------------------------------------
  # fetch_admin_awaiting_first_invite/0 unit-level tests via mount
  # ---------------------------------------------------------------------------

  describe "fetch_admin_awaiting_first_invite/0" do
    test "returns :not_found when no users exist" do
      assert {:error, :not_found} =
               Onboarding.fetch_admin_awaiting_first_invite()
    end

    test "returns :not_found when user exists but has no passkey" do
      Onboarding.bootstrap_admin("no_passkey_admin", %{
        "family_name" => "No Passkey Family"
      })

      assert {:error, :not_found} =
               Onboarding.fetch_admin_awaiting_first_invite()
    end

    test "returns {:ok, user, family} when community_admin has passkey and membership" do
      %{user: user, family: family} =
        bootstrap_admin_with_passkey("awaiting_invite_admin")

      assert {:ok, returned_user, returned_family} =
               Onboarding.fetch_admin_awaiting_first_invite()

      assert returned_user.id == user.id
      assert returned_family.id == family.id
    end

    test "returns :not_found when multiple users exist (not first-run state)" do
      %{user: _admin} = bootstrap_admin_with_passkey("multi_user_admin")

      # Simulate a second user existing (e.g., invite was accepted)
      Famichat.ChatFixtures.user_fixture(%{username: "second_user"})

      assert {:error, :not_found} =
               Onboarding.fetch_admin_awaiting_first_invite()
    end
  end

  # ---------------------------------------------------------------------------
  # Static render path: must not redirect to /login mid-setup
  # ---------------------------------------------------------------------------

  describe "static render (disconnected mount)" do
    test "shows :check spinner when admin has passkey but no invite — does not redirect",
         %{conn: base_conn} do
      bootstrap_admin_with_passkey("static_render_admin")

      # Static (disconnected) render should NOT redirect to /login because
      # incomplete_bootstrap_available? now covers the :issue_invite state.
      # It should show :check (the spinner) instead.
      resp = get(base_conn, "/en/setup")

      # Must not be a redirect to /login
      refute resp.status == 302 and
               String.contains?(
                 Phoenix.ConnTest.redirected_to(resp),
                 "login"
               )
    end
  end

  # ---------------------------------------------------------------------------
  # Existing :bootstrap step — no regression
  # ---------------------------------------------------------------------------

  describe "fresh first-run (no users)" do
    test "shows :bootstrap form when no users exist", %{} do
      {:ok, _view, html} = live(session_conn(), "/en/setup")

      assert html =~ "Welcome to your family space"
    end
  end
end
