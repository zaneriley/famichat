defmodule Famichat.Accounts.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Famichat.Accounts.RateLimiter

  setup do
    cache_name =
      :"rate_limiter_test_cache_#{System.unique_integer([:positive])}"

    start_supervised!({Cachex, name: cache_name})

    %{cache_name: cache_name}
  end

  test "returns :ok while under the configured limit", %{cache_name: cache_name} do
    assert :ok =
             RateLimiter.throttle(:test_bucket, "key", 2, 60,
               cache_name: cache_name
             )

    assert :ok =
             RateLimiter.throttle(:test_bucket, "key", 2, 60,
               cache_name: cache_name
             )
  end

  test "returns throttled error once the limit is exceeded", %{
    cache_name: cache_name
  } do
    assert :ok =
             RateLimiter.throttle(:test_bucket, "another-key", 1, 60,
               cache_name: cache_name
             )

    assert {:error, :throttled, retry} =
             RateLimiter.throttle(:test_bucket, "another-key", 1, 60,
               cache_name: cache_name
             )

    assert retry >= 1
  end

  test "allows traffic when the backing cache is unavailable", %{
    cache_name: cache_name
  } do
    cache_name
    |> Process.whereis()
    |> case do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end

    assert :ok =
             RateLimiter.throttle(:test_bucket, "missing-cache", 1, 60,
               cache_name: cache_name
             )
  end
end
