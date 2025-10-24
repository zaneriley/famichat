defmodule Famichat.Auth.Authenticators do
  @moduledoc """
  Deprecated shim. Use `Famichat.Auth.Passkeys` instead.
  """
  @deprecated "use Famichat.Auth.Passkeys"

  defdelegate issue_registration_challenge(user, opts \\ []),
    to: Famichat.Auth.Passkeys

  defdelegate issue_assertion_challenge(user, opts \\ []),
    to: Famichat.Auth.Passkeys

  defdelegate fetch_registration_challenge(handle),
    to: Famichat.Auth.Passkeys

  defdelegate fetch_assertion_challenge(handle),
    to: Famichat.Auth.Passkeys

  defdelegate consume_challenge(challenge),
    to: Famichat.Auth.Passkeys
end
