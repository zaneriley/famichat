defmodule Famichat.Auth.Households do
  @moduledoc """
  Household governance helpers (membership + role lookups).
  """

  use Boundary

  alias Ecto.Changeset
  alias Famichat.Accounts.HouseholdMembership
  alias Famichat.Repo

  @type role :: :admin | :member

  @doc "Adds a user to the household with the provided role."
  @spec add_member(Ecto.UUID.t(), Ecto.UUID.t(), role()) ::
          {:ok, HouseholdMembership.t()} | {:error, Changeset.t()}
  def add_member(family_id, user_id, role \\ :member) do
    %HouseholdMembership{}
    |> HouseholdMembership.changeset(%{
      family_id: family_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  @doc "Returns the stored household role for the given user."
  @spec member_role(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, role()} | :error
  def member_role(family_id, user_id) do
    case Repo.get_by(HouseholdMembership,
           family_id: family_id,
           user_id: user_id
         ) do
      %HouseholdMembership{role: role} -> {:ok, role}
      nil -> :error
    end
  end
end
