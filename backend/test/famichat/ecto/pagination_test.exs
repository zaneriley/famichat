defmodule Famichat.Ecto.PaginationTest do
  use Famichat.DataCase, async: true

  import Ecto.Query

  alias Famichat.Ecto.Pagination
  alias Famichat.Repo

  describe "apply_or_default/2" do
    test "applies integer params" do
      base_query = from(m in Famichat.Chat.Message)

      assert {:ok, query} =
               Pagination.apply_or_default(base_query, %{limit: 10, offset: 5})

      {_sql, params} = Ecto.Adapters.SQL.to_sql(:all, Repo, query)
      assert params == [10, 5]
    end

    test "casts string params" do
      base_query = from(m in Famichat.Chat.Message)

      assert {:ok, query} =
               Pagination.apply_or_default(base_query, %{
                 limit: "15",
                 offset: "2"
               })

      {_sql, params} = Ecto.Adapters.SQL.to_sql(:all, Repo, query)
      assert params == [15, 2]
    end

    test "returns error for invalid params" do
      base_query = from(m in Famichat.Chat.Message)

      assert {:error, {:invalid_pagination, changeset}} =
               Pagination.apply_or_default(base_query, %{limit: 500, offset: -1})

      assert {"must be less than or equal to %{number}", _} =
               Keyword.fetch!(changeset.errors, :limit)

      assert {"must be greater than or equal to %{number}", _} =
               Keyword.fetch!(changeset.errors, :offset)
    end

    test "applies defaults when params empty" do
      base_query = from(m in Famichat.Chat.Message)

      assert {:ok, query} = Pagination.apply_or_default(base_query, %{})
      {_sql, params} = Ecto.Adapters.SQL.to_sql(:all, Repo, query)
      assert params == [20, 0]

      assert {:ok, query_nil} = Pagination.apply_or_default(base_query, nil)
      {_sql_nil, params_nil} = Ecto.Adapters.SQL.to_sql(:all, Repo, query_nil)
      assert params_nil == [20, 0]
    end
  end
end
