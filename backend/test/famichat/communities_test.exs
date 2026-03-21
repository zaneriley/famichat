defmodule Famichat.CommunitiesTest do
  use Famichat.DataCase, async: true

  import Ecto.Changeset, only: [force_change: 3]

  alias Famichat.Accounts.{Community, User}
  alias Famichat.Chat.{Conversation, Family}
  alias Famichat.Communities

  describe "backfill_nil_community_ids!/0" do
    @tag known_failure: "B7: calls undefined Communities.backfill_nil_community_ids!/0 (2026-03-21)"
    test "creates one default community and backfills existing unscoped rows" do
      family = unscoped_family_fixture()
      user = unscoped_user_fixture()
      peer = unscoped_user_fixture()
      conversation = unscoped_conversation_fixture(family)

      assert is_nil(Repo.get!(Family, family.id).community_id)
      assert is_nil(Repo.get!(User, user.id).community_id)
      assert is_nil(Repo.get!(User, peer.id).community_id)
      assert is_nil(Repo.get!(Conversation, conversation.id).community_id)

      result = Communities.backfill_nil_community_ids!()

      assert %Community{} = result.community
      assert result.users_updated == 2
      assert result.families_updated == 1
      assert result.conversations_updated == 1
      assert Repo.aggregate(Community, :count) == 1

      assert Repo.get!(Family, family.id).community_id == result.community.id
      assert Repo.get!(User, user.id).community_id == result.community.id
      assert Repo.get!(User, peer.id).community_id == result.community.id

      assert Repo.get!(Conversation, conversation.id).community_id ==
               result.community.id
    end

    @tag known_failure: "B7: calls undefined Communities.backfill_nil_community_ids!/0 (2026-03-21)"
    test "reuses the existing community and is idempotent" do
      community = community_fixture(%{name: "Dogfood Community"})
      family = unscoped_family_fixture()
      user = unscoped_user_fixture()
      peer = unscoped_user_fixture()
      conversation = unscoped_conversation_fixture(family)

      first = Communities.backfill_nil_community_ids!()

      assert first.community.id == community.id
      assert first.users_updated == 2
      assert first.families_updated == 1
      assert first.conversations_updated == 1

      second = Communities.backfill_nil_community_ids!()

      assert second.community.id == community.id
      assert second.users_updated == 0
      assert second.families_updated == 0
      assert second.conversations_updated == 0
      assert Repo.aggregate(Community, :count) == 1
      assert Repo.get!(Family, family.id).community_id == community.id
      assert Repo.get!(User, user.id).community_id == community.id
      assert Repo.get!(User, peer.id).community_id == community.id

      assert Repo.get!(Conversation, conversation.id).community_id ==
               community.id
    end
  end

  defp community_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        id: Ecto.UUID.generate(),
        name: "Community #{System.unique_integer([:positive])}"
      })

    %Community{}
    |> Community.changeset(attrs)
    |> Repo.insert!()
  end

  defp unscoped_family_fixture do
    %Family{}
    |> Family.changeset(%{
      name: "Family #{System.unique_integer([:positive])}"
    })
    |> force_change(:community_id, nil)
    |> Repo.insert!()
  end

  defp unscoped_user_fixture do
    %User{}
    |> User.changeset(%{
      username: "user#{System.unique_integer([:positive])}",
      email: "user#{System.unique_integer([:positive])}@example.com",
      status: :active,
      confirmed_at: DateTime.utc_now()
    })
    |> force_change(:community_id, nil)
    |> Repo.insert!()
  end

  defp unscoped_conversation_fixture(family) do
    direct_key =
      Conversation.compute_direct_key(
        Ecto.UUID.generate(),
        Ecto.UUID.generate(),
        family.id
      )

    %Conversation{}
    |> Conversation.create_changeset(%{
      family_id: family.id,
      conversation_type: :direct,
      metadata: %{},
      direct_key: direct_key
    })
    |> force_change(:community_id, nil)
    |> Repo.insert!()
  end
end
