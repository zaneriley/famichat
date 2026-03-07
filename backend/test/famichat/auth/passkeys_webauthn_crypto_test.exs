defmodule Famichat.Auth.Passkeys.WebAuthnCryptoTest do
  @moduledoc """
  End-to-end cryptographic tests for passkey registration and assertion.

  These tests construct real WebAuthn registration and assertion payloads using
  real ECDSA P-256 cryptography — no mocking of Wax.register or Wax.authenticate.

  ## Payload construction

  WebAuthn registration requires:
  - attestationObject: CBOR-encoded map with "fmt", "attStmt", and "authData" keys
  - clientDataJSON: JSON string with "type", "challenge", and "origin" keys
  - credentialId: the credential ID bytes

  WebAuthn assertion requires:
  - authenticatorData: binary with rp_id_hash + flags + sign_count
  - clientDataJSON: JSON string with "type", "challenge", and "origin" keys
  - signature: ECDSA P-256 signature over authenticatorData || SHA256(clientDataJSON)
  - credentialId: the credential ID bytes

  ## RP configuration

  Tests use `origin: "http://localhost"` and `rp_id: "localhost"` which are set
  in the test config via `Application.get_env(:famichat, :webauthn)`.
  """

  use Famichat.DataCase, async: false

  import Ecto.Query, only: [from: 2]
  import Famichat.ChatFixtures

  alias Famichat.Accounts.Passkey
  alias Famichat.Auth.Passkeys
  alias Famichat.Repo

  @origin "http://localhost"
  @rp_id "localhost"

  # ---------------------------------------------------------------------------
  # Helpers — key generation and WebAuthn payload construction
  # ---------------------------------------------------------------------------

  # Generates an EC P-256 key pair. Returns {private_key, public_key_point} where
  # public_key_point is the uncompressed point (04 || x || y).
  defp generate_ec_keypair do
    {pub, priv} = :crypto.generate_key(:ecdh, :secp256r1)
    # pub is the uncompressed point: <<4, x::32, y::32>>
    {priv, pub}
  end

  # Builds a COSE key map (alg=-7, kty=2, crv=1) from raw EC public key point.
  # The public key point from :crypto is <<4, x::32, y::32>>.
  defp cose_key_from_point(<<4, x::binary-size(32), y::binary-size(32)>>) do
    %{
      1 => 2,
      # kty: EC2
      3 => -7,
      # alg: ES256
      -1 => 1,
      # crv: P-256
      -2 => x,
      # x coordinate
      -3 => y
      # y coordinate
    }
  end

  # Encodes the COSE key into CBOR binary suitable for use in authenticator data.
  defp encode_cose_key(cose_key) do
    # CBOR integer keys — CBOR.encode uses string keys by default for maps.
    # We need integer-keyed CBOR, so we build it manually using the cbor lib's
    # integer map encoding.
    CBOR.encode(cose_key)
  end

  # Builds the authenticator data binary for registration (with attested credential data).
  # Layout: rp_id_hash(32) + flags(1) + sign_count(4) + aaguid(16) +
  #         credential_id_length(2) + credential_id + cose_key_cbor
  defp build_auth_data_registration(credential_id, cose_key, sign_count) do
    rp_id_hash = :crypto.hash(:sha256, @rp_id)

    # flags: UP=1, UV=1, AT=1 (attested credential data present)
    # bit layout: ED AT 0 BE BS UV 0 UP
    # bits:       7  6  5  4  3  2  1  0
    # UP=bit0=1, UV=bit2=1, AT=bit6=1 → 0b01000101 = 0x45
    flags = 0x45

    aaguid = <<0::128>>
    cred_id_len = byte_size(credential_id)
    cose_key_cbor = encode_cose_key(cose_key)

    <<rp_id_hash::binary-size(32), flags::8,
      sign_count::unsigned-big-integer-32, aaguid::binary-size(16),
      cred_id_len::unsigned-big-integer-16,
      credential_id::binary-size(cred_id_len), cose_key_cbor::binary>>
  end

  # Builds authenticator data for assertion (no attested credential data).
  # Layout: rp_id_hash(32) + flags(1) + sign_count(4)
  defp build_auth_data_assertion(sign_count) do
    rp_id_hash = :crypto.hash(:sha256, @rp_id)
    # UP=1, UV=1, no AT flag → 0b00000101 = 0x05
    flags = 0x05

    <<rp_id_hash::binary-size(32), flags::8,
      sign_count::unsigned-big-integer-32>>
  end

  # Builds client data JSON for registration (type "webauthn.create").
  defp build_client_data_json_create(challenge_bytes) do
    challenge_b64 = Base.url_encode64(challenge_bytes, padding: false)

    Jason.encode!(%{
      "type" => "webauthn.create",
      "challenge" => challenge_b64,
      "origin" => @origin,
      "crossOrigin" => false
    })
  end

  # Builds client data JSON for assertion (type "webauthn.get").
  defp build_client_data_json_get(challenge_bytes) do
    challenge_b64 = Base.url_encode64(challenge_bytes, padding: false)

    Jason.encode!(%{
      "type" => "webauthn.get",
      "challenge" => challenge_b64,
      "origin" => @origin,
      "crossOrigin" => false
    })
  end

  # Builds an attestation object with "none" format (no attestation statement).
  defp build_attestation_object(auth_data) do
    att_obj = %{
      "fmt" => "none",
      "attStmt" => %{},
      "authData" => %CBOR.Tag{tag: :bytes, value: auth_data}
    }

    CBOR.encode(att_obj)
  end

  # Signs the assertion message: auth_data_bin || SHA256(client_data_json).
  defp sign_assertion(private_key, auth_data_bin, client_data_json_raw) do
    client_data_hash = :crypto.hash(:sha256, client_data_json_raw)
    message = auth_data_bin <> client_data_hash

    :crypto.sign(:ecdsa, :sha256, message, [private_key, :secp256r1])
  end

  # Builds a complete registration payload ready for Passkeys.register_passkey/1.
  defp build_registration_payload(challenge_handle, challenge_bytes) do
    {private_key, pub_point} = generate_ec_keypair()
    cose_key = cose_key_from_point(pub_point)
    credential_id = :crypto.strong_rand_bytes(32)

    auth_data =
      build_auth_data_registration(credential_id, cose_key, _sign_count = 1)

    client_data_json = build_client_data_json_create(challenge_bytes)
    attestation_object = build_attestation_object(auth_data)

    payload = %{
      "challenge_handle" => challenge_handle,
      "challenge" => Base.url_encode64(challenge_bytes, padding: false),
      "credential_id" => Base.encode64(credential_id, padding: false),
      "attestation_object" => Base.encode64(attestation_object, padding: false),
      "client_data_json" => Base.encode64(client_data_json, padding: false)
    }

    {payload, private_key, cose_key, credential_id}
  end

  # Builds a complete assertion payload ready for Passkeys.assert_passkey/1.
  defp build_assertion_payload(
         challenge_handle,
         challenge_bytes,
         credential_id,
         private_key,
         sign_count
       ) do
    auth_data_bin = build_auth_data_assertion(sign_count)
    client_data_json = build_client_data_json_get(challenge_bytes)
    signature = sign_assertion(private_key, auth_data_bin, client_data_json)

    %{
      "challenge_handle" => challenge_handle,
      "challenge" => Base.url_encode64(challenge_bytes, padding: false),
      "credential_id" => Base.encode64(credential_id, padding: false),
      "authenticator_data" => Base.encode64(auth_data_bin, padding: false),
      "client_data_json" => Base.encode64(client_data_json, padding: false),
      "signature" => Base.encode64(signature, padding: false)
    }
  end

  # Decodes a COSE key from the portable JSON format used by Fix 4.
  # String keys are converted to integers; base64 strings that decode cleanly
  # are treated as binary coordinate values (integers left as integers).
  defp decode_stored_cose_key(json_str) when is_binary(json_str) do
    json_str
    |> Jason.decode!()
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      int_key = String.to_integer(k)

      val =
        if is_binary(v) do
          case Base.decode64(v) do
            {:ok, bin} -> bin
            :error -> v
          end
        else
          v
        end

      Map.put(acc, int_key, val)
    end)
  end

  # Issues a registration challenge and extracts handle + raw challenge bytes.
  defp issue_registration_challenge(user) do
    {:ok, challenge_response} = Passkeys.issue_registration_challenge(user)
    handle = Map.fetch!(challenge_response, "challenge_handle")

    {:ok, challenge_record} = Passkeys.fetch_registration_challenge(handle)
    challenge_bytes = challenge_record.challenge

    {handle, challenge_bytes}
  end

  # Issues an assertion challenge and extracts handle + raw challenge bytes.
  defp issue_assertion_challenge(user) do
    {:ok, challenge_response} = Passkeys.issue_assertion_challenge(user, [])
    handle = Map.fetch!(challenge_response, "challenge_handle")

    {:ok, challenge_record} = Passkeys.fetch_assertion_challenge(handle)
    challenge_bytes = challenge_record.challenge

    {handle, challenge_bytes}
  end

  # Registers a passkey for a user and returns {passkey, private_key, credential_id}.
  defp register_passkey_for_user(user) do
    {handle, challenge_bytes} = issue_registration_challenge(user)

    {payload, private_key, _cose_key, credential_id} =
      build_registration_payload(handle, challenge_bytes)

    {:ok, passkey} = Passkeys.register_passkey(payload)
    {passkey, private_key, credential_id}
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  setup do
    # Override webauthn config for tests to use localhost
    Application.put_env(:famichat, :webauthn,
      rp_id: @rp_id,
      rp_name: "Famichat Test",
      origin: @origin
    )

    on_exit(fn ->
      Application.put_env(:famichat, :webauthn,
        rp_id: System.get_env("WEBAUTHN_RP_ID") || "localhost",
        rp_name: System.get_env("WEBAUTHN_RP_NAME") || "Famichat",
        origin: System.get_env("WEBAUTHN_ORIGIN") || "http://localhost"
      )
    end)

    %{user: user_fixture()}
  end

  # ---------------------------------------------------------------------------
  # 1. Registration with a valid COSE-encoded P-256 key succeeds
  # ---------------------------------------------------------------------------
  test "registration with valid COSE P-256 key succeeds", %{user: user} do
    {handle, challenge_bytes} = issue_registration_challenge(user)

    {payload, _private_key, cose_key, credential_id} =
      build_registration_payload(handle, challenge_bytes)

    assert {:ok, %Passkey{} = passkey} = Passkeys.register_passkey(payload)

    assert passkey.user_id == user.id
    assert passkey.credential_id == credential_id

    # The stored public key must round-trip to the original COSE key map.
    # Since Fix 4, keys are stored as portable JSON (not term_to_binary).
    # Decode by converting string keys back to integers and base64-decoding binary values.
    stored_cose_key = decode_stored_cose_key(passkey.public_key)
    assert stored_cose_key == cose_key

    assert passkey.sign_count == 1
  end

  # ---------------------------------------------------------------------------
  # 2. Assertion with a valid signature succeeds
  # ---------------------------------------------------------------------------
  test "assertion with valid signature succeeds", %{user: user} do
    {_passkey, private_key, credential_id} = register_passkey_for_user(user)

    {handle, challenge_bytes} = issue_assertion_challenge(user)

    payload =
      build_assertion_payload(
        handle,
        challenge_bytes,
        credential_id,
        private_key,
        2
      )

    assert {:ok, %{user: returned_user, passkey: returned_passkey}} =
             Passkeys.assert_passkey(payload)

    assert returned_user.id == user.id
    assert returned_passkey.credential_id == credential_id
    assert returned_passkey.sign_count == 2
  end

  # ---------------------------------------------------------------------------
  # 3. Assertion with a tampered signature is rejected
  # ---------------------------------------------------------------------------
  test "assertion with tampered signature returns error", %{user: user} do
    {_passkey, private_key, credential_id} = register_passkey_for_user(user)

    {handle, challenge_bytes} = issue_assertion_challenge(user)

    payload =
      build_assertion_payload(
        handle,
        challenge_bytes,
        credential_id,
        private_key,
        2
      )

    # Corrupt the last byte of the signature
    original_sig_b64 = payload["signature"]
    {:ok, original_sig} = Base.decode64(original_sig_b64, padding: false)

    tampered_sig =
      case original_sig do
        <<prefix::binary-size(byte_size(original_sig) - 1), last_byte>> ->
          <<prefix::binary, :erlang.bxor(last_byte, 0xFF)>>

        _ ->
          <<original_sig::binary, 0x00>>
      end

    tampered_payload =
      Map.put(payload, "signature", Base.encode64(tampered_sig, padding: false))

    result = Passkeys.assert_passkey(tampered_payload)

    assert {:error, reason} = result

    assert reason in [:invalid_signature, :invalid_challenge, :not_found] or
             match?({:rate_limited, _retry}, reason) or
             match?({:error, _}, result)
  end

  # ---------------------------------------------------------------------------
  # 4. Assertion with replayed sign_count is rejected
  # ---------------------------------------------------------------------------
  test "assertion with replayed sign_count returns :replayed", %{user: user} do
    {passkey, private_key, credential_id} = register_passkey_for_user(user)

    # Advance the stored sign_count to 10 so we can replay a lower value
    Repo.update_all(
      from(p in Passkey, where: p.id == ^passkey.id),
      set: [sign_count: 10]
    )

    {handle, challenge_bytes} = issue_assertion_challenge(user)

    # Use sign_count = 5 which is less than stored 10 → should be rejected
    payload =
      build_assertion_payload(
        handle,
        challenge_bytes,
        credential_id,
        private_key,
        5
      )

    assert {:error, :replayed} = Passkeys.assert_passkey(payload)
  end

  # ---------------------------------------------------------------------------
  # 5. Assertion with wrong origin is rejected
  # ---------------------------------------------------------------------------
  test "assertion with wrong origin returns error", %{user: user} do
    {_passkey, private_key, credential_id} = register_passkey_for_user(user)

    {handle, challenge_bytes} = issue_assertion_challenge(user)

    # Build client data with a different origin
    challenge_b64 = Base.url_encode64(challenge_bytes, padding: false)

    wrong_origin_client_data =
      Jason.encode!(%{
        "type" => "webauthn.get",
        "challenge" => challenge_b64,
        "origin" => "https://evil.example.com",
        "crossOrigin" => false
      })

    auth_data_bin = build_auth_data_assertion(2)

    # Sign with the wrong-origin client data (signature is over correct data
    # but origin in client_data_json is wrong)
    signature =
      sign_assertion(private_key, auth_data_bin, wrong_origin_client_data)

    tampered_payload = %{
      "challenge_handle" => handle,
      "challenge" => challenge_b64,
      "credential_id" => Base.encode64(credential_id, padding: false),
      "authenticator_data" => Base.encode64(auth_data_bin, padding: false),
      "client_data_json" =>
        Base.encode64(wrong_origin_client_data, padding: false),
      "signature" => Base.encode64(signature, padding: false)
    }

    result = Passkeys.assert_passkey(tampered_payload)

    assert {:error, reason} = result
    assert reason in [:invalid_origin, :invalid_signature, :invalid_challenge]
  end

  # ---------------------------------------------------------------------------
  # 6. Registration with arbitrary bytes as public_key is now rejected
  #    (the old code accepted any bytes as the "public key")
  # ---------------------------------------------------------------------------
  test "registration with arbitrary bytes instead of valid attestation object is rejected",
       %{user: user} do
    {handle, challenge_bytes} = issue_registration_challenge(user)

    garbage_bytes = :crypto.strong_rand_bytes(64)

    # Provide garbage as attestation_object — Wax will fail to parse it
    payload = %{
      "challenge_handle" => handle,
      "challenge" => Base.url_encode64(challenge_bytes, padding: false),
      "credential_id" =>
        Base.encode64(:crypto.strong_rand_bytes(32), padding: false),
      "attestation_object" => Base.encode64(garbage_bytes, padding: false),
      "client_data_json" =>
        Base.encode64(
          Jason.encode!(%{
            "type" => "webauthn.create",
            "challenge" => Base.url_encode64(challenge_bytes, padding: false),
            "origin" => @origin,
            "crossOrigin" => false
          }),
          padding: false
        )
    }

    assert {:error, _reason} = Passkeys.register_passkey(payload)
  end

  # ---------------------------------------------------------------------------
  # 7. Registration with wrong origin is rejected
  # ---------------------------------------------------------------------------
  test "registration with wrong origin is rejected", %{user: user} do
    {handle, challenge_bytes} = issue_registration_challenge(user)

    {private_key, pub_point} = generate_ec_keypair()
    cose_key = cose_key_from_point(pub_point)
    credential_id = :crypto.strong_rand_bytes(32)

    auth_data = build_auth_data_registration(credential_id, cose_key, 1)
    attestation_object = build_attestation_object(auth_data)

    # Use a different origin in client data
    wrong_client_data =
      Jason.encode!(%{
        "type" => "webauthn.create",
        "challenge" => Base.url_encode64(challenge_bytes, padding: false),
        "origin" => "https://evil.example.com",
        "crossOrigin" => false
      })

    payload = %{
      "challenge_handle" => handle,
      "challenge" => Base.url_encode64(challenge_bytes, padding: false),
      "credential_id" => Base.encode64(credential_id, padding: false),
      "attestation_object" => Base.encode64(attestation_object, padding: false),
      "client_data_json" => Base.encode64(wrong_client_data, padding: false)
    }

    assert {:error, _reason} = Passkeys.register_passkey(payload)

    # Suppress unused variable warning
    _ = private_key
  end

  # ---------------------------------------------------------------------------
  # Extras: sign_count = 0 on both sides (authenticator doesn't support it)
  # ---------------------------------------------------------------------------
  test "assertion with both sign_counts at 0 succeeds (authenticator does not track)",
       %{user: user} do
    # Register with sign_count = 0 (some authenticators don't implement it)
    {handle, challenge_bytes} = issue_registration_challenge(user)
    {private_key, pub_point} = generate_ec_keypair()
    cose_key = cose_key_from_point(pub_point)
    credential_id = :crypto.strong_rand_bytes(32)

    auth_data_reg = build_auth_data_registration(credential_id, cose_key, 0)
    client_data_json_reg = build_client_data_json_create(challenge_bytes)
    attestation_object = build_attestation_object(auth_data_reg)

    reg_payload = %{
      "challenge_handle" => handle,
      "challenge" => Base.url_encode64(challenge_bytes, padding: false),
      "credential_id" => Base.encode64(credential_id, padding: false),
      "attestation_object" => Base.encode64(attestation_object, padding: false),
      "client_data_json" => Base.encode64(client_data_json_reg, padding: false)
    }

    assert {:ok, %Passkey{sign_count: 0}} =
             Passkeys.register_passkey(reg_payload)

    {handle2, challenge_bytes2} = issue_assertion_challenge(user)

    # Assertion with sign_count = 0 when stored is 0 → should succeed
    auth_data_bin = build_auth_data_assertion(0)
    client_data_json = build_client_data_json_get(challenge_bytes2)
    signature = sign_assertion(private_key, auth_data_bin, client_data_json)

    assert_payload = %{
      "challenge_handle" => handle2,
      "challenge" => Base.url_encode64(challenge_bytes2, padding: false),
      "credential_id" => Base.encode64(credential_id, padding: false),
      "authenticator_data" => Base.encode64(auth_data_bin, padding: false),
      "client_data_json" => Base.encode64(client_data_json, padding: false),
      "signature" => Base.encode64(signature, padding: false)
    }

    assert {:ok, %{user: _, passkey: _}} =
             Passkeys.assert_passkey(assert_payload)
  end

  # ---------------------------------------------------------------------------
  # Challenge is consumed after successful registration (single-use enforcement)
  # ---------------------------------------------------------------------------
  test "challenge is consumed after successful registration — replay rejected",
       %{user: user} do
    {handle, challenge_bytes} = issue_registration_challenge(user)

    {payload, _private_key, _cose_key, _credential_id} =
      build_registration_payload(handle, challenge_bytes)

    assert {:ok, _passkey} = Passkeys.register_passkey(payload)

    # The challenge has been consumed. The second payload would need a fresh
    # challenge handle. Using the same handle must fail at the challenge fetch stage.
    # We cannot reuse the same credential_id either (unique constraint), so use
    # a fresh key pair but same (consumed) challenge handle.
    {handle2_payload, _, _, _} =
      build_registration_payload(handle, challenge_bytes)

    assert {:error, reason} = Passkeys.register_passkey(handle2_payload)
    assert reason in [:already_used, :invalid_challenge, :expired]
  end

  # ---------------------------------------------------------------------------
  # Security Fix 1 & 2: UV flag = false on assertion must be rejected
  # ---------------------------------------------------------------------------
  test "assertion with UV flag = false is rejected with :user_verification_required",
       %{user: user} do
    {_passkey, private_key, credential_id} = register_passkey_for_user(user)

    {handle, challenge_bytes} = issue_assertion_challenge(user)

    # Build authenticator data with UV flag cleared (bit 2 = 0).
    # UP=1, UV=0, no AT → 0b00000001 = 0x01
    rp_id_hash = :crypto.hash(:sha256, @rp_id)
    flags_no_uv = 0x01
    sign_count = 2

    auth_data_bin =
      <<rp_id_hash::binary-size(32), flags_no_uv::8,
        sign_count::unsigned-big-integer-32>>

    client_data_json = build_client_data_json_get(challenge_bytes)
    signature = sign_assertion(private_key, auth_data_bin, client_data_json)

    payload = %{
      "challenge_handle" => handle,
      "challenge" => Base.url_encode64(challenge_bytes, padding: false),
      "credential_id" => Base.encode64(credential_id, padding: false),
      "authenticator_data" => Base.encode64(auth_data_bin, padding: false),
      "client_data_json" => Base.encode64(client_data_json, padding: false),
      "signature" => Base.encode64(signature, padding: false)
    }

    assert {:error, :user_verification_required} =
             Passkeys.assert_passkey(payload)
  end

  # ---------------------------------------------------------------------------
  # Security Fix 4: COSE key round-trips correctly through portable JSON format
  # ---------------------------------------------------------------------------
  test "COSE key round-trips correctly through portable JSON storage format" do
    {_private_key, pub_point} = generate_ec_keypair()
    original_key = cose_key_from_point(pub_point)

    # Simulate encode → store → load → decode cycle
    encoded = encode_cose_key_for_test(original_key)

    # Must be valid JSON (not Erlang binary)
    assert String.starts_with?(encoded, "{")

    # Must decode back to the exact same map
    decoded = decode_stored_cose_key(encoded)
    assert decoded == original_key

    # Integer keys must survive the round-trip (COSE EC2 P-256 key structure)
    # kty=2 stored under key 1, alg=-7 stored under key 3, crv=1 under key -1
    assert Map.has_key?(decoded, 1)
    assert Map.has_key?(decoded, 3)
    assert Map.has_key?(decoded, -1)
    assert Map.has_key?(decoded, -2)
    assert Map.has_key?(decoded, -3)

    # Algorithm value must survive as integer
    assert decoded[3] == -7

    # Binary coordinate values must survive as binaries
    assert is_binary(decoded[-2])
    assert is_binary(decoded[-3])
    assert byte_size(decoded[-2]) == 32
    assert byte_size(decoded[-3]) == 32
  end

  # ---------------------------------------------------------------------------
  # Security Fix 4: insecure old path blocked — arbitrary bytes as public key
  # must not authenticate. This test proves that without real Wax.authenticate
  # crypto, the assertion path fails.
  # ---------------------------------------------------------------------------
  test "registration with arbitrary bytes as attestation_object is rejected",
       %{user: user} do
    {handle, challenge_bytes} = issue_registration_challenge(user)

    # Provide garbage as attestation_object — Wax.register will fail to parse CBOR.
    # This is the "if Wax crypto were bypassed, this test would fail" test.
    garbage = :crypto.strong_rand_bytes(64)

    payload = %{
      "challenge_handle" => handle,
      "challenge" => Base.url_encode64(challenge_bytes, padding: false),
      "credential_id" =>
        Base.encode64(:crypto.strong_rand_bytes(32), padding: false),
      "attestation_object" => Base.encode64(garbage, padding: false),
      "client_data_json" =>
        Base.encode64(
          Jason.encode!(%{
            "type" => "webauthn.create",
            "challenge" => Base.url_encode64(challenge_bytes, padding: false),
            "origin" => @origin,
            "crossOrigin" => false
          }),
          padding: false
        )
    }

    # Must fail — Wax performs real CBOR/attestation verification.
    # Without that, any bytes could be accepted as a passkey public key.
    assert {:error, _reason} = Passkeys.register_passkey(payload)
  end

  # Helper: encodes a COSE key using the same algorithm as encode_cose_key_json/1
  # in passkeys.ex, for use in round-trip tests.
  defp encode_cose_key_for_test(cose_key) when is_map(cose_key) do
    cose_key
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      key_str = Integer.to_string(k)
      val = if is_binary(v), do: Base.encode64(v), else: v
      Map.put(acc, key_str, val)
    end)
    |> Jason.encode!()
  end
end
