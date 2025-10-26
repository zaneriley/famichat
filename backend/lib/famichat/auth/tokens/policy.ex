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
  """

  @typedoc "Storage backends supported by token issuance."
  @type storage :: :ledgered | :signed | :device_secret

  alias Famichat.Auth.Tokens.Policy.Definition

  @policies Macro.escape(%{
              invite: %Definition{
                kind: :invite,
                storage: :ledgered,
                ttl: 7 * 24 * 60 * 60,
                max_ttl: 14 * 24 * 60 * 60,
                audience: :invitee,
                legacy_context: "invite",
                subject_strategy: :none
              },
              pair_qr: %Definition{
                kind: :pair_qr,
                storage: :ledgered,
                ttl: 10 * 60,
                max_ttl: 30 * 60,
                audience: :device,
                legacy_context: "pair",
                subject_strategy: :none
              },
              pair_admin_code: %Definition{
                kind: :pair_admin_code,
                storage: :ledgered,
                ttl: 10 * 60,
                max_ttl: 30 * 60,
                audience: :device,
                legacy_context: "pair",
                subject_strategy: :none
              },
              invite_registration: %Definition{
                kind: :invite_registration,
                storage: :signed,
                ttl: 10 * 60,
                max_ttl: 30 * 60,
                audience: :invitee,
                signing_salt: "invite_registration_v1",
                subject_strategy: :user_id
              },
              passkey_registration: %Definition{
                kind: :passkey_registration,
                storage: :ledgered,
                ttl: 10 * 60,
                max_ttl: 30 * 60,
                audience: :user,
                legacy_context: "passkey_register",
                subject_strategy: :user_id
              },
              passkey_assertion: %Definition{
                kind: :passkey_assertion,
                storage: :ledgered,
                ttl: 5 * 60,
                max_ttl: 15 * 60,
                audience: :user,
                legacy_context: "passkey_assert_challenge",
                subject_strategy: :user_id
              },
              magic_link: %Definition{
                kind: :magic_link,
                storage: :ledgered,
                ttl: 15 * 60,
                max_ttl: 60 * 60,
                audience: :user,
                legacy_context: "magic_link",
                subject_strategy: :user_id
              },
              otp: %Definition{
                kind: :otp,
                storage: :ledgered,
                ttl: 10 * 60,
                max_ttl: 30 * 60,
                audience: :user,
                legacy_context: nil,
                subject_strategy: :email_sha256
              },
              recovery: %Definition{
                kind: :recovery,
                storage: :ledgered,
                ttl: 24 * 60 * 60,
                max_ttl: 7 * 24 * 60 * 60,
                audience: :admin,
                legacy_context: "recovery",
                subject_strategy: :user_id
              },
              access: %Definition{
                kind: :access,
                storage: :signed,
                ttl: 15 * 60,
                max_ttl: 60 * 60,
                audience: :device,
                signing_salt: "user_access_v1",
                subject_strategy: :device_id
              },
              session_refresh: %Definition{
                kind: :session_refresh,
                storage: :device_secret,
                ttl: 30 * 24 * 60 * 60,
                max_ttl: 90 * 24 * 60 * 60,
                audience: :device,
                subject_strategy: :device_id
              }
            })

  @legacy_kind_map %{
    invite: "invite",
    pair_qr: "pair_qr",
    pair_admin_code: "pair_admin_code",
    invite_registration: "invite_registration",
    passkey_registration: "passkey_reg",
    passkey_assertion: "passkey_assert",
    magic_link: "magic_link",
    otp: "otp",
    recovery: "recovery",
    access: nil,
    session_refresh: "device_refresh"
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
  @spec audience(Famichat.Auth.Tokens.kind()) :: atom()
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
