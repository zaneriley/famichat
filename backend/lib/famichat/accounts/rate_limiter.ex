defmodule Famichat.Accounts.RateLimiter do
  @moduledoc "Deprecated shim. Use `Famichat.Auth.RateLimit` instead."
  @deprecated "use Famichat.Auth.RateLimit"

  alias Famichat.Auth.RateLimit

  @spec throttle(atom(), term(), pos_integer(), pos_integer(), Keyword.t()) ::
          :ok | {:error, :throttled, pos_integer()}
  def throttle(bucket, key, limit, interval_seconds, opts \\ [])
      when limit > 0 and interval_seconds > 0 do
    rate_opts =
      opts
      |> Keyword.put(:limit, limit)
      |> Keyword.put(:interval, interval_seconds)

    case RateLimit.check(bucket, key, rate_opts) do
      :ok -> :ok
      {:error, {:rate_limited, retry}} -> {:error, :throttled, retry}
    end
  end
end
