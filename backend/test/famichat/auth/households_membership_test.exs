defmodule Famichat.Auth.Households.MembershipTest do
  use Famichat.DataCase, async: true

  alias Famichat.Auth.Households
  alias Famichat.Accounts.HouseholdMembership
  alias Famichat.ChatFixtures
  alias Famichat.Repo

  test "ensure functions enforce membership and admin role" do
    family = ChatFixtures.family_fixture()
    other_family = ChatFixtures.family_fixture()

    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    outsider =
      ChatFixtures.user_fixture(%{family_id: other_family.id, role: :member})

    assert {:error, :not_in_household} =
             Households.ensure_membership(outsider.id, family.id)

    assert {:ok, _} = Households.ensure_membership(member.id, family.id)

    assert {:error, :forbidden} =
             Households.ensure_admin_membership(member.id, family.id)

    assert {:ok, _} = Households.ensure_admin_membership(admin.id, family.id)
  end

  test "upsert_membership/3 is idempotent and updates roles" do
    family = ChatFixtures.family_fixture()
    other_family = ChatFixtures.family_fixture()

    user =
      ChatFixtures.user_fixture(%{family_id: other_family.id, role: :member})

    assert {:ok, membership} =
             Households.upsert_membership(user.id, family.id, :member)

    assert membership.role == :member
    assert membership.user_id == user.id

    assert_membership_count(user.id, family.id, 1)

    assert {:ok, same_membership} =
             Households.upsert_membership(user.id, family.id, :member)

    assert same_membership.id == membership.id
    assert same_membership.role == :member
    assert_membership_count(user.id, family.id, 1)

    assert {:ok, updated_membership} =
             Households.upsert_membership(user.id, family.id, :admin)

    assert updated_membership.id == membership.id
    assert updated_membership.role == :admin
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
