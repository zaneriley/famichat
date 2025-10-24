defmodule Famichat.Auth.Tokens do
  @moduledoc """
  Public façade for token issuance and verification.

  Callers receive a single `Issue` struct regardless of storage backend,
  and all policy decisions (TTL, audience, storage) flow through
  `Famichat.Auth.TokenPolicy`.  Legacy code should call this module rather
  than reaching into infra helpers directly.
  """

  alias Famichat.Accounts.UserToken
  alias Famichat.Auth.Infra.Tokens, as: Infra
  alias Famichat.Auth.TokenPolicy
  alias Famichat.Auth.TokenPolicy.Policy

  @typedoc "Token kinds supported by the auth refactor."
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
          | :access
          | :device_refresh

  @typedoc "Options accepted when issuing tokens."
  @type issue_opts :: [
          ttl: pos_integer(),
          raw: String.t(),
          context: String.t()
        ]

  @typedoc "Options accepted when fetching tokens."
  @type fetch_opts :: [context: String.t()]

  defmodule Issue do
    @moduledoc "Unified return type for token issuance."

    @enforce_keys [:kind, :class, :raw, :issued_at]
    defstruct [
      :kind,
      :class,
      :raw,
      :hash,
      :record,
      :audience,
      :subject_id,
      :issued_at,
      :expires_at
    ]

    @type t :: %__MODULE__{
            kind: Famichat.Auth.Tokens.kind(),
            class: Famichat.Auth.TokenPolicy.storage(),
            raw: String.t(),
            hash: binary() | nil,
            record: UserToken.t() | nil,
            audience: atom() | nil,
            subject_id: term() | nil,
            issued_at: DateTime.t(),
            expires_at: DateTime.t() | nil
          }
  end

  @doc "Returns the default TTL for the provided kind."
  @spec default_ttl(kind()) :: pos_integer()
  def default_ttl(kind), do: TokenPolicy.default_ttl(kind)

  @doc "Returns the maximum TTL for the provided kind."
  @spec max_ttl(kind()) :: pos_integer()
  def max_ttl(kind), do: TokenPolicy.max_ttl(kind)

  @doc """
  Issues a token for the requested kind and returns a unified `Issue`
  struct. The storage backend is selected automatically from the policy.
  """
  @spec issue(kind(), map(), issue_opts()) ::
          {:ok, Issue.t()} | {:error, term()}
  def issue(kind, payload, opts \\ []) when is_map(payload) do
    policy = TokenPolicy.policy!(kind)
    opts_with_ttl = Keyword.put_new(opts, :ttl, policy.ttl)

    kind
    |> do_issue(policy, payload, opts_with_ttl)
    |> with_telemetry(:issued, policy)
  end

  defp do_issue(kind, %Policy{storage: :ledgered} = policy, payload, opts) do
    context = ledgered_context(policy, opts)

    token_opts =
      opts
      |> Keyword.delete(:context)

    case Infra.issue_ledgered(context, payload, token_opts) do
      {:ok, raw, %UserToken{} = record} ->
        {:ok,
         %Issue{
           kind: kind,
           class: :ledgered,
           raw: raw,
           record: record,
           audience: policy.audience,
           issued_at: to_datetime(record.inserted_at),
           expires_at: to_datetime(record.expires_at)
         }}

      other ->
        other
    end
  end

  defp do_issue(kind, %Policy{storage: :signed} = policy, payload, opts) do
    salt = policy.signing_salt || raise_missing_salt(kind)
    max_age = Keyword.fetch!(opts, :ttl)
    token = Infra.sign(payload, salt, Keyword.delete(opts, :ttl))
    issued_at = DateTime.utc_now()

    {:ok,
     %Issue{
       kind: kind,
       class: :signed,
       raw: token,
       audience: policy.audience,
       issued_at: issued_at,
       expires_at: DateTime.add(issued_at, max_age, :second)
     }}
  end

  defp do_issue(kind, %Policy{storage: :device_secret} = policy, _payload, opts) do
    case Infra.issue_device_secret(opts) do
      {:ok, raw, hash} ->
        issued_at = DateTime.utc_now()

        {:ok,
         %Issue{
           kind: kind,
           class: :device_secret,
           raw: raw,
           hash: hash,
           audience: policy.audience,
           issued_at: issued_at,
           expires_at:
             DateTime.add(issued_at, Keyword.fetch!(opts, :ttl), :second)
         }}

      other ->
        other
    end
  end

  @doc """
  Fetches a ledgered token by kind. Signed/device-secret tokens do not have
  fetch semantics and will raise.
  """
  @spec fetch(kind(), String.t(), fetch_opts()) ::
          {:ok, UserToken.t()} | {:error, :invalid | :expired | :used}
  def fetch(kind, raw_token, opts \\ []) when is_binary(raw_token) do
    policy = TokenPolicy.policy!(kind)

    case policy.storage do
      :ledgered ->
        context = ledgered_context(policy, opts)
        Infra.fetch_ledgered(context, raw_token)

      storage ->
        raise ArgumentError,
              "fetch/3 is not supported for #{inspect(storage)} tokens"
    end
  end

  @doc """
  Marks a ledgered token as consumed.
  """
  @spec consume(UserToken.t()) ::
          {:ok, UserToken.t()} | {:error, Ecto.Changeset.t()}
  def consume(%UserToken{} = token), do: Infra.consume_ledgered(token)

  @doc """
  Signs a Phoenix token using the configured kind.
  """
  @spec sign(kind(), term(), keyword()) :: String.t()
  def sign(kind, payload, opts \\ []) do
    policy = TokenPolicy.policy!(kind)

    case policy.storage do
      :signed ->
        salt = policy.signing_salt || raise_missing_salt(kind)
        Infra.sign(payload, salt, opts)

      storage ->
        raise ArgumentError,
              "sign/3 is not supported for #{inspect(storage)} tokens"
    end
  end

  @doc """
  Verifies a Phoenix token using the configured kind.
  """
  @spec verify(kind(), String.t(), keyword()) ::
          {:ok, term()} | {:error, :expired | :invalid | :missing}
  def verify(kind, token, opts \\ []) do
    policy = TokenPolicy.policy!(kind)

    case policy.storage do
      :signed ->
        salt = policy.signing_salt || raise_missing_salt(kind)
        max_age = Keyword.get(opts, :max_age, policy.ttl)
        Infra.verify(token, salt, Keyword.put(opts, :max_age, max_age))

      storage ->
        raise ArgumentError,
              "verify/3 is not supported for #{inspect(storage)} tokens"
    end
  end

  @doc """
  Generates a device secret (raw + hash).
  """
  @spec issue_device_secret(keyword()) :: {:ok, String.t(), binary()}
  def issue_device_secret(opts \\ []), do: Infra.issue_device_secret(opts)

  @doc """
  Convenience hash helper for raw tokens.
  """
  @spec hash(String.t()) :: binary()
  def hash(raw), do: Infra.hash(raw)

  defp ledgered_context(%Policy{legacy_context: nil}, opts) do
    case Keyword.get(opts, :context) do
      value when is_binary(value) ->
        value

      nil ->
        raise ArgumentError, "token kind requires explicit :context option"

      other ->
        raise ArgumentError, ":context must be a binary, got: #{inspect(other)}"
    end
  end

  defp ledgered_context(%Policy{legacy_context: context}, opts) do
    Keyword.get(opts, :context, context)
  end

  defp to_datetime(%NaiveDateTime{} = naive) do
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(nil), do: nil

  defp raise_missing_salt(kind) do
    raise ArgumentError,
          "token kind #{inspect(kind)} requires a signing salt but none is configured"
  end

  defp with_telemetry({:ok, %Issue{} = issue} = ok, action, policy) do
    :telemetry.execute(
      [:famichat, :auth, :token, action],
      %{count: 1},
      %{
        kind: issue.kind,
        class: issue.class,
        audience: policy.audience,
        ttl: policy.ttl
      }
    )

    ok
  end

  defp with_telemetry(other, _action, _policy), do: other
end
