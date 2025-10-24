defmodule Famichat.Accounts.Token do
  @moduledoc """
  Helpers for issuing and verifying user-scoped tokens backed by `user_tokens` table.
  """

  alias Famichat.Accounts.UserToken
  alias Famichat.Repo

  @hash_algorithm :sha256

  @doc """
  Generates a secure, url-safe token and stores its hash.

  Returns `{:ok, raw_token, %UserToken{}}` on success.
  """
  @spec issue(String.t(), map(), keyword()) ::
          {:ok, String.t(), UserToken.t()} | {:error, Ecto.Changeset.t()}
  def issue(context, payload, opts \\ [])
      when is_binary(context) and is_map(payload) do
    ttl = Keyword.fetch!(opts, :ttl)
    user_id = Keyword.get(opts, :user_id)
    kind = opts |> Keyword.get(:kind) |> maybe_string()
    audience = opts |> Keyword.get(:audience) |> maybe_string()
    subject_id = opts |> Keyword.get(:subject_id) |> maybe_string()
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, ttl, :second)

    raw_encoded =
      case Keyword.get(opts, :raw) do
        nil ->
          :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

        custom when is_binary(custom) ->
          custom
      end

    hash = hash_token(raw_encoded)

    changeset =
      UserToken.changeset(%UserToken{}, %{
        user_id: user_id,
        context: context,
        kind: kind,
        audience: audience,
        subject_id: subject_id,
        token_hash: hash,
        payload: payload,
        expires_at: expires_at
      })

    with {:ok, stored} <- Repo.insert(changeset) do
      {:ok, raw_encoded, stored}
    end
  end

  @doc """
  Loads an active token by context + raw token. Returns {:ok, token} or error tuple.
  """
  @spec fetch(String.t(), String.t()) ::
          {:ok, UserToken.t()} | {:error, :invalid | :expired | :used}
  def fetch(context, raw_token)
      when is_binary(context) and is_binary(raw_token) do
    hash = hash_token(raw_token)

    case Repo.get_by(UserToken, context: context, token_hash: hash) do
      %UserToken{} = token -> validate_token_active(token)
      nil -> {:error, :invalid}
    end
  end

  @doc """
  Marks a token as consumed.
  """
  @spec consume(UserToken.t()) ::
          {:ok, UserToken.t()} | {:error, Ecto.Changeset.t()}
  def consume(%UserToken{} = token) do
    token
    |> UserToken.changeset(%{used_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @spec fetch_by_id(Ecto.UUID.t()) ::
          {:ok, UserToken.t()} | {:error, :invalid | :expired | :used}
  def fetch_by_id(id) do
    case Repo.get(UserToken, id) do
      %UserToken{} = token -> validate_token_active(token)
      nil -> {:error, :invalid}
    end
  end

  defp validate_token_active(%UserToken{used_at: %DateTime{}}),
    do: {:error, :used}

  defp validate_token_active(%UserToken{expires_at: expires_at} = token) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :lt do
      {:error, :expired}
    else
      {:ok, token}
    end
  end

  defp maybe_string(nil), do: nil
  defp maybe_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_string(value) when is_binary(value), do: value
  defp maybe_string(value), do: to_string(value)

  @doc """
  Convenience to hash raw token string.
  """
  @spec hash_token(String.t()) :: binary()
  def hash_token(raw) when is_binary(raw) do
    :crypto.hash(@hash_algorithm, raw)
  end
end
