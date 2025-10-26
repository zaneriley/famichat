defmodule Famichat.Auth.Onboarding.InvitePolicyTest do
  use Famichat.DataCase, async: true

  alias Famichat.Auth.Onboarding
  alias Famichat.Auth.Tokens
  alias Famichat.Auth.Tokens.Policy
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.{RedactionHelpers, TelemetryHelpers}

  @invite_event [:famichat, :auth, :onboarding, :invite_issued]

  test "only admins can issue invites and issued token respects TTL" do
    family = ChatFixtures.family_fixture()
    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})
    invitee_email = ChatFixtures.unique_user_email()

    assert {:error, :forbidden} =
             Onboarding.issue_invite(member.id, invitee_email, %{
               household_id: family.id,
               role: :member
             })

    events =
      TelemetryHelpers.capture([@invite_event], fn ->
        Onboarding.issue_invite(admin.id, invitee_email, %{
          household_id: family.id,
          role: :member
        })
      end)

    [%{metadata: metadata}] =
      Enum.filter(events, fn %{metadata: metadata} ->
        metadata[:inviter_id] == admin.id
      end)

    assert metadata[:household_id] == family.id
    assert metadata[:inviter_id] == admin.id
    RedactionHelpers.pii_free!(metadata)

    {:ok, %{invite: invite_token}} =
      Onboarding.issue_invite(admin.id, invitee_email, %{
        household_id: family.id,
        role: :member
      })

    {:ok, invite_record} = Tokens.fetch(:invite, invite_token)
    ttl = Policy.default_ttl(:invite)

    seconds_remaining =
      DateTime.diff(invite_record.expires_at, DateTime.utc_now(), :second)

    assert seconds_remaining <= ttl
    assert seconds_remaining >= ttl - 5
  end
end
