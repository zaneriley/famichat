defmodule Famichat.Accounts.CommunityScope do
  @moduledoc """
  Hardcoded defaults for the single operator-owned community root scope.
  """

  @default_id "00000000-0000-0000-0000-000000000001"
  @default_name "Famichat Community"

  @spec default_id() :: Ecto.UUID.t()
  def default_id, do: @default_id

  @spec default_name() :: String.t()
  def default_name, do: @default_name
end
