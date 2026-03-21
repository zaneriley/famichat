defmodule Famichat.Accounts.FirstRun do
  @moduledoc """
  Detects whether the Famichat instance has been bootstrapped (at least one user exists).

  Uses an ETS-backed boolean cache so the check is fast on every request.
  Once the instance is bootstrapped the flag flips to `true` and never reverts.
  """

  import Ecto.Query, only: [from: 2]

  alias Famichat.Accounts.User
  alias Famichat.Repo

  @table __MODULE__

  @doc """
  Returns `true` if at least one user exists in the database.

  The result is cached in ETS after the first positive check. Subsequent calls
  return the cached value without hitting the database.
  """
  @spec bootstrapped?() :: boolean()
  def bootstrapped? do
    case lookup_cache() do
      {:ok, true} ->
        true

      _ ->
        # Not yet cached or cached as false -- check the DB.
        result = user_exists?()

        if result do
          put_cache(true)
        end

        result
    end
  end

  @doc """
  Force the bootstrapped flag to true in ETS without querying the DB.
  Use in test setup blocks that assume a bootstrapped instance but
  don't test the bootstrap flow itself.
  """
  @spec force_bootstrapped!() :: :ok
  def force_bootstrapped! do
    put_cache(true)
    :ok
  end

  @doc """
  Clears the cached bootstrapped flag. Useful in tests.
  """
  @spec reset_cache() :: :ok
  def reset_cache do
    try do
      :ets.delete(@table, :bootstrapped)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  # -- Private ----------------------------------------------------------------

  defp user_exists? do
    try do
      Repo.exists?(from(u in User, where: u.status == :active, limit: 1))
    rescue
      # During compilation or before Repo is started, return false gracefully.
      _ -> false
    end
  end

  defp lookup_cache do
    try do
      case :ets.lookup(@table, :bootstrapped) do
        [{:bootstrapped, value}] -> {:ok, value}
        [] -> :miss
      end
    rescue
      ArgumentError ->
        # Table doesn't exist yet -- create it.
        ensure_table()
        :miss
    end
  end

  defp put_cache(value) do
    try do
      :ets.insert(@table, {:bootstrapped, value})
    rescue
      ArgumentError ->
        ensure_table()
        :ets.insert(@table, {:bootstrapped, value})
    end
  end

  defp ensure_table do
    try do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    rescue
      # Another process may have created it concurrently.
      ArgumentError -> :ok
    end
  end
end
