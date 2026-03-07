defmodule Famichat.Communities do
  @moduledoc """
  Hidden root community helpers for one operator-owned deployment.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Accounts,
      Famichat.Chat
    ]

  import Ecto.Query, warn: false

  alias Famichat.Accounts.{Community, CommunityScope, User}
  alias Famichat.Chat.{Conversation, Family}
  alias Famichat.Repo

  @spec current_community!() :: Community.t()
  def current_community! do
    case first_community() do
      %Community{} = community ->
        community

      nil ->
        %Community{}
        |> Community.changeset(%{
          id: CommunityScope.default_id(),
          name: CommunityScope.default_name()
        })
        |> Repo.insert!()
    end
  end

  @spec backfill_nil_community_ids!() ::
          %{
            community: Community.t(),
            users_updated: non_neg_integer(),
            families_updated: non_neg_integer(),
            conversations_updated: non_neg_integer()
          }
  def backfill_nil_community_ids! do
    community = current_community!()

    %{
      community: community,
      users_updated: backfill(User, community.id),
      families_updated: backfill(Family, community.id),
      conversations_updated: backfill(Conversation, community.id)
    }
  end

  defp first_community do
    Community
    |> order_by([community], asc: community.inserted_at, asc: community.id)
    |> limit(1)
    |> Repo.one()
  end

  defp backfill(schema, community_id) do
    {count, _rows} =
      schema
      |> where([record], is_nil(field(record, :community_id)))
      |> Repo.update_all(set: [community_id: community_id])

    count
  end
end
