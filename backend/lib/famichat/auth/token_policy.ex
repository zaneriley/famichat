defmodule Famichat.Auth.TokenPolicy.Policy do
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
          storage: Famichat.Auth.TokenPolicy.storage(),
          ttl: pos_integer(),
          max_ttl: pos_integer(),
          audience: atom(),
          legacy_context: String.t() | nil,
          signing_salt: String.t() | nil,
          subject_strategy: :none | {:user_id} | {:device_id} | {:email_sha256}
        }
end

defmodule Famichat.Auth.TokenPolicy do
  @moduledoc """
  Canonical policies for all authentication token kinds.

  The policy data lives here (domain layer) so that every caller — legacy
  or new — reads from a single source of truth.  Infrastructure modules
  receive a policy struct instead of redefining TTLs, audiences, or
  storage classes.
  """

  @typedoc "Storage backends supported by token issuance."
  @type storage :: :ledgered | :signed | :device_secret

  alias Famichat.Auth.TokenPolicy.Policy

  @policies Macro.escape(%{
              invite: %Policy{
                kind: :invite,
                storage: :ledgered,
                ttl: 7 * 24 * 60 * 60,
                max_ttl: 14 * 24 * 60 * 60,
                audience: :invitee,
                legacy_context: "invite",
                subject_strategy: :none
              },
              pair_qr: %Policy{
                kind: :pair_qr,
                storage: :ledgered,
                ttl: 10 * 60,
                max_ttl: 30 * 60,
                audience: :device,
                legacy_context: "pair",
                subject_strategy: :none
              },
              pair_admin_code: %Policy{
                kind: :pair_admin_code,
                storage: :ledgered,
                ttl: 10 * 60,
                max_ttl: 30 * 60,
                audience: :device,
                legacy_context: "pair",
                subject_strategy: :none
              },
              invite_registration: %Policy{
                kind: :invite_registration,
                storage: :signed,
                ttl: 10 * 60,
                max_ttl: 30 * 60,
                audience: :invitee,
                signing_salt: "invite_registration_v1",
                subject_strategy: {:user_id}
              },
              passkey_reg: %Policy{
                kind: :passkey_reg,
                storage: :ledgered,
                ttl: 10 * 60,
                max_ttl: 30 * 60,
                audience: :user,
                legacy_context: "passkey_register",
                subject_strategy: {:user_id}
              },
              passkey_assert: %Policy{
                kind: :passkey_assert,
                storage: :ledgered,
                ttl: 5 * 60,
                max_ttl: 15 * 60,
                audience: :user,
                legacy_context: "passkey_assert_challenge",
                subject_strategy: {:user_id}
              },
              magic_link: %Policy{
                kind: :magic_link,
                storage: :ledgered,
                ttl: 15 * 60,
                max_ttl: 60 * 60,
                audience: :user,
                legacy_context: "magic_link",
                subject_strategy: {:user_id}
              },
              otp: %Policy{
                kind: :otp,
                storage: :ledgered,
                ttl: 10 * 60,
                max_ttl: 30 * 60,
                audience: :user,
                legacy_context: nil,
                subject_strategy: {:email_sha256}
              },
              recovery: %Policy{
                kind: :recovery,
                storage: :ledgered,
                ttl: 24 * 60 * 60,
                max_ttl: 7 * 24 * 60 * 60,
                audience: :admin,
                legacy_context: "recovery",
                subject_strategy: {:user_id}
              },
              access: %Policy{
                kind: :access,
                storage: :signed,
                ttl: 15 * 60,
                max_ttl: 60 * 60,
                audience: :device,
                signing_salt: "user_access_v1",
                subject_strategy: {:device_id}
              },
              device_refresh: %Policy{
                kind: :device_refresh,
                storage: :device_secret,
                ttl: 30 * 24 * 60 * 60,
                max_ttl: 90 * 24 * 60 * 60,
                audience: :device,
                subject_strategy: {:device_id}
              }
            })

  @doc "Returns the canonical policy for the provided token kind."
  @spec policy!(Famichat.Auth.Tokens.kind()) :: Policy.t()
  def policy!(kind) do
    policy_map()
    |> Map.fetch!(kind)
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

  @doc "Storage backend that should handle the token kind."
  @spec storage(Famichat.Auth.Tokens.kind()) :: storage()
  def storage(kind), do: policy!(kind).storage

  @doc "Legacy context string used by historical helpers."
  @spec legacy_context(Famichat.Auth.Tokens.kind()) :: String.t() | nil
  def legacy_context(kind), do: policy!(kind).legacy_context

  @doc "Optional Phoenix.Token signing salt for signed kinds."
  @spec signing_salt(Famichat.Auth.Tokens.kind()) :: String.t() | nil
  def signing_salt(kind), do: policy!(kind).signing_salt

  @doc "Subject strategy that should be applied for the kind."
  @spec subject_strategy(Famichat.Auth.Tokens.kind()) ::
          :none | {:user_id} | {:device_id} | {:email_sha256}
  def subject_strategy(kind), do: policy!(kind).subject_strategy

  defp policy_map do
    unquote(@policies)
  end

  defp enforce_bounds(%Policy{ttl: ttl, max_ttl: max} = policy)
       when ttl > 0 and max >= ttl do
    policy
  end

  defp enforce_bounds(%Policy{kind: kind}) do
    raise ArgumentError,
          "token policy #{inspect(kind)} violates TTL bounds"
  end
end
