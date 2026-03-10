defmodule Famichat.Chat.OrphanFamilyCleanup do
  @moduledoc """
  Deletes families that have no household memberships and no conversations.

  These accumulate when users abandon the family setup flow after creating
  the family row but before completing registration. A 1-hour buffer avoids
  racing with in-progress setups.

  Called by `OrphanFamilyReaper` on a timer.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Accounts,
      Famichat.Chat
    ]

  import Ecto.Query

  alias Famichat.Accounts.HouseholdMembership
  alias Famichat.Chat.{Conversation, Family}
  alias Famichat.Repo

  # Families younger than this are left alone to avoid racing in-progress setups.
  @buffer_seconds 60 * 60

  @spec run() :: {:ok, non_neg_integer()}
  def run do
    cutoff = DateTime.add(DateTime.utc_now(), -@buffer_seconds, :second)

    membership_subquery = from m in HouseholdMembership, select: m.family_id
    conversation_subquery = from c in Conversation, select: c.family_id

    {count, _} =
      Repo.delete_all(
        from f in Family,
          where: f.inserted_at < ^cutoff,
          where: f.id not in subquery(membership_subquery),
          where: f.id not in subquery(conversation_subquery)
      )

    :telemetry.execute(
      [:famichat, :chat, :orphan_families_cleaned],
      %{count: count},
      %{}
    )

    {:ok, count}
  end
end
