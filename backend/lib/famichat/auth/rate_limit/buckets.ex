defmodule Famichat.Auth.RateLimit.Buckets do
  @moduledoc "Canonical auth rate limit buckets."

  @type t ::
          :"invite.issue"
          | :"invite.accept"
          | :"pairing.redeem"
          | :"pairing.reissue"
          | :"passkey.registration"
          | :"passkey.assertion"
          | :"session.refresh"
          | :"magic_link.issue"
          | :"magic_link.redeem"
          | :"otp.issue"
          | :"otp.verify"
          | :"recovery.issue"
          | :"recovery.redeem"
end
