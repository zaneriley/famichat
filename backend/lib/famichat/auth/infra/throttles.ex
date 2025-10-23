defmodule Famichat.Auth.Infra.Throttles do
  @moduledoc """
  Macro-level rate limiting buckets. Phase 0 placeholder.
  """

  @typedoc "Enumerated throttle buckets."
  @type bucket ::
          :invite_issue
          | :invite_accept
          | :pairing_attempt
          | :webauthn_challenge
          | :passkey_failure
          | :refresh_attempt
          | :magic_link
          | :otp_issue

  @doc """
  Placeholder throttle check.
  """
  @spec check(bucket(), term(), keyword()) ::
          :ok | {:error, {:rate_limited, pos_integer()}}
  def check(_bucket, _key, _opts \\ []) do
    :ok
  end
end
