defmodule Famichat.Crypto.MLS.SnapshotMacTest do
  use ExUnit.Case, async: true

  alias Famichat.Crypto.MLS.SnapshotMac

  # 32-byte key for all tests — never used outside this test module.
  @test_key "famichat-test-snapshot-hmac-key!!"

  defp valid_payload do
    %{
      "group_id" => "group-abc",
      "epoch" => "3",
      "session_sender_storage" => "deadbeef",
      "session_recipient_storage" => "cafebabe",
      "session_sender_signer" => "0102030405",
      "session_recipient_signer" => "0607080910",
      "session_cache" => ""
    }
  end

  # ── sign/2 ──────────────────────────────────────────────────────────────────

  describe "sign/2" do
    test "returns a 64-character lowercase hex string" do
      assert {:ok, mac} = SnapshotMac.sign(valid_payload(), @test_key)
      assert byte_size(mac) == 64
      assert mac =~ ~r/\A[0-9a-f]{64}\z/
    end

    test "is deterministic: same payload + key always produces the same MAC" do
      payload = valid_payload()
      assert {:ok, mac1} = SnapshotMac.sign(payload, @test_key)
      assert {:ok, mac2} = SnapshotMac.sign(payload, @test_key)
      assert mac1 == mac2
    end

    test "different group_id produces a different MAC" do
      payload_a = valid_payload()
      payload_b = Map.put(payload_a, "group_id", "group-xyz")
      assert {:ok, mac_a} = SnapshotMac.sign(payload_a, @test_key)
      assert {:ok, mac_b} = SnapshotMac.sign(payload_b, @test_key)
      refute mac_a == mac_b
    end

    test "different epoch produces a different MAC" do
      payload_a = valid_payload()
      payload_b = Map.put(payload_a, "epoch", "4")
      assert {:ok, mac_a} = SnapshotMac.sign(payload_a, @test_key)
      assert {:ok, mac_b} = SnapshotMac.sign(payload_b, @test_key)
      refute mac_a == mac_b
    end

    test "different session_sender_storage produces a different MAC" do
      payload_a = valid_payload()
      payload_b = Map.put(payload_a, "session_sender_storage", "00000000")
      assert {:ok, mac_a} = SnapshotMac.sign(payload_a, @test_key)
      assert {:ok, mac_b} = SnapshotMac.sign(payload_b, @test_key)
      refute mac_a == mac_b
    end

    test "different HMAC key produces a different MAC for the same payload" do
      payload = valid_payload()
      other_key = "another-test-snapshot-hmac-key!!"
      assert {:ok, mac_a} = SnapshotMac.sign(payload, @test_key)
      assert {:ok, mac_b} = SnapshotMac.sign(payload, other_key)
      refute mac_a == mac_b
    end

    test "accepts atom keys in addition to string keys" do
      payload_atom = %{
        group_id: "group-atom",
        epoch: "1",
        session_sender_storage: "aa",
        session_recipient_storage: "bb",
        session_sender_signer: "cc",
        session_recipient_signer: "dd",
        session_cache: ""
      }

      payload_string = %{
        "group_id" => "group-atom",
        "epoch" => "1",
        "session_sender_storage" => "aa",
        "session_recipient_storage" => "bb",
        "session_sender_signer" => "cc",
        "session_recipient_signer" => "dd",
        "session_cache" => ""
      }

      assert {:ok, mac_atom} = SnapshotMac.sign(payload_atom, @test_key)
      assert {:ok, mac_string} = SnapshotMac.sign(payload_string, @test_key)
      assert mac_atom == mac_string
    end

    test "returns error when group_id is missing" do
      payload = Map.delete(valid_payload(), "group_id")
      assert {:error, :missing_required_fields} = SnapshotMac.sign(payload, @test_key)
    end

    test "returns error when epoch is missing" do
      payload = Map.delete(valid_payload(), "epoch")
      assert {:error, :missing_required_fields} = SnapshotMac.sign(payload, @test_key)
    end
  end

  # ── verify/3 ────────────────────────────────────────────────────────────────

  describe "verify/3" do
    test "returns :ok for a freshly signed payload" do
      payload = valid_payload()
      assert {:ok, mac} = SnapshotMac.sign(payload, @test_key)
      assert :ok == SnapshotMac.verify(payload, mac, @test_key)
    end

    test "returns {:error, :mac_mismatch} when group_id has been swapped" do
      payload_original = valid_payload()
      assert {:ok, mac} = SnapshotMac.sign(payload_original, @test_key)

      payload_swapped = Map.put(payload_original, "group_id", "group-intruder")
      assert {:error, :mac_mismatch} = SnapshotMac.verify(payload_swapped, mac, @test_key)
    end

    test "returns {:error, :mac_mismatch} when epoch has been decremented (stale replay)" do
      payload_current = valid_payload()
      assert {:ok, mac} = SnapshotMac.sign(payload_current, @test_key)

      payload_stale = Map.put(payload_current, "epoch", "2")
      assert {:error, :mac_mismatch} = SnapshotMac.verify(payload_stale, mac, @test_key)
    end

    test "returns {:error, :mac_mismatch} when any session field is modified" do
      payload = valid_payload()
      assert {:ok, mac} = SnapshotMac.sign(payload, @test_key)

      tampered = Map.put(payload, "session_sender_storage", "00000001")
      assert {:error, :mac_mismatch} = SnapshotMac.verify(tampered, mac, @test_key)
    end

    test "returns {:error, :mac_mismatch} for a truncated MAC" do
      payload = valid_payload()
      assert {:ok, mac} = SnapshotMac.sign(payload, @test_key)
      truncated = String.slice(mac, 0, 32)
      assert {:error, :mac_mismatch} = SnapshotMac.verify(payload, truncated, @test_key)
    end

    test "returns {:error, :mac_mismatch} for an all-zeros MAC" do
      payload = valid_payload()
      zero_mac = String.duplicate("0", 64)
      assert {:error, :mac_mismatch} = SnapshotMac.verify(payload, zero_mac, @test_key)
    end

    test "returns {:error, :mac_mismatch} when wrong key is used to verify" do
      payload = valid_payload()
      assert {:ok, mac} = SnapshotMac.sign(payload, @test_key)
      wrong_key = "wrong-key-snapshot-hmac-key!!!!!"
      assert {:error, :mac_mismatch} = SnapshotMac.verify(payload, mac, wrong_key)
    end

    test "cross-group snapshot swap is rejected" do
      # MAC was computed for group-a; attacker tries to use it with group-b snapshot.
      payload_a =
        valid_payload()
        |> Map.put("group_id", "group-a")
        |> Map.put("session_sender_storage", "aabbcc")

      payload_b =
        valid_payload()
        |> Map.put("group_id", "group-b")
        |> Map.put("session_sender_storage", "aabbcc")

      assert {:ok, mac_a} = SnapshotMac.sign(payload_a, @test_key)
      assert {:error, :mac_mismatch} = SnapshotMac.verify(payload_b, mac_a, @test_key)
    end

    test "stale-epoch snapshot is rejected even when state bytes are identical" do
      # Epoch 5 snapshot signed, then an attacker tries to restore an epoch-3 snapshot
      # with the epoch-5 MAC (or vice-versa).
      payload_current = Map.put(valid_payload(), "epoch", "5")
      payload_stale = Map.put(valid_payload(), "epoch", "3")

      assert {:ok, mac_current} = SnapshotMac.sign(payload_current, @test_key)
      assert {:error, :mac_mismatch} = SnapshotMac.verify(payload_stale, mac_current, @test_key)
    end
  end

  # ── configured_key!/0 ───────────────────────────────────────────────────────

  describe "configured_key!/0" do
    test "returns the key configured in :famichat, :mls_snapshot_hmac_key" do
      previous = Application.get_env(:famichat, :mls_snapshot_hmac_key)
      Application.put_env(:famichat, :mls_snapshot_hmac_key, @test_key)

      assert SnapshotMac.configured_key!() == @test_key

      case previous do
        nil -> Application.delete_env(:famichat, :mls_snapshot_hmac_key)
        val -> Application.put_env(:famichat, :mls_snapshot_hmac_key, val)
      end
    end
  end
end
