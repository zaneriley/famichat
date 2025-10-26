defmodule Famichat.Auth.Onboarding.AcceptInviteTest do
  use Famichat.DataCase, async: true

  alias Famichat.Auth.Onboarding
  alias Famichat.ChatFixtures

  test "accepting a valid invite returns a registration token and second accept fails" do
    family = ChatFixtures.family_fixture()
    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    invitee_email = ChatFixtures.unique_user_email()

    {:ok, %{invite: invite_token}} =
      Onboarding.issue_invite(admin.id, invitee_email, %{
        household_id: family.id,
        role: :member
      })

    {:ok, %{payload: payload, registration_token: registration_token}} =
      Onboarding.accept_invite(invite_token)

    assert payload["household_id"] == family.id
    assert is_binary(registration_token)

    assert {:error, :used} = Onboarding.accept_invite(invite_token)
  end

  test "registration rejects mismatched email fingerprints" do
    family = ChatFixtures.family_fixture()
    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    invitee_email = ChatFixtures.unique_user_email()

    {:ok, %{invite: invite_token}} =
      Onboarding.issue_invite(admin.id, invitee_email, %{
        household_id: family.id,
        role: :member
      })

    {:ok, %{registration_token: registration_token}} =
      Onboarding.accept_invite(invite_token)

    assert {:error, :email_mismatch} =
             Onboarding.complete_registration(registration_token, %{
               "username" => ChatFixtures.unique_user_username(),
               "email" => "other_" <> invitee_email
             })
  end
end
