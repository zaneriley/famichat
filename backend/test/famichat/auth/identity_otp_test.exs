defmodule Famichat.Auth.Identity.OTPTest do
  use Famichat.DataCase, async: false

  alias Famichat.Auth.Identity
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.TelemetryHelpers

  describe "issue_otp/1 rate limiting" do
    test "enforces bucket limits" do
      email = ChatFixtures.unique_user_email()
      _user = ChatFixtures.user_fixture(%{email: email})

      assert {:ok, _, _} = Identity.issue_otp(email)
      assert {:ok, _, _} = Identity.issue_otp(email)
      assert {:ok, _, _} = Identity.issue_otp(email)

      assert {:error, {:rate_limited, retry_in}} = Identity.issue_otp(email)
      assert retry_in > 0
    end
  end

  describe "verify_otp/2" do
    test "accepts once and rejects replay without leaking telemetry secrets" do
      email = ChatFixtures.unique_user_email()
      user = ChatFixtures.user_fixture(%{email: email})

      {:ok, code, _record} = Identity.issue_otp(email)

      events =
        TelemetryHelpers.capture(
          [[:famichat, :auth, :identity, :otp_verified]],
          fn ->
            assert {:ok, verified_user} = Identity.verify_otp(email, code)
            assert verified_user.id == user.id
          end
        )

      assert [%{metadata: metadata}] = events
      assert metadata[:user_id] == user.id

      refute TelemetryHelpers.sensitive_key_present?(metadata),
             "telemetry metadata contains sensitive keys"

      assert {:error, :used} = Identity.verify_otp(email, code)

      replay_events =
        TelemetryHelpers.capture(
          [[:famichat, :auth, :identity, :otp_verified]],
          fn -> assert {:error, :used} = Identity.verify_otp(email, code) end
        )

      assert replay_events == []
    end
  end
end
