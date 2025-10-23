defmodule Famichat.Auth.Tokens do
  @moduledoc """
  Typed token facade that wraps the existing ledgered helpers while the
  refactor progresses.  This API is intentionally thin so the façade and
  legacy modules can migrate gradually.
  """

  alias Famichat.Accounts.Token
  alias Famichat.Accounts.UserToken
  alias Famichat.Auth.Infra.Tokens

  @typedoc "Options accepted when issuing tokens."
  @type issue_opts :: [
          ttl: pos_integer(),
          user_id: Ecto.UUID.t(),
          raw: String.t(),
          context: String.t()
        ]

  @typedoc "Options accepted when fetching tokens."
  @type fetch_opts :: [context: String.t()]

  @doc """
  Issues a token for the requested kind, delegating to the correct class.

  Ledgered tokens return `{:ok, raw, %UserToken{}}`. Signed tokens return
  `{:ok, token}`. Device secrets reuse the refresh helper and return
  `{:ok, raw, hash}`.
  """
  @spec issue(Tokens.kind(), map(), issue_opts()) ::
          {:ok, String.t(), UserToken.t()}
          | {:ok, String.t()}
          | {:ok, String.t(), binary()}
          | {:error, term()}
  def issue(kind, payload, opts \\ []) when is_map(payload) do
    case Tokens.class_for(kind) do
      :ledgered ->
        context = Tokens.legacy_context(kind, opts)

        token_opts =
          opts
          |> Keyword.delete(:context)
          |> Keyword.put_new(:ttl, Tokens.default_ttl(kind))

        Token.issue(context, payload, token_opts)

      :signed ->
        token = Tokens.sign(kind, payload, Keyword.delete(opts, :context))
        {:ok, token}

      :device_secret ->
        Tokens.issue_device_secret(opts)
    end
  end

  @doc """
  Fetches a ledgered token by kind. Signed/device-secret tokens do not have
  fetch semantics and will raise.
  """
  @spec fetch(Tokens.kind(), String.t(), fetch_opts()) ::
          {:ok, UserToken.t()} | {:error, :invalid | :expired | :used}
  def fetch(kind, raw_token, opts \\ []) when is_binary(raw_token) do
    case Tokens.class_for(kind) do
      :ledgered ->
        context = Tokens.legacy_context(kind, opts)
        Token.fetch(context, raw_token)

      class ->
        raise ArgumentError,
              "fetch/3 is not supported for #{inspect(class)} tokens"
    end
  end

  @doc """
  Marks a ledgered token as consumed.
  """
  @spec consume(UserToken.t()) ::
          {:ok, UserToken.t()} | {:error, Ecto.Changeset.t()}
  def consume(%UserToken{} = token), do: Token.consume(token)

  @doc """
  Signs a Phoenix token using the configured kind.
  """
  @spec sign(Tokens.kind(), term(), keyword()) :: String.t()
  def sign(kind, payload, opts \\ []) do
    Tokens.sign(kind, payload, opts)
  end

  @doc """
  Verifies a Phoenix token using the configured kind.
  """
  @spec verify(Tokens.kind(), String.t(), keyword()) ::
          {:ok, term()}
          | {:error, :expired | :invalid | :missing}
  def verify(kind, token, opts \\ []) do
    Tokens.verify(kind, token, opts)
  end

  @doc """
  Issues a device secret (raw + hash).
  """
  @spec issue_device_secret(keyword()) :: {:ok, String.t(), binary()}
  def issue_device_secret(opts \\ []), do: Tokens.issue_device_secret(opts)

  @doc """
  Convenience hash helper for raw tokens.
  """
  @spec hash(String.t()) :: binary()
  def hash(raw), do: Tokens.hash(raw)
end
