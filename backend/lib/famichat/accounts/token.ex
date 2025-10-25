defmodule Famichat.Accounts.Token do
  @moduledoc "Deprecated shim. Use `Famichat.Auth.Tokens.Storage` instead."
  @deprecated "use Famichat.Auth.Tokens.Storage"

  alias Famichat.Auth.Tokens.Storage

  @spec issue(String.t(), map(), keyword()) ::
          {:ok, String.t(), Famichat.Accounts.UserToken.t()} | {:error, term()}
  defdelegate issue(context, payload, opts \\ []),
    to: Storage,
    as: :issue_ledgered

  @spec fetch(String.t(), String.t()) ::
          {:ok, Famichat.Accounts.UserToken.t()}
          | {:error, :invalid | :expired | :used}
  defdelegate fetch(context, raw_token),
    to: Storage,
    as: :fetch_ledgered

  @spec fetch_by_id(Ecto.UUID.t()) ::
          {:ok, Famichat.Accounts.UserToken.t()}
          | {:error, :invalid | :expired | :used}
  defdelegate fetch_by_id(id),
    to: Storage,
    as: :fetch_ledgered_by_id

  @spec consume(Famichat.Accounts.UserToken.t()) ::
          {:ok, Famichat.Accounts.UserToken.t()} | {:error, Ecto.Changeset.t()}
  defdelegate consume(token),
    to: Storage,
    as: :consume_ledgered

  @spec hash_token(String.t()) :: binary()
  defdelegate hash_token(raw),
    to: Storage,
    as: :hash
end
