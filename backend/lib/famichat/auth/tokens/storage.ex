defmodule Famichat.Auth.Tokens.Storage do
  @moduledoc """
  Low-level helpers for ledgered token issuance, hashing, and device
  secrets.  Domain policy (kind → storage/ttl/etc.) lives in
  `Famichat.Auth.Tokens.Policy`; this module stays focused on interacting
  with the existing persistence and crypto helpers.
  """

  alias Famichat.Accounts.Token
  alias Famichat.Accounts.UserToken

  @doc """
  Issues a ledgered token using the legacy `user_tokens` helpers.
  """
  @spec issue_ledgered(String.t(), map(), keyword()) ::
          {:ok, String.t(), UserToken.t()} | {:error, term()}
  def issue_ledgered(context, payload, opts \\ []) when is_binary(context) do
    Token.issue(context, payload, opts)
  end

  @doc """
  Fetches a ledgered token by context + raw value.
  """
  @spec fetch_ledgered(String.t(), String.t()) ::
          {:ok, UserToken.t()} | {:error, :invalid | :expired | :used}
  def fetch_ledgered(context, raw_token)
      when is_binary(context) and is_binary(raw_token) do
    Token.fetch(context, raw_token)
  end

  @doc """
  Marks a ledgered token as consumed.
  """
  @spec consume_ledgered(UserToken.t()) ::
          {:ok, UserToken.t()} | {:error, Ecto.Changeset.t()}
  def consume_ledgered(%UserToken{} = token), do: Token.consume(token)

  @doc """
  Signs a Phoenix token with the provided salt.
  """
  @spec sign(term(), String.t(), keyword()) :: String.t()
  def sign(payload, salt, opts \\ [])
      when is_binary(salt) do
    Phoenix.Token.sign(FamichatWeb.Endpoint, salt, payload, opts)
  end

  @doc """
  Verifies a Phoenix token with the provided salt.
  """
  @spec verify(String.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, :expired | :invalid | :missing}
  def verify(token, salt, opts \\ [])
      when is_binary(token) and is_binary(salt) do
    Phoenix.Token.verify(FamichatWeb.Endpoint, salt, token, opts)
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
  Generates a refresh token (raw + hash). Kept for backwards-compatibility
  with session helpers.
  """
  @spec generate_refresh(keyword()) :: {:ok, String.t(), binary()}
  def generate_refresh(opts \\ []) do
    issue_device_secret(opts)
  end

  @doc """
  Hashes a raw token using the same algorithm as legacy helpers.
  """
  @spec hash(String.t()) :: binary()
  def hash(raw) when is_binary(raw), do: Token.hash_token(raw)
end
