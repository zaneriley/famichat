defmodule Famichat.Accounts.RateLimiter do
  @moduledoc """
  Lightweight rate limiter built on Cachex. Rate limits are bucketed by a tuple
  key so multiple policies can coexist (e.g., per-IP, per-user).
  """

  alias Famichat.Cache
  require Logger

  @default_cache :content_cache

  @spec throttle(atom(), term(), pos_integer(), pos_integer(), Keyword.t()) ::
          :ok | {:error, :throttled, pos_integer()}
  def throttle(bucket, key, limit, interval_seconds, opts \\ [])
      when is_atom(bucket) and limit > 0 and interval_seconds > 0 do
    if Cache.disabled?() do
      :ok
    else
      cache = cache_name(opts)
      cache_key = {__MODULE__, bucket, key}

      with {:ok, count} <- Cachex.incr(cache, cache_key, 1, initial: 0),
           :ok <- ensure_ttl(cache, cache_key, interval_seconds) do
        evaluate_limit(cache, count, cache_key, interval_seconds, limit)
      else
        {:error, reason} ->
          handle_cache_error(reason, bucket, key, interval_seconds)
      end
    end
  rescue
    exception ->
      handle_cache_error(exception, bucket, key, interval_seconds)
  end

  defp evaluate_limit(cache, count, cache_key, interval_seconds, limit) do
    if count <= limit do
      :ok
    else
      remaining =
        case Cachex.ttl(cache, cache_key) do
          {:ok, ttl_ms} when is_integer(ttl_ms) -> div(ttl_ms + 999, 1000)
          _ -> interval_seconds
        end

      remaining_seconds = max(1, remaining)

      emit_throttled_telemetry(cache_key, limit, remaining_seconds)

      {:error, :throttled, remaining_seconds}
    end
  end

  defp ensure_ttl(cache, cache_key, interval_seconds) do
    case Cachex.ttl(cache, cache_key) do
      {:ok, nil} ->
        case Cachex.expire(cache, cache_key, :timer.seconds(interval_seconds)) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, _ttl} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_cache_error({:error, reason}, bucket, key, interval_seconds) do
    handle_cache_error(reason, bucket, key, interval_seconds)
  end

  defp handle_cache_error(:no_cache = reason, bucket, key, _interval_seconds) do
    log_cache_fault(reason, bucket, key)
    :ok
  end

  defp handle_cache_error(reason, bucket, key, interval_seconds) do
    log_cache_fault(reason, bucket, key)
    emit_throttled_telemetry({__MODULE__, bucket, key}, nil, interval_seconds)
    {:error, :throttled, interval_seconds}
  end

  defp log_cache_fault(reason, bucket, key) do
    Logger.warning(fn ->
      "[RateLimiter] cache fault (#{inspect(reason)}) for bucket=#{inspect(bucket)} key=#{inspect(key)}. Allowing request to proceed."
    end)
  end

  defp emit_throttled_telemetry(
         {__MODULE__, bucket, key},
         limit,
         remaining_seconds
       ) do
    :telemetry.execute(
      [:famichat, :rate_limiter, :throttled],
      %{count: 1},
      %{
        bucket: bucket,
        key_hash: hash_key(key),
        limit: limit,
        remaining_seconds: remaining_seconds
      }
    )
  end

  defp emit_throttled_telemetry(_, _, _), do: :ok

  defp hash_key(key) do
    key
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp cache_name(opts) do
    Keyword.get_lazy(opts, :cache_name, fn ->
      Application.get_env(:famichat, :rate_limiter_cache, @default_cache)
    end)
  end
end
