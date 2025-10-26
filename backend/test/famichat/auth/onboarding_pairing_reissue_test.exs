defmodule Famichat.Auth.Onboarding.PairingReissueTest do
  use Famichat.DataCase, async: false

  alias Famichat.Auth.Onboarding
  alias Famichat.Auth.Tokens
  alias Famichat.Auth.Tokens.Policy
  alias Famichat.ChatFixtures

  test "reissue requires admin and does not resurrect consumed tokens" do
    family = ChatFixtures.family_fixture()
    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})
    invitee_email = ChatFixtures.unique_user_email()

    {:ok, %{invite: invite_token, qr: qr_token, admin_code: admin_code}} =
      Onboarding.issue_invite(admin.id, invitee_email, %{
        household_id: family.id,
        role: :member
      })

    assert {:error, :forbidden} =
             Onboarding.reissue_pairing(member.id, invite_token)

    {:ok, %{invite_token: ^invite_token}} = Onboarding.redeem_pairing(qr_token)
    assert {:error, :used} = Onboarding.redeem_pairing(qr_token)

    {:ok, %{qr: new_qr, admin_code: new_admin_code}} =
      Onboarding.reissue_pairing(admin.id, invite_token)

    refute new_qr == qr_token
    refute new_admin_code == admin_code

    ttl_seconds = Policy.default_ttl(:pair_qr)

    {:ok, new_qr_record} = Tokens.fetch(:pair_qr, new_qr)

    seconds_remaining =
      DateTime.diff(new_qr_record.expires_at, DateTime.utc_now(), :second)

    assert_close(ttl_seconds, seconds_remaining, 5)

    # Original, consumed token stays unusable after reissue
    assert {:error, :used} = Onboarding.redeem_pairing(qr_token)
  end

  defp assert_close(expected, actual, delta) do
    assert abs(expected - actual) <= delta,
           "Expected #{actual} to be within ±#{delta} of #{expected}"
  end
end
