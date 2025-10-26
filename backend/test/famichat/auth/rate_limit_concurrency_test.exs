defmodule Famichat.Auth.RateLimitConcurrencyTest do
  use ExUnit.Case, async: false

  alias Famichat.Auth.RateLimit
  alias Famichat.Cache

  setup do
    Cache.clear()
    :ok
  end

  test "concurrent checks respect configured limits" do
    bucket =
      String.to_atom("concurrency.bucket.#{System.unique_integer([:positive])}")

    key = "key-#{System.unique_integer([:positive])}"
    limit = 5
    interval = 60

    results =
      1..10
      |> Task.async_stream(
        fn _ ->
          RateLimit.check(bucket, key, limit: limit, interval: interval)
        end,
        max_concurrency: 10,
        timeout: 2000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    throttled =
      Enum.count(results, fn
        {:error, {:rate_limited, retry}} when retry > 0 -> true
        _ -> false
      end)

    assert throttled >= 5
    assert Enum.count(results, &(&1 == :ok)) <= limit
  end
end
