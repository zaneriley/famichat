defmodule Famichat.Auth.Households.MembershipIntegrityTest do
  use Famichat.DataCase, async: true

  import Ecto.Query
  alias Famichat.Accounts.HouseholdMembership
  alias Famichat.Auth.Households
  alias Famichat.ChatFixtures
  alias Famichat.Repo

  test "membership helpers enforce boundaries" do
    family = ChatFixtures.family_fixture()
    other_family = ChatFixtures.family_fixture()

    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    outsider =
      ChatFixtures.user_fixture(%{family_id: other_family.id, role: :member})

    assert {:ok, _} = Households.ensure_membership(member.id, family.id)

    assert {:error, :not_in_household} =
             Households.ensure_membership(outsider.id, family.id)

    assert {:ok, _} = Households.ensure_admin_membership(admin.id, family.id)

    assert {:error, :forbidden} =
             Households.ensure_admin_membership(member.id, family.id)
  end

  test "upsert_membership creates once and promotes role" do
    family = ChatFixtures.family_fixture()
    user = ChatFixtures.user_fixture()

    assert {:ok, membership} =
             Households.upsert_membership(user.id, family.id, :member)

    assert membership.role == :member

    assert_membership_count(user.id, family.id, 1)

    assert {:ok, ^membership} =
             Households.upsert_membership(user.id, family.id, :member)

    assert_membership_count(user.id, family.id, 1)

    assert {:ok, updated} =
             Households.upsert_membership(user.id, family.id, :admin)

    assert updated.role == :admin
    assert updated.id == membership.id
    assert_membership_count(user.id, family.id, 1)
  end

  defp assert_membership_count(user_id, family_id, expected) do
    count =
      HouseholdMembership
      |> where([m], m.user_id == ^user_id and m.family_id == ^family_id)
      |> Repo.aggregate(:count, :id)

    assert count == expected
  end
end
