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

  describe "issue_otp/1 code properties" do
    test "OTP codes are always exactly 6 digits" do
      email = ChatFixtures.unique_user_email()
      _user = ChatFixtures.user_fixture(%{email: email})

      {:ok, code, _record} = Identity.issue_otp(email)

      assert String.length(code) == 6,
             "expected a 6-digit OTP code, got #{inspect(code)}"

      assert String.match?(code, ~r/^\d{6}$/),
             "OTP code must be all digits, got #{inspect(code)}"
    end

    test "OTP code value is within valid 6-digit range (100_000..999_999)" do
      email = ChatFixtures.unique_user_email()
      _user = ChatFixtures.user_fixture(%{email: email})

      {:ok, code, _record} = Identity.issue_otp(email)
      value = String.to_integer(code)

      assert value >= 100_000 and value <= 999_999,
             "OTP code #{value} is outside valid range 100_000..999_999"
    end

    test "two OTP codes issued in rapid succession are distinct (CSPRNG check)" do
      # Uses two separate users so rate limiting does not interfere.
      email1 = ChatFixtures.unique_user_email()
      email2 = ChatFixtures.unique_user_email()
      _user1 = ChatFixtures.user_fixture(%{email: email1})
      _user2 = ChatFixtures.user_fixture(%{email: email2})

      {:ok, code1, _} = Identity.issue_otp(email1)
      {:ok, code2, _} = Identity.issue_otp(email2)

      refute code1 == code2,
             "two CSPRNG-generated codes should be distinct (collision probability ~1 in 900k)"
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

    test "rejects codes outside the valid 6-digit range" do
      email = ChatFixtures.unique_user_email()
      _user = ChatFixtures.user_fixture(%{email: email})

      # Codes that are too short, too long, or all zeros are never valid.
      for bad_code <- ["00000", "0000000", "000000", "abcdef"] do
        result = Identity.verify_otp(email, bad_code)

        assert match?({:error, _}, result),
               "expected rejection of code #{inspect(bad_code)}, got #{inspect(result)}"
      end
    end
  end
end
