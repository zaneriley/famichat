defmodule Famichat.Auth do
  @moduledoc """
  Public authentication façade exposing sessions, tokens, and passkeys.

  Use these functions from application code instead of calling individual
  context modules directly. Context modules remain available for
  fine-grained control, while this module provides the curated surface
  area expected by external callers.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat.Accounts,
      Famichat.Auth.Passkeys,
      Famichat.Auth.Sessions,
      Famichat.Auth.Tokens
    ]

  alias Famichat.Accounts.User
  alias Famichat.Auth.Passkeys
  alias Famichat.Auth.Sessions
  alias Famichat.Auth.Tokens

  ## Sessions -----------------------------------------------------------------

  defdelegate start_session(user, device_info, opts \\ []), to: Sessions
  defdelegate refresh_session(device_id, refresh_token), to: Sessions
  defdelegate revoke_device(user_id, device_id), to: Sessions
  defdelegate verify_access_token(token), to: Sessions
  defdelegate require_reauth?(user_id, device_id, action), to: Sessions

  ## Passkeys -----------------------------------------------------------------

  defdelegate issue_registration_challenge(user, opts \\ []), to: Passkeys

  def issue_assertion_challenge(identifier)
      when is_map(identifier) and not is_struct(identifier) do
    Passkeys.issue_assertion_challenge(identifier)
  end

  def issue_assertion_challenge(identifier) when is_binary(identifier) do
    Passkeys.issue_assertion_challenge(identifier)
  end

  def issue_assertion_challenge(%User{} = user, opts \\ []) do
    Passkeys.issue_assertion_challenge(user, opts)
  end

  defdelegate fetch_registration_challenge(handle), to: Passkeys
  defdelegate fetch_assertion_challenge(handle), to: Passkeys
  defdelegate consume_challenge(challenge), to: Passkeys

  ## Tokens -------------------------------------------------------------------

  defdelegate issue(kind, payload, opts \\ []), to: Tokens
  defdelegate fetch(kind, raw, opts \\ []), to: Tokens
  defdelegate consume(user_token), to: Tokens
  defdelegate sign(kind, payload, opts \\ []), to: Tokens
  defdelegate verify(kind, token, opts \\ []), to: Tokens
end
