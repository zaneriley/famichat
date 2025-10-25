defmodule Famichat.Auth.RateLimit do
  @moduledoc """
  Auth-layer rate limiting facade. Buckets are defined in
  `Famichat.Auth.RateLimit.Buckets` and ultimately delegate to the existing
  `Famichat.Accounts.RateLimiter` implementation.
  """

  alias Famichat.Accounts.RateLimiter
  alias Famichat.Auth.RateLimit.Buckets

  @type opts :: [limit: pos_integer(), interval: pos_integer()]

  @spec check(Buckets.t(), term(), opts()) ::
          :ok | {:error, {:rate_limited, pos_integer()}}
  def check(bucket, key, opts) when is_list(opts) do
    limit = Keyword.fetch!(opts, :limit)
    interval = Keyword.fetch!(opts, :interval)

    case RateLimiter.throttle(bucket, key, limit, interval) do
      :ok -> :ok
      {:error, :throttled, retry} -> {:error, {:rate_limited, retry}}
    end
  end
end
