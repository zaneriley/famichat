defmodule Famichat.Auth.Onboarding.InviteExpiryTest do
  use Famichat.DataCase, async: true

  alias Famichat.Accounts.UserToken
  alias Famichat.Auth.Onboarding
  alias Famichat.Auth.Tokens
  alias Famichat.ChatFixtures
  alias Famichat.Repo
  alias Famichat.TestSupport.{RedactionHelpers, TelemetryHelpers}

  @accept_event [:famichat, :auth, :onboarding, :invite_accepted]

  test "expired invite cannot be accepted" do
    family = ChatFixtures.family_fixture()
    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    invitee_email = ChatFixtures.unique_user_email()

    {:ok, %{invite: invite_token}} =
      Onboarding.issue_invite(admin.id, invitee_email, %{
        household_id: family.id,
        role: :member
      })

    {:ok, invite_record} = Tokens.fetch(:invite, invite_token)

    invite_record
    |> UserToken.changeset(%{
      expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
    })
    |> Repo.update!()

    events =
      TelemetryHelpers.capture([@accept_event], fn ->
        assert {:error, :expired} = Onboarding.accept_invite(invite_token)
      end)

    Enum.each(events, fn %{metadata: metadata} ->
      RedactionHelpers.pii_free!(metadata)
    end)
  end

  @tag :pending
  test "cancellation prevents later acceptance" do
    # TODO: implement once invite cancellation API is available.
  end
end
