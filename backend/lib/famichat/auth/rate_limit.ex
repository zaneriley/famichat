defmodule Famichat.Auth.RateLimit do
  @moduledoc """
  Auth-layer rate limiting mechanism. Buckets are defined in
  `Famichat.Auth.RateLimit.Buckets`; this module owns the Cachex-backed
  enforcement and telemetry emission.
  """

  use Boundary,
    exports: :all,
    deps: [Famichat]

  alias Famichat.Auth.RateLimit.Buckets
  alias Famichat.Cache

  require Logger

  @default_cache :content_cache

  @type opts :: [
          limit: pos_integer(),
          interval: pos_integer(),
          cache_name: atom()
        ]

  @spec check(Buckets.t() | atom(), term(), opts()) ::
          :ok | {:error, {:rate_limited, pos_integer()}}
  def check(bucket, key, opts) when is_list(opts) do
    limit = Keyword.fetch!(opts, :limit)
    interval_seconds = Keyword.fetch!(opts, :interval)
    cache = cache_name(opts)

    try do
      if Cache.disabled?() do
        :ok
      else
        do_check(cache, bucket, key, limit, interval_seconds)
      end
    rescue
      exception ->
        handle_cache_error(exception, bucket, key, interval_seconds)
    catch
      {:error, reason} ->
        handle_cache_error(reason, bucket, key, interval_seconds)
    end
  end

  defp do_check(cache, bucket, key, limit, interval) do
    cache_key = {__MODULE__, bucket, key}

    with {:ok, count} <- Cachex.incr(cache, cache_key, 1, initial: 0),
         :ok <- ensure_ttl(cache, cache_key, interval) do
      evaluate_limit(cache, cache_key, bucket, key, count, limit, interval)
    else
      {:error, reason} ->
        handle_cache_error(reason, bucket, key, interval)
    end
  end

  defp evaluate_limit(
         _cache,
         _cache_key,
         _bucket,
         _key,
         count,
         limit,
         _interval
       )
       when count <= limit,
       do: :ok

  defp evaluate_limit(cache, cache_key, bucket, key, _count, limit, interval) do
    remaining = remaining_seconds(cache, cache_key, interval)
    emit_throttled(bucket, key, limit, remaining)
    {:error, {:rate_limited, remaining}}
  end

  defp ensure_ttl(cache, cache_key, interval) do
    case Cachex.ttl(cache, cache_key) do
      {:ok, nil} ->
        case Cachex.expire(cache, cache_key, :timer.seconds(interval)) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, _ttl} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remaining_seconds(cache, cache_key, interval) do
    case Cachex.ttl(cache, cache_key) do
      {:ok, ttl_ms} when is_integer(ttl_ms) -> max(1, div(ttl_ms + 999, 1000))
      _ -> interval
    end
  end

  defp cache_name(opts) do
    Keyword.get_lazy(opts, :cache_name, fn ->
      Application.get_env(:famichat, :rate_limiter_cache, @default_cache)
    end)
  end

  defp handle_cache_error({:error, reason}, bucket, key, interval),
    do: handle_cache_error(reason, bucket, key, interval)

  defp handle_cache_error(:no_cache = reason, bucket, key, _interval) do
    log_cache_fault(reason, bucket, key)
    :ok
  end

  defp handle_cache_error(reason, bucket, key, interval) do
    log_cache_fault(reason, bucket, key)
    emit_throttled(bucket, key, nil, interval)
    {:error, {:rate_limited, interval}}
  end

  defp emit_throttled(bucket, key, limit, remaining_seconds) do
    :telemetry.execute(
      [:famichat, :auth, :rate_limit, :throttled],
      %{count: 1},
      %{
        bucket: bucket,
        key_hash: hash_key(key),
        limit: limit,
        remaining_seconds: remaining_seconds
      }
    )
  end

  defp hash_key(key) do
    key
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp log_cache_fault(reason, bucket, key) do
    Logger.warning(fn ->
      "[Auth.RateLimit] cache fault (#{inspect(reason)}) for bucket=#{inspect(bucket)} key=#{inspect(key)}. Allowing request to proceed."
    end)
  end
end
