defmodule FamichatWeb.AuthLive.FamilySetupLiveTest do
  @moduledoc """
  Tests for FamilySetupLive, including reconnect recovery after token
  consumption and the direct-passkey hook wiring used by the second-family
  setup flow.
  """

  use FamichatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Famichat.Auth.Onboarding

  setup do
    Famichat.Accounts.FirstRun.reset_cache()
    on_exit(fn -> Famichat.Accounts.FirstRun.reset_cache() end)
    :ok
  end

  describe "reconnect recovery (consumed-token mount)" do
    @tag known_failure: "B6: setup flow passkey recovery changed (2026-03-21)"
    test "mounting with a consumed token shows passkey recovery state" do
      {:ok, %{setup_token: raw_token}} =
        Onboarding.create_family_self_service("Reconnect Test Family", %{
          remote_ip: "127.0.0.1"
        })

      {:ok, %{user: _user, passkey_register_token: _}} =
        Onboarding.complete_family_setup(raw_token, %{
          "username" => "reconnect_user"
        })

      {:ok, view, _html} =
        live(session_conn(), "/en/families/start/#{raw_token}")

      rendered = render(view)

      assert rendered =~ "Secure your account, reconnect_user."

      assert has_element?(
               view,
               "#passkey-register-btn[phx-hook='PasskeyAdminSetup']"
             )

      refute rendered =~ "already been used"
      refute rendered =~ "not valid"
      refute rendered =~ "expired"
      refute rendered =~ "not available"
    end
  end

  describe "happy path" do
    @tag known_failure: "B6: setup flow username submission changed (2026-03-21)"
    test "submitting username advances to direct passkey setup" do
      {:ok, %{setup_token: raw_token}} =
        Onboarding.create_family_self_service("Happy Path Family", %{
          remote_ip: "127.0.0.1"
        })

      {:ok, view, _html} =
        live(session_conn(), "/en/families/start/#{raw_token}")

      html =
        view
        |> form("form[phx-submit='submit-username']", %{
          "username" => "Family Admin"
        })
        |> render_submit()

      assert html =~ "Secure your account, Family Admin."

      assert has_element?(
               view,
               "#passkey-register-btn[phx-hook='PasskeyAdminSetup']"
             )
    end
  end
end
