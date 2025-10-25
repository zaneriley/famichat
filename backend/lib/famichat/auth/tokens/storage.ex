defmodule Famichat.Auth.Tokens.Storage do
  @moduledoc """
  Low-level helpers for ledgered token issuance, hashing, and device
  secrets. Domain policy (kind → storage/ttl/etc.) lives in
  `Famichat.Auth.Tokens.Policy`; this module stays focused on interacting
  with persistence and crypto helpers.
  """

  alias Ecto.Changeset
  alias Famichat.Accounts.UserToken
  alias Famichat.Repo

  @hash_algorithm :sha256

  @doc """
  Issues a ledgered token row in `user_tokens`, returning the raw value together
  with the stored record.
  """
  @spec issue_ledgered(String.t(), map(), keyword()) ::
          {:ok, String.t(), UserToken.t()} | {:error, term()}
  def issue_ledgered(context, payload, opts \\ [])
      when is_binary(context) and is_map(payload) do
    ttl = Keyword.fetch!(opts, :ttl)
    user_id = Keyword.get(opts, :user_id)
    kind = normalize_opt(opts, :kind)
    audience = normalize_opt(opts, :audience)
    subject_id = normalize_opt(opts, :subject_id)

    now = DateTime.utc_now()
    expires_at = DateTime.add(now, ttl, :second)

    raw =
      case Keyword.get(opts, :raw) do
        nil -> generate_raw()
        custom when is_binary(custom) -> custom
      end

    token_hash = hash(raw)

    changeset =
      UserToken.changeset(%UserToken{}, %{
        user_id: user_id,
        context: context,
        kind: kind,
        audience: audience,
        subject_id: subject_id,
        token_hash: token_hash,
        payload: payload,
        expires_at: expires_at
      })

    case Repo.insert(changeset) do
      {:ok, stored} -> {:ok, raw, stored}
      other -> other
    end
  end

  @doc """
  Fetches an active ledgered token by context + raw value.
  """
  @spec fetch_ledgered(String.t(), String.t()) ::
          {:ok, UserToken.t()} | {:error, :invalid | :expired | :used}
  def fetch_ledgered(context, raw_token)
      when is_binary(context) and is_binary(raw_token) do
    hash = hash(raw_token)

    case Repo.get_by(UserToken, context: context, token_hash: hash) do
      %UserToken{} = token -> validate_active(token)
      nil -> {:error, :invalid}
    end
  end

  @doc """
  Fetches an active ledgered token by database id.
  """
  @spec fetch_ledgered_by_id(Ecto.UUID.t()) ::
          {:ok, UserToken.t()} | {:error, :invalid | :expired | :used}
  def fetch_ledgered_by_id(id) do
    case Repo.get(UserToken, id) do
      %UserToken{} = token -> validate_active(token)
      nil -> {:error, :invalid}
    end
  end

  @doc """
  Marks a ledgered token as consumed.
  """
  @spec consume_ledgered(UserToken.t()) ::
          {:ok, UserToken.t()} | {:error, Changeset.t()}
  def consume_ledgered(%UserToken{} = token) do
    token
    |> UserToken.changeset(%{used_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Signs a Phoenix token with the provided salt.
  """
  @spec sign(term(), String.t(), keyword()) :: String.t()
  def sign(payload, salt, opts \\ []) when is_binary(salt) do
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
  Generates a refresh token (raw + hash). Kept for backwards compatibility with
  session helpers.
  """
  @spec generate_refresh(keyword()) :: {:ok, String.t(), binary()}
  def generate_refresh(opts \\ []), do: issue_device_secret(opts)

  @doc """
  Hashes a raw token using the canonical algorithm.
  """
  @spec hash(String.t()) :: binary()
  def hash(raw) when is_binary(raw) do
    :crypto.hash(@hash_algorithm, raw)
  end

  ## Helpers -----------------------------------------------------------------

  defp generate_raw do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp validate_active(%UserToken{used_at: %DateTime{}}), do: {:error, :used}

  defp validate_active(%UserToken{expires_at: expires_at} = token) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :lt do
      {:error, :expired}
    else
      {:ok, token}
    end
  end

  defp normalize_opt(opts, key) do
    case Keyword.get(opts, key) do
      nil -> nil
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end
  end
end
