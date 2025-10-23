defmodule Famichat.Auth.Infra.TokensTest do
  use ExUnit.Case, async: true

  alias Famichat.Auth.Infra.Tokens

  describe "classes/0" do
    test "returns the supported classes" do
      assert MapSet.new(Tokens.classes()) ==
               MapSet.new([:device_secret, :ledgered, :signed])
    end
  end

  describe "spec!/1" do
    test "returns configuration for a kind" do
      spec = Tokens.spec!(:invite)

      assert spec.class == :ledgered
      assert spec.legacy_context == "invite"
      assert spec.default_ttl == 7 * 24 * 60 * 60
    end
  end

  describe "sign/3 + verify/3" do
    test "signs and verifies invite registration tokens with default ttl" do
      payload = %{"invite_token_id" => Ecto.UUID.generate()}

      token = Tokens.sign(:invite_registration, payload)

      assert {:ok, ^payload} = Tokens.verify(:invite_registration, token)
    end
  end

  describe "issue_device_secret/1" do
    test "returns raw value and matching hash" do
      assert {:ok, raw, hash} = Tokens.issue_device_secret()
      assert byte_size(raw) > 0
      assert hash == Tokens.hash(raw)
    end
  end

  describe "legacy_context/2" do
    test "falls back to the default context when available" do
      assert Tokens.legacy_context(:pair_qr) == "pair"
    end

    test "accepts explicit overrides" do
      context =
        Tokens.legacy_context(:passkey_reg,
          context: "passkey_register_challenge"
        )

      assert context == "passkey_register_challenge"
    end

    test "raises when an override is required" do
      assert_raise ArgumentError, fn -> Tokens.legacy_context(:otp) end

      assert Tokens.legacy_context(:otp, context: "otp:user") == "otp:user"
    end
  end
end
