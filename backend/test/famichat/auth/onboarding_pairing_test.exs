defmodule Famichat.Auth.Onboarding.PairingTest do
  use Famichat.DataCase, async: false

  alias Famichat.Auth.Onboarding
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.TelemetryHelpers

  @tokens_event [:famichat, :auth, :tokens, :issued]

  test "pairing tokens redeem once and reject reuse" do
    family = ChatFixtures.family_fixture()
    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    invitee_email = ChatFixtures.unique_user_email()
    result_ref = make_ref()

    events =
      TelemetryHelpers.capture([@tokens_event], fn ->
        result =
          Onboarding.issue_invite(admin.id, invitee_email, %{
            household_id: family.id,
            role: :member
          })

        send(self(), {result_ref, result})
      end)

    assert_receive {^result_ref,
                    {:ok,
                     %{
                       invite: invite_token,
                       qr: qr_token,
                       admin_code: admin_code
                     }}}

    Enum.each(events, fn %{metadata: metadata} ->
      refute TelemetryHelpers.sensitive_key_present?(metadata)
    end)

    {:ok, %{invite_token: ^invite_token, payload: payload}} =
      Onboarding.redeem_pairing(qr_token)

    assert payload["household_id"] == family.id

    assert {:error, :used} = Onboarding.redeem_pairing(qr_token)

    # Reissue admin code path requires admin; non-admin is rejected.
    member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    assert {:error, :forbidden} =
             Onboarding.reissue_pairing(member.id, invite_token)

    assert {:ok, %{qr: new_qr, admin_code: new_admin_code}} =
             Onboarding.reissue_pairing(admin.id, invite_token)

    refute new_qr == qr_token
    refute new_admin_code == admin_code
  end
end
