defmodule Famichat.Auth.Infra.Tokens do
  @moduledoc "Deprecated alias; use `Famichat.Auth.Runtime.Tokens`."
  @deprecated "use Famichat.Auth.Runtime.Tokens"

  defdelegate issue_ledgered(context, payload, opts \\ []),
    to: Famichat.Auth.Runtime.Tokens

  defdelegate fetch_ledgered(context, raw_token),
    to: Famichat.Auth.Runtime.Tokens

  defdelegate consume_ledgered(token),
    to: Famichat.Auth.Runtime.Tokens

  defdelegate sign(payload, salt, opts \\ []),
    to: Famichat.Auth.Runtime.Tokens

  defdelegate verify(token, salt, opts \\ []),
    to: Famichat.Auth.Runtime.Tokens

  defdelegate issue_device_secret(opts \\ []),
    to: Famichat.Auth.Runtime.Tokens

  defdelegate generate_refresh(opts \\ []),
    to: Famichat.Auth.Runtime.Tokens

  defdelegate hash(raw),
    to: Famichat.Auth.Runtime.Tokens
end
