defmodule Famichat.Accounts.FamilyContext do
  @moduledoc """
  Resolves and persists the active-family context for a user.

  The active family is the family a user is operating inside during the
  current session. It scopes conversations, members, and admin actions.

  Resolution order:
  1. Explicit candidate (from session cookie or switch request)
  2. `last_active_family_id` from the user's DB record
  3. First membership by `inserted_at` (deterministic default)

  The returned family_id is always one the user is currently a member of.
  No family is ever returned without membership verification.

  Boundary: depends on `Famichat.Accounts` schemas and `Famichat.Repo`.
  Does NOT depend on `Famichat.Auth` (to avoid circular deps).
  """

  import Ecto.Query
  require Logger

  alias Famichat.Accounts.{HouseholdMembership, User}
  alias Famichat.Chat.Family
  alias Famichat.Repo

  @type resolution_source :: :explicit | :last_used | :only | :default

  @type resolution_result ::
          {:ok, Family.t(), resolution_source()}
          | {:error, :no_family}

  @doc """
  Resolves the active family for a user.

  Returns `{:ok, family, source}` where `source` indicates how the family
  was determined:
  - `:explicit` — the candidate_family_id was valid and the user is a member
  - `:last_used` — from `user.last_active_family_id` in the DB
  - `:only` — the user has exactly one family membership
  - `:default` — the user has multiple memberships; first by inserted_at was chosen

  Returns `{:error, :no_family}` when the user has zero family memberships.
  """
  @spec resolve(binary(), binary() | nil) :: resolution_result()
  def resolve(user_id, candidate_family_id \\ nil)

  def resolve(user_id, candidate_family_id)
      when is_binary(candidate_family_id) and candidate_family_id != "" do
    case fetch_membership_with_family(user_id, candidate_family_id) do
      {:ok, family} -> {:ok, family, :explicit}
      {:error, :not_a_member} -> resolve_from_db(user_id)
    end
  end

  def resolve(user_id, _nil_or_empty) do
    resolve_from_db(user_id)
  end

  @doc """
  Returns all family memberships for a user, sorted by insertion order.
  Each entry contains the family struct and the user's role in that family.
  """
  @spec all_memberships(binary()) :: [%{family: Family.t(), role: atom()}]
  def all_memberships(user_id) do
    from(m in HouseholdMembership,
      where: m.user_id == ^user_id,
      order_by: [asc: m.inserted_at],
      preload: [:family]
    )
    |> Repo.all()
    |> Enum.map(fn m -> %{family: m.family, role: m.role} end)
  end

  ## Private resolution steps

  defp resolve_from_db(user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :no_family}

      user ->
        resolve_from_user(user_id, user.last_active_family_id)
    end
  end

  defp resolve_from_user(user_id, last_active_family_id)
       when is_binary(last_active_family_id) and last_active_family_id != "" do
    case fetch_membership_with_family(user_id, last_active_family_id) do
      {:ok, family} ->
        {:ok, family, :last_used}

      {:error, :not_a_member} ->
        Logger.warning(
          "[FamilyContext] last_active_family_id stale for user #{user_id}, clearing"
        )

        clear_last_active_family(user_id)
        resolve_from_memberships(user_id)
    end
  end

  defp resolve_from_user(user_id, _nil_or_empty) do
    resolve_from_memberships(user_id)
  end

  defp resolve_from_memberships(user_id) do
    memberships =
      from(m in HouseholdMembership,
        where: m.user_id == ^user_id,
        order_by: [asc: m.inserted_at],
        preload: [:family]
      )
      |> Repo.all()

    case memberships do
      [] ->
        {:error, :no_family}

      [single] ->
        {:ok, single.family, :only}

      [first | _rest] ->
        {:ok, first.family, :default}
    end
  end

  defp fetch_membership_with_family(user_id, family_id) do
    case from(m in HouseholdMembership,
           where: m.user_id == ^user_id and m.family_id == ^family_id,
           preload: [:family]
         )
         |> Repo.one() do
      nil -> {:error, :not_a_member}
      m -> {:ok, m.family}
    end
  end

  # Direct DB clear of last_active_family_id. This is called within
  # FamilyContext itself (not through Identity) to avoid circular deps.
  # Uses atomic UPDATE to avoid TOCTOU race on concurrent calls.
  defp clear_last_active_family(user_id) do
    Repo.update_all(
      from(u in User, where: u.id == ^user_id),
      set: [last_active_family_id: nil]
    )

    :ok
  end
end
