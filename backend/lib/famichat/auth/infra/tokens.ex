defmodule Famichat.Auth.Infra.Tokens do
  @moduledoc """
  Infrastructure helpers that unify legacy token helpers with the new
  class/kind model introduced in the auth refactor.
  """

  alias Famichat.Accounts.Token
  alias __MODULE__.Spec

  defmodule Spec do
    @moduledoc """
    Internal description of a token kind.
    """

    @enforce_keys [:kind, :class]
    defstruct [
      :kind,
      :class,
      :legacy_context,
      :default_ttl,
      :audience,
      :signing_salt
    ]

    @type t :: %__MODULE__{
            kind: Famichat.Auth.Infra.Tokens.kind(),
            class: Famichat.Auth.Infra.Tokens.class(),
            legacy_context: String.t() | nil,
            default_ttl: pos_integer() | nil,
            audience: atom() | nil,
            signing_salt: String.t() | nil
          }
  end

  @typedoc "Enumerated token classes used during the refactor."
  @type class :: :ledgered | :signed | :device_secret

  @typedoc "Typed token kinds supported by Phase 2."
  @type kind ::
          :invite
          | :pair_qr
          | :pair_admin_code
          | :invite_registration
          | :passkey_reg
          | :passkey_assert
          | :magic_link
          | :otp
          | :recovery

  @classes [:ledgered, :signed, :device_secret]

  @kind_specs %{
    invite: %{
      class: :ledgered,
      legacy_context: "invite",
      default_ttl: 7 * 24 * 60 * 60,
      audience: :invitee
    },
    pair_qr: %{
      class: :ledgered,
      legacy_context: "pair",
      default_ttl: 10 * 60,
      audience: :device
    },
    pair_admin_code: %{
      class: :ledgered,
      legacy_context: "pair",
      default_ttl: 10 * 60,
      audience: :device
    },
    invite_registration: %{
      class: :signed,
      default_ttl: 10 * 60,
      signing_salt: "invite_registration_v1",
      audience: :invitee
    },
    passkey_reg: %{
      class: :ledgered,
      legacy_context: "passkey_register",
      default_ttl: 10 * 60,
      audience: :user
    },
    passkey_assert: %{
      class: :ledgered,
      legacy_context: "passkey_assert_challenge",
      default_ttl: 5 * 60,
      audience: :user
    },
    magic_link: %{
      class: :ledgered,
      legacy_context: "magic_link",
      default_ttl: 15 * 60,
      audience: :user
    },
    otp: %{
      class: :ledgered,
      legacy_context: nil,
      default_ttl: 10 * 60,
      audience: :user
    },
    recovery: %{
      class: :ledgered,
      legacy_context: "recovery",
      default_ttl: 24 * 60 * 60,
      audience: :user
    }
  }

  @doc """
  Returns all supported token classes.
  """
  @spec classes() :: [class()]
  def classes, do: @classes

  @doc """
  Returns true if `class` is a known token class.
  """
  @spec class?(term()) :: boolean()
  def class?(class), do: class in @classes

  @doc """
  Returns all supported token kinds.
  """
  @spec kinds() :: [kind()]
  def kinds, do: Map.keys(@kind_specs)

  @doc """
  Fetches the `Spec` struct for a given kind.

  Raises if the kind is unknown.
  """
  @spec spec!(kind()) :: Spec.t()
  def spec!(kind) do
    attrs =
      @kind_specs
      |> Map.fetch!(kind)
      |> Map.put(:kind, kind)

    struct!(Spec, attrs)
  end

  @doc """
  Returns the class for the provided kind.
  """
  @spec class_for(kind()) :: class()
  def class_for(kind) do
    spec!(kind).class
  end

  @doc """
  Returns the default TTL (in seconds) for a given kind.
  """
  @spec default_ttl(kind()) :: pos_integer() | nil
  def default_ttl(kind) do
    spec!(kind).default_ttl
  end

  @doc """
  Returns the default audience for the provided kind.
  """
  @spec default_audience(kind()) :: atom() | nil
  def default_audience(kind) do
    spec!(kind).audience
  end

  @doc """
  Resolves the legacy context string for a kind.

  For contexts that do not have a single canonical value (e.g. OTP),
  callers must supply a `:context` option.
  """
  @spec legacy_context(kind(), keyword()) :: String.t()
  def legacy_context(kind, opts \\ []) do
    case Keyword.get(opts, :context) do
      nil ->
        spec!(kind).legacy_context ||
          raise ArgumentError,
                "token kind #{inspect(kind)} requires explicit :context option"

      value when is_binary(value) ->
        value

      other ->
        raise ArgumentError,
              ":context must be a binary, got: #{inspect(other)}"
    end
  end

  @doc """
  Signs an access token using Phoenix.Token.
  """
  @spec sign_access(map(), String.t()) :: String.t()
  def sign_access(payload, salt) when is_map(payload) and is_binary(salt) do
    Phoenix.Token.sign(FamichatWeb.Endpoint, salt, payload)
  end

  @doc """
  Signs a token for signed kinds (currently invite registration).
  """
  @spec sign(kind(), term(), keyword()) :: String.t()
  def sign(kind, payload, opts \\ [])

  def sign(kind, payload, opts)
      when kind in [:invite_registration] do
    spec = spec!(kind)

    Phoenix.Token.sign(
      FamichatWeb.Endpoint,
      spec.signing_salt,
      payload,
      opts
    )
  end

  def sign(kind, _payload, _opts) do
    raise ArgumentError,
          "cannot sign token for #{inspect(kind)} (class #{inspect(class_for(kind))})"
  end

  @doc """
  Verifies a signed token, defaulting to the kind's TTL.
  """
  @spec verify(kind(), String.t(), keyword()) ::
          {:ok, term()}
          | {:error, :expired | :invalid | :missing}
  def verify(kind, token, opts \\ [])

  def verify(kind, token, opts)
      when kind in [:invite_registration] do
    spec = spec!(kind)
    max_age = Keyword.get(opts, :max_age, spec.default_ttl)

    Phoenix.Token.verify(
      FamichatWeb.Endpoint,
      spec.signing_salt,
      token,
      Keyword.put(opts, :max_age, max_age)
    )
  end

  def verify(kind, _token, _opts) do
    raise ArgumentError,
          "cannot verify token for #{inspect(kind)} (class #{inspect(class_for(kind))})"
  end

  @doc """
  Generates a device secret (raw value + hash).
  """
  @spec issue_device_secret(keyword()) :: {:ok, String.t(), binary()}
  def issue_device_secret(opts \\ []) do
    size = Keyword.get(opts, :size, 48)
    raw = :crypto.strong_rand_bytes(size) |> Base.url_encode64(padding: false)
    {:ok, raw, hash(raw)}
  end

  @doc """
  Generates a refresh token (raw value + hash).
  """
  @spec generate_refresh() :: {:ok, String.t(), binary()}
  def generate_refresh do
    issue_device_secret()
  end

  @doc """
  Hashes a raw token using the same algorithm as legacy helpers.
  """
  @spec hash(String.t()) :: binary()
  def hash(raw) when is_binary(raw), do: Token.hash_token(raw)
end
