defmodule Famichat.Auth.Households do
  @moduledoc """
  Household governance helpers (membership + role lookups).
  """

  use Boundary,
    exports: :all,
    deps: [
      Famichat
    ]

  alias Ecto.Changeset
  alias Famichat.Accounts.HouseholdMembership
  alias Famichat.Repo

  @type role :: :admin | :member

  @doc "Adds a user to the household with the provided role."
  @spec add_member(Ecto.UUID.t(), Ecto.UUID.t(), role()) ::
          {:ok, HouseholdMembership.t()} | {:error, Changeset.t()}
  def add_member(household_id, user_id, role \\ :member) do
    %HouseholdMembership{}
    |> HouseholdMembership.changeset(%{
      family_id: household_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  @doc "Returns the stored household role for the given user."
  @spec member_role(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, role()} | :error
  def member_role(household_id, user_id) do
    case Repo.get_by(HouseholdMembership,
           family_id: household_id,
           user_id: user_id
         ) do
      %HouseholdMembership{role: role} -> {:ok, role}
      nil -> :error
    end
  end

  @doc """
  Ensures the user belongs to the household, returning the stored membership or
  `{:error, :not_in_household}`.
  """
  @spec ensure_membership(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, HouseholdMembership.t()} | {:error, :not_in_household}
  def ensure_membership(user_id, household_id) do
    case Repo.get_by(HouseholdMembership,
           user_id: user_id,
           family_id: household_id
         ) do
      %HouseholdMembership{} = membership -> {:ok, membership}
      nil -> {:error, :not_in_household}
    end
  end

  @doc """
  Ensures the user is an admin of the household.
  """
  @spec ensure_admin_membership(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, HouseholdMembership.t()}
          | {:error, :forbidden | :not_in_household}
  def ensure_admin_membership(user_id, household_id) do
    with {:ok, membership} <- ensure_membership(user_id, household_id),
         true <- membership.role == :admin || {:error, :forbidden} do
      {:ok, membership}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Inserts or updates the household membership with the provided role.
  """
  @spec upsert_membership(Ecto.UUID.t(), Ecto.UUID.t(), role()) ::
          {:ok, HouseholdMembership.t()} | {:error, Changeset.t()}
  def upsert_membership(user_id, household_id, role \\ :member) do
    attrs = %{
      user_id: user_id,
      family_id: household_id,
      role: role
    }

    case Repo.get_by(HouseholdMembership,
           user_id: user_id,
           family_id: household_id
         ) do
      nil ->
        %HouseholdMembership{}
        |> HouseholdMembership.changeset(attrs)
        |> Repo.insert()

      %HouseholdMembership{} = membership ->
        membership
        |> HouseholdMembership.changeset(attrs)
        |> Repo.update()
    end
  end
end
