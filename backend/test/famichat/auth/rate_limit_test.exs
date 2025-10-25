defmodule Famichat.Auth.RateLimitTest do
  use ExUnit.Case, async: true

  alias Famichat.Auth.RateLimit

  setup do
    cache_name =
      :"rate_limit_test_cache_#{System.unique_integer([:positive])}"

    start_supervised!({Cachex, name: cache_name})

    %{cache_name: cache_name}
  end

  test "returns :ok while under the configured limit", %{cache_name: cache} do
    assert :ok =
             RateLimit.check(:test_bucket, "key",
               limit: 2,
               interval: 60,
               cache_name: cache
             )

    assert :ok =
             RateLimit.check(:test_bucket, "key",
               limit: 2,
               interval: 60,
               cache_name: cache
             )
  end

  test "returns rate_limited error once the limit is exceeded", %{
    cache_name: cache
  } do
    assert :ok =
             RateLimit.check(:another_bucket, "another-key",
               limit: 1,
               interval: 60,
               cache_name: cache
             )

    assert {:error, {:rate_limited, retry}} =
             RateLimit.check(:another_bucket, "another-key",
               limit: 1,
               interval: 60,
               cache_name: cache
             )

    assert retry >= 1
  end

  test "allows traffic when the backing cache is unavailable", %{
    cache_name: cache
  } do
    cache
    |> Process.whereis()
    |> case do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end

    assert :ok =
             RateLimit.check(:missing_cache, "missing-key",
               limit: 1,
               interval: 60,
               cache_name: cache
             )
  end
end
