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

  alias Famichat.Accounts.{Community, User}
  alias Famichat.Chat.{Conversation, Family}
  alias Famichat.Repo

  @doc """
  Returns the singleton operator-owned community, creating it with default
  values on first access.

  Delegates to `Famichat.Accounts.current_community!/0`, which owns the
  implementation to avoid a dependency cycle between `Famichat.Communities`
  and `Famichat.Chat`.
  """
  @spec current_community!() :: Community.t()
  defdelegate current_community!(), to: Famichat.Accounts

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

  defp backfill(schema, community_id) do
    {count, _rows} =
      schema
      |> where([record], is_nil(field(record, :community_id)))
      |> Repo.update_all(set: [community_id: community_id])

    count
  end
end
