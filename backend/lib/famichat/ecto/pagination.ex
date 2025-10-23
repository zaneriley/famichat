defmodule Famichat.Ecto.Pagination do
  @moduledoc """
  Generic Ecto query pagination utility.
  De-coupled from any specific domain; purely a query transformation tool.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @default_limit 20
  @max_limit 100

  @primary_key false
  embedded_schema do
    field :limit, :integer, default: @default_limit
    field :offset, :integer, default: 0
  end

  @doc """
  Validates params and applies pagination to the query.
  Returns `{:ok, query}` or `{:error, {:invalid_pagination, changeset}}`.
  """
  def apply_or_default(query, params \\ %{}) do
    case validate(params || %{}) do
      {:ok, pagination} -> {:ok, apply_pagination(query, pagination)}
      {:error, changeset} -> {:error, {:invalid_pagination, changeset}}
    end
  end

  defp validate(params) do
    %__MODULE__{}
    |> cast(params, [:limit, :offset])
    |> validate_number(:limit,
      greater_than: 0,
      less_than_or_equal_to: @max_limit
    )
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> apply_action(:insert)
  end

  defp apply_pagination(query, %__MODULE__{limit: limit, offset: offset}) do
    query |> limit(^limit) |> offset(^offset)
  end
end
