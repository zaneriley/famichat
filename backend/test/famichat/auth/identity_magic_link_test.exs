defmodule Famichat.Auth.Identity.MagicLinkTest do
  use Famichat.DataCase, async: false

  alias Famichat.Auth.Identity
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.TelemetryHelpers

  describe "redeem_magic_link/1" do
    test "succeeds once, rejects reuse, and emits sanitized telemetry" do
      email = ChatFixtures.unique_user_email()
      user = ChatFixtures.user_fixture(%{email: email})

      events =
        TelemetryHelpers.capture(
          [
            [:famichat, :auth, :identity, :magic_link_issued],
            [:famichat, :auth, :identity, :magic_link_redeemed]
          ],
          fn ->
            {:ok, token, _record} = Identity.issue_magic_link(email)

            assert {:ok, redeemed_user} = Identity.redeem_magic_link(token)
            assert redeemed_user.id == user.id

            assert {:error, :used} = Identity.redeem_magic_link(token)
          end
        )

      assert length(events) == 2

      Enum.each(events, fn %{event: event, metadata: metadata} ->
        assert metadata[:user_id] == user.id

        refute TelemetryHelpers.sensitive_key_present?(metadata),
               "telemetry metadata for #{inspect(event)} contains sensitive keys"
      end)
    end
  end
end
