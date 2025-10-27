defmodule Famichat.Accounts do
  @moduledoc """
  Compatibility façade that forwards legacy `Famichat.Accounts.*` calls to the
  new authentication contexts. Callers should migrate to `Famichat.Auth.*`
  directly; these helpers remain temporarily for backwards compatibility.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat
    ]

  alias Famichat.Accounts.User
  alias Famichat.Auth.{Identity, Onboarding, Passkeys, Recovery, Sessions}

  # Onboarding -----------------------------------------------------------------

  @deprecated "use Famichat.Auth.Onboarding.issue_invite/3"
  defdelegate issue_invite(inviter_id, email, payload), to: Onboarding

  @deprecated "use Famichat.Auth.Onboarding.accept_invite/1"
  defdelegate accept_invite(raw_token), to: Onboarding

  @deprecated "use Famichat.Auth.Onboarding.redeem_pairing/1"
  def redeem_pairing_token(raw_token) do
    Onboarding.redeem_pairing(raw_token)
  end

  @deprecated "use Famichat.Auth.Onboarding.reissue_pairing/2"
  defdelegate reissue_pairing(requester_id, invite_raw), to: Onboarding

  @deprecated "use Famichat.Auth.Onboarding.complete_registration/2"
  def register_user_from_invite(registration_token, attrs) do
    Onboarding.complete_registration(registration_token, attrs)
  end

  # Passkeys -------------------------------------------------------------------

  @deprecated "use Famichat.Auth.Passkeys.exchange_registration_token/1"
  defdelegate exchange_passkey_register_token(raw_token),
    to: Passkeys,
    as: :exchange_registration_token

  @deprecated "use Famichat.Auth.Passkeys.issue_registration_challenge/2"
  def issue_passkey_registration_challenge(%User{} = user) do
    Passkeys.issue_registration_challenge(user)
  end

  @deprecated "use Famichat.Auth.Passkeys.issue_registration_challenge/2"
  def issue_passkey_registration_challenge(user_id) when is_binary(user_id) do
    with {:ok, user} <- Identity.fetch_user(user_id) do
      Passkeys.issue_registration_challenge(user)
    end
  end

  @deprecated "use Famichat.Auth.Passkeys.issue_assertion_challenge/1"
  def issue_passkey_assertion_challenge(identifier) do
    Passkeys.issue_assertion_challenge(identifier)
  end

  @deprecated "use Famichat.Auth.Passkeys.register_passkey/1"
  defdelegate register_passkey(attestation_payload), to: Passkeys

  @deprecated "use Famichat.Auth.Passkeys.assert_passkey/1"
  defdelegate assert_passkey(payload), to: Passkeys

  # Sessions -------------------------------------------------------------------

  @deprecated "use Famichat.Auth.Sessions.start_session/3"
  def start_session(user, device_info, opts \\ []) do
    Sessions.start_session(user, device_info, opts)
  end

  @deprecated "use Famichat.Auth.Sessions.refresh_session/2"
  defdelegate refresh_session(device_id, raw_refresh), to: Sessions

  @deprecated "use Famichat.Auth.Sessions.revoke_device/2"
  defdelegate revoke_device(user_id, device_id), to: Sessions

  @deprecated "use Famichat.Auth.Sessions.verify_access_token/1"
  defdelegate verify_access_token(token), to: Sessions

  @deprecated "use Famichat.Auth.Sessions.require_reauth?/3"
  defdelegate require_reauth?(user_id, device_id, action), to: Sessions

  # Identity / tokens ----------------------------------------------------------

  @deprecated "use Famichat.Auth.Identity.issue_magic_link/1"
  defdelegate issue_magic_link(email), to: Identity

  @deprecated "use Famichat.Auth.Identity.redeem_magic_link/1"
  defdelegate redeem_magic_link(raw_token), to: Identity

  @deprecated "use Famichat.Auth.Identity.issue_otp/1"
  defdelegate issue_otp(email), to: Identity

  @deprecated "use Famichat.Auth.Identity.verify_otp/2"
  defdelegate verify_otp(email, code), to: Identity

  @deprecated "use Famichat.Auth.Recovery.issue_recovery/2"
  defdelegate issue_recovery(admin_id, user_id), to: Recovery

  @deprecated "use Famichat.Auth.Recovery.redeem_recovery/1"
  defdelegate redeem_recovery(token), to: Recovery
end
