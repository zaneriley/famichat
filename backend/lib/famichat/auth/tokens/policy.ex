defmodule Famichat.Auth.Tokens.Policy.Definition do
  @moduledoc "Typed description of a token kind."

  @enforce_keys [:kind, :storage, :ttl, :max_ttl, :audience]
  defstruct [
    :kind,
    :storage,
    :ttl,
    :max_ttl,
    :audience,
    :legacy_context,
    :signing_salt,
    :subject_strategy
  ]

  @type t :: %__MODULE__{
          kind: Famichat.Auth.Tokens.kind(),
          storage: Famichat.Auth.Tokens.Policy.storage(),
          ttl: pos_integer(),
          max_ttl: pos_integer(),
          audience: atom(),
          legacy_context: String.t() | nil,
          signing_salt: String.t() | nil,
          subject_strategy: :none | :user_id | :device_id | :email_sha256
        }
end

defmodule Famichat.Auth.Tokens.Policy do
  @moduledoc """
  Canonical policies for all authentication token kinds.

  The policy data lives here (domain layer) so that every caller — legacy
  or new — reads from a single source of truth. Infrastructure modules
  receive a policy struct instead of redefining TTLs, audiences, or
  storage classes.

  ## TTL conventions

  All TTL values are in **seconds**. Do NOT use `:timer.hours/1` or
  `:timer.minutes/1` — those return milliseconds. Use the named
  constants below for readability.
  """

  @typedoc "Storage backends supported by token issuance."
  @type storage :: :ledgered | :signed | :device_secret

  @typedoc "Audience scopes for token kinds."
  @type audience :: :registrant | :user | :device | :admin

  alias Famichat.Auth.Tokens.Policy.Definition

  # TTL named constants — all values in seconds.
  # Using named constants rather than raw arithmetic prevents unit confusion
  # (e.g. accidentally using :timer.hours/1 which returns milliseconds).
  @one_minute 60
  @five_minutes 5 * @one_minute
  @ten_minutes 10 * @one_minute
  @fifteen_minutes 15 * @one_minute
  @thirty_minutes 30 * @one_minute
  @one_hour 3600
  @one_day 86_400
  @three_days 3 * @one_day
  @seven_days 7 * @one_day
  @thirty_days 30 * @one_day
  @ninety_days 90 * @one_day

  @policies Macro.escape(%{
              invite: %Definition{
                kind: :invite,
                storage: :ledgered,
                ttl: @three_days,
                max_ttl: @seven_days,
                audience: :registrant,
                legacy_context: "invite",
                subject_strategy: :none
              },
              pair_qr: %Definition{
                kind: :pair_qr,
                storage: :ledgered,
                ttl: @ten_minutes,
                max_ttl: @thirty_minutes,
                audience: :device,
                legacy_context: "pair",
                subject_strategy: :none
              },
              pair_admin_code: %Definition{
                kind: :pair_admin_code,
                storage: :ledgered,
                ttl: @ten_minutes,
                max_ttl: @thirty_minutes,
                audience: :device,
                legacy_context: "pair",
                subject_strategy: :none
              },
              invite_registration: %Definition{
                kind: :invite_registration,
                storage: :ledgered,
                ttl: @ten_minutes,
                max_ttl: @thirty_minutes,
                audience: :registrant,
                legacy_context: "invite_registration",
                subject_strategy: :user_id
              },
              passkey_registration: %Definition{
                kind: :passkey_registration,
                storage: :ledgered,
                ttl: @ten_minutes,
                max_ttl: @thirty_minutes,
                audience: :user,
                legacy_context: "passkey_register",
                subject_strategy: :user_id
              },
              passkey_assertion: %Definition{
                kind: :passkey_assertion,
                storage: :ledgered,
                ttl: @five_minutes,
                max_ttl: @fifteen_minutes,
                audience: :user,
                legacy_context: "passkey_assert_challenge",
                subject_strategy: :user_id
              },
              magic_link: %Definition{
                kind: :magic_link,
                storage: :ledgered,
                ttl: @fifteen_minutes,
                max_ttl: @one_hour,
                audience: :user,
                legacy_context: "magic_link",
                subject_strategy: :user_id
              },
              otp: %Definition{
                kind: :otp,
                storage: :ledgered,
                ttl: @ten_minutes,
                max_ttl: @thirty_minutes,
                audience: :user,
                legacy_context: nil,
                subject_strategy: :email_sha256
              },
              recovery: %Definition{
                kind: :recovery,
                storage: :ledgered,
                ttl: @one_day,
                max_ttl: @seven_days,
                audience: :admin,
                legacy_context: "recovery",
                subject_strategy: :user_id
              },
              access: %Definition{
                kind: :access,
                storage: :signed,
                ttl: @fifteen_minutes,
                max_ttl: @one_hour,
                audience: :device,
                signing_salt: "user_access_v1",
                subject_strategy: :device_id
              },
              session_refresh: %Definition{
                kind: :session_refresh,
                storage: :device_secret,
                ttl: @thirty_days,
                max_ttl: @ninety_days,
                audience: :device,
                subject_strategy: :device_id
              },
              channel_bootstrap: %Definition{
                kind: :channel_bootstrap,
                storage: :signed,
                ttl: @one_minute,
                max_ttl: 2 * @one_minute,
                audience: :device,
                signing_salt: "channel_bootstrap_v1",
                subject_strategy: :device_id
              },
              family_setup: %Definition{
                kind: :family_setup,
                storage: :ledgered,
                ttl: @three_days,
                max_ttl: @seven_days,
                audience: :registrant,
                legacy_context: "family_setup",
                subject_strategy: :none
              }
            })

  @legacy_kind_map %{
    invite: "invite",
    pair_qr: "pair_qr",
    pair_admin_code: "pair_admin_code",
    invite_registration: "invite_registration",
    passkey_registration: "passkey_registration",
    passkey_assertion: "passkey_assertion",
    magic_link: "magic_link",
    otp: "otp",
    recovery: "recovery",
    access: nil,
    session_refresh: "session_refresh",
    channel_bootstrap: nil,
    family_setup: "family_setup"
  }

  @doc "Returns the canonical policy for the provided token kind."
  @spec policy!(Famichat.Auth.Tokens.kind()) :: Definition.t()
  def policy!(kind) do
    policy_map()
    |> Map.fetch!(canonicalize_kind(kind))
    |> enforce_bounds()
  end

  @doc "Default TTL (seconds) for a token kind."
  @spec default_ttl(Famichat.Auth.Tokens.kind()) :: pos_integer()
  def default_ttl(kind), do: policy!(kind).ttl

  @doc "Maximum allowable TTL (seconds) for a token kind."
  @spec max_ttl(Famichat.Auth.Tokens.kind()) :: pos_integer()
  def max_ttl(kind), do: policy!(kind).max_ttl

  @doc "Audience associated with the token kind."
  @spec audience(Famichat.Auth.Tokens.kind()) :: audience()
  def audience(kind), do: policy!(kind).audience

  @doc "Legacy context string for the token kind, if any."
  @spec legacy_context(Famichat.Auth.Tokens.kind()) :: String.t() | nil
  def legacy_context(kind), do: policy!(kind).legacy_context

  @doc """
  Legacy string stored in the database for the provided token kind.
  """
  @spec legacy_kind_string(Famichat.Auth.Tokens.kind()) :: String.t() | nil
  def legacy_kind_string(kind) do
    canonical_kind = canonicalize_kind(kind)
    Map.fetch!(@legacy_kind_map, canonical_kind)
  end

  @doc "Raw policy map (kind => policy)."
  @spec policy_map() :: %{
          optional(Famichat.Auth.Tokens.kind()) => Definition.t()
        }
  def policy_map, do: unquote(@policies)

  defp canonicalize_kind(:passkey_reg), do: :passkey_registration
  defp canonicalize_kind(:passkey_assert), do: :passkey_assertion
  defp canonicalize_kind(:device_refresh), do: :session_refresh
  defp canonicalize_kind(kind), do: kind

  defp enforce_bounds(%Definition{} = policy) do
    ttl = min(policy.ttl, policy.max_ttl)
    %{policy | ttl: ttl}
  end
end
