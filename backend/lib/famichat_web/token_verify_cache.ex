defmodule FamichatWeb.TokenVerifyCache do
  @moduledoc """
  Small ETS-backed cache for SessionRefresh access-token verification results.
  """

  use GenServer

  @table :session_token_verify_cache
  @ttl_ms 30_000
  @max_entries 10_000

  @type cache_status :: :hit | :miss

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @spec verify_cached(String.t()) :: cache_status()
  def verify_cached(token) when is_binary(token) do
    case :ets.whereis(@table) do
      :undefined ->
        :miss

      _table ->
        now_ms = System.monotonic_time(:millisecond)

        case :ets.lookup(@table, token) do
          [{^token, expires_at_ms}] when expires_at_ms > now_ms ->
            :hit

          [{^token, _expires_at_ms}] ->
            :ets.delete(@table, token)
            :miss

          [] ->
            :miss
        end
    end
  end

  @spec cache(String.t()) :: :ok
  def cache(token) when is_binary(token) do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _table ->
        now_ms = System.monotonic_time(:millisecond)
        maybe_trim(now_ms)
        :ets.insert(@table, {token, now_ms + @ttl_ms})
        :ok
    end
  end

  @spec clear() :: :ok
  def clear do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _table ->
        :ets.delete_all_objects(@table)
        :ok
    end
  end

  defp maybe_trim(now_ms) do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _table ->
        maybe_trim_existing_table(now_ms, current_size())
    end
  end

  defp maybe_trim_existing_table(_now_ms, size) when size < @max_entries,
    do: :ok

  defp maybe_trim_existing_table(now_ms, _size) do
    purge_expired(now_ms)

    case current_size() do
      size when size < @max_entries -> :ok
      _size -> trim_oversized_table()
    end
  end

  defp purge_expired(now_ms) do
    match_spec = [
      {{:"$1", :"$2"}, [{:"=<", :"$2", now_ms}], [true]}
    ]

    :ets.select_delete(@table, match_spec)
    :ok
  end

  defp trim_oversized_table do
    overflow = current_size() - @max_entries + 1

    @table
    |> :ets.tab2list()
    |> Enum.take(overflow)
    |> Enum.each(fn {token, _expires_at_ms} ->
      :ets.delete(@table, token)
    end)

    :ok
  end

  defp current_size do
    case :ets.info(@table, :size) do
      :undefined -> 0
      size -> size
    end
  end
end
