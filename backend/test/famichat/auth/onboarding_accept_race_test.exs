defmodule Famichat.Auth.Onboarding.AcceptRaceTest do
  use Famichat.DataCase, async: false

  alias Famichat.Accounts.UserToken
  alias Famichat.Auth.Onboarding
  alias Famichat.Auth.Tokens
  alias Famichat.ChatFixtures
  alias Famichat.Repo

  @tag :pending
  test "only one invite acceptance succeeds under concurrent load" do
    family = ChatFixtures.family_fixture()
    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    invitee_email = ChatFixtures.unique_user_email()

    {:ok, %{invite: invite_token}} =
      Onboarding.issue_invite(admin.id, invitee_email, %{
        household_id: family.id,
        role: :member
      })

    {:ok, invite_record} = Tokens.fetch(:invite, invite_token)

    task_fun = fn -> Onboarding.accept_invite(invite_token) end

    [res1, res2] =
      [Task.async(task_fun), Task.async(task_fun)]
      |> Enum.map(&Task.await(&1, 2000))

    assert Enum.any?([res1, res2], &match?({:error, _}, &1))

    reloaded = Repo.get!(UserToken, invite_record.id)
    assert %DateTime{} = reloaded.used_at
  end
end
