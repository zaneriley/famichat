defmodule Famichat.Auth.Recovery.RedeemTest do
  use Famichat.DataCase, async: false

  alias Famichat.Auth.Recovery
  alias Famichat.Auth.Sessions
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.{RedactionHelpers, TelemetryHelpers}
  alias Famichat.Accounts.UserDevice
  alias Famichat.Repo

  @redeem_event [:famichat, :auth, :recovery, :redeem]

  test "redeeming recovery revokes active devices and is idempotent" do
    family = ChatFixtures.family_fixture()
    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    device_info = %{
      id: "device-#{System.unique_integer([:positive])}",
      user_agent: "RecoveryRedeemTest",
      ip: "127.0.0.1"
    }

    {:ok, session} =
      Sessions.start_session(member, device_info, remember_device?: true)

    {:ok, recovery_token, _record} =
      Recovery.issue_recovery(admin.id, member.id)

    events =
      TelemetryHelpers.capture([@redeem_event], fn ->
        assert {:ok, redeemed_user} = Recovery.redeem_recovery(recovery_token)
        assert redeemed_user.id == member.id
      end)

    assert [%{metadata: metadata}] = events
    assert metadata[:user_id] == member.id
    RedactionHelpers.pii_free!(metadata)

    device =
      Repo.get_by!(UserDevice,
        user_id: member.id,
        device_id: session.device_id
      )

    refute is_nil(device.revoked_at)

    assert {:error, :revoked} =
             Sessions.refresh_session(session.device_id, session.refresh_token)

    second_attempt_events =
      TelemetryHelpers.capture([@redeem_event], fn ->
        assert {:error, :used} = Recovery.redeem_recovery(recovery_token)
      end)

    assert second_attempt_events == []
  end
end
