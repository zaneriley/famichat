defmodule Famichat.Auth.Identity.OTPBruteforceTest do
  use Famichat.DataCase, async: false

  alias Famichat.Auth.Identity
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.{RedactionHelpers, TelemetryHelpers}

  describe "verify_otp/2 adversarial paths" do
    test "wrong code is rejected and telemetry remains redacted" do
      email = ChatFixtures.unique_user_email()
      _user = ChatFixtures.user_fixture(%{email: email})

      {:ok, code, _record} = Identity.issue_otp(email)
      wrong_code = mutate_code(code)

      events =
        TelemetryHelpers.capture(
          [[:famichat, :auth, :identity, :otp_verified]],
          fn ->
            assert {:error, :invalid} = Identity.verify_otp(email, wrong_code)
          end
        )

      Enum.each(events, fn %{metadata: metadata} ->
        RedactionHelpers.pii_free!(metadata)
      end)
    end

    @tag :pending
    test "verify_otp enforces rate limit on repeated attempts" do
      # TODO: add once Identity.verify_otp/2 applies rate limiting.
    end
  end

  defp mutate_code(code) do
    case code do
      "000000" -> "999999"
      _ -> "000000"
    end
  end
end
