defmodule Famichat.Auth.Runtime.Tokens do
  @moduledoc "Deprecated shim. Use `Famichat.Auth.Tokens.Storage` instead."
  @deprecated "use Famichat.Auth.Tokens.Storage"

  defdelegate issue_ledgered(context, payload, opts \\ []),
    to: Famichat.Auth.Tokens.Storage

  defdelegate fetch_ledgered(context, raw_token),
    to: Famichat.Auth.Tokens.Storage

  defdelegate consume_ledgered(token),
    to: Famichat.Auth.Tokens.Storage

  defdelegate sign(payload, salt, opts \\ []),
    to: Famichat.Auth.Tokens.Storage

  defdelegate verify(token, salt, opts \\ []),
    to: Famichat.Auth.Tokens.Storage

  defdelegate issue_device_secret(opts \\ []),
    to: Famichat.Auth.Tokens.Storage

  defdelegate generate_refresh(opts \\ []),
    to: Famichat.Auth.Tokens.Storage

  defdelegate hash(raw),
    to: Famichat.Auth.Tokens.Storage
end
