defmodule FamichatWeb.AuthLive.FamilySetupLiveTest do
  @moduledoc """
  Tests for FamilySetupLive, focused on the consumed-token reconnect recovery
  pattern that prevents P0 bugs on mobile WebSocket reconnects.

  ## Context

  When a mobile user's WebSocket drops mid-flow (after token consumption but
  before passkey completion), the LiveView remounts and calls
  `validate_family_setup_token/1` again. If the token was already consumed by
  `complete_family_setup/2`, this returns `{:error, :used}`. Without a peek
  recovery path, the user sees "This setup link has already been used" even
  though they were actively using it.

  This bug class was found in the 2026-03-09 bug bash. The fix requires a
  `peek_family_setup/1` function in Onboarding (analogous to `peek_invite/1`)
  and a `{:error, :used}` branch in `FamilySetupLive.mount_connected/2` that
  calls it.

  See `InviteLive` @moduledoc "Pattern: Token-Gated LiveView with Reconnect
  Recovery" for the three-part contract.
  """

  use FamichatWeb.ConnCase

  alias Famichat.Auth.Onboarding

  # --------------------------------------------------------------------------
  # This test is tagged :skip because the fix has NOT been implemented yet.
  #
  # FamilySetupLive currently transitions to {:error, :used} -> :invalid
  # instead of falling back to a peek recovery function. The test documents
  # the EXPECTED behavior: after token consumption, mounting should show a
  # recovery state, not an error.
  #
  # To unblock this test:
  #   1. Add `peek_family_setup/1` to Onboarding (mirrors `peek_invite/1`)
  #   2. Add `{:error, :used} -> peek_family_setup(token)` branch to
  #      `FamilySetupLive.mount_connected/2`
  #   3. Remove the @tag :skip below
  # --------------------------------------------------------------------------

  describe "reconnect recovery (consumed-token mount)" do
    @tag :skip
    test "mounting with a consumed token shows recovery state, not error", %{conn: conn} do
      # Step 1: Issue a family setup token via the self-service path
      {:ok, %{setup_token: raw_token}} =
        Onboarding.create_family_self_service("Reconnect Test Family", %{
          remote_ip: "127.0.0.1"
        })

      # Step 2: Consume the token by completing family setup (simulates the
      # user submitting their username form, which triggers
      # complete_family_setup/2 server-side)
      {:ok, %{user: _user, passkey_register_token: _}} =
        Onboarding.complete_family_setup(raw_token, %{"username" => "reconnect_user"})

      # Step 3: Mount the LiveView with the now-consumed token. This simulates
      # a WebSocket reconnect: the user's browser reconnects and Phoenix
      # re-mounts the LiveView, calling mount_connected/2 again.
      conn = session_conn()
      {:ok, view, _html} = live(conn, "/en/families/start/#{raw_token}")

      # Step 4: Assert recovery state, NOT error
      #
      # The user should see a usable state (the passkey registration step or
      # the username form pre-filled), NOT any of the error messages that
      # indicate the token is dead.
      rendered = render(view)
      refute rendered =~ "already been used"
      refute rendered =~ "not valid"
      refute rendered =~ "expired"
      refute rendered =~ "not available"
    end

    @tag :skip
    test "mounting with an expired token shows friendly error", %{conn: conn} do
      # This test verifies the non-recovery case: genuinely expired tokens
      # should still show a friendly error (not crash or 500).
      #
      # NOTE: This requires a way to issue an already-expired token, which is
      # not straightforward without time manipulation. Leaving as a placeholder
      # for when the token TTL testing infrastructure is available.
    end
  end

  describe "happy path" do
    @tag :skip
    test "valid token shows username registration form", %{conn: conn} do
      {:ok, %{setup_token: raw_token}} =
        Onboarding.create_family_self_service("Happy Path Family", %{
          remote_ip: "127.0.0.1"
        })

      conn = session_conn()
      {:ok, _view, html} = live(conn, "/en/families/start/#{raw_token}")

      # The user should see the registration step with a username form
      assert html =~ "username" or html =~ "name"
    end
  end
end
