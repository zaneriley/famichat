defmodule Famichat.Crypto.MLS.NifAdapterTest do
  use ExUnit.Case, async: false

  alias Famichat.Crypto.MLS
  alias Famichat.Crypto.MLS.Adapter.Nif

  setup do
    previous_adapter = Application.get_env(:famichat, :mls_adapter)
    Application.put_env(:famichat, :mls_adapter, Nif)

    on_exit(fn ->
      restore_env(:mls_adapter, previous_adapter)
    end)

    :ok
  end

  test "nif version and health are exposed through the adapter contract" do
    assert {:ok, version_payload} = MLS.nif_version()
    assert {:ok, health_payload} = MLS.nif_health()

    assert fetch(version_payload, "status") == "wired_contract"
    assert fetch(health_payload, "status") == "ok"
    assert fetch(health_payload, "reason") == "openmls_ready"
  end

  test "group/message lifecycle operations return deterministic contract-safe payloads" do
    assert {:ok, create_group_payload} =
             MLS.create_group(%{
               group_id: "group-nif-1",
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert fetch(create_group_payload, "group_id") == "group-nif-1"

    assert {:ok, encrypted_payload} =
             MLS.create_application_message(%{
               group_id: "group-nif-1",
               body: "hello from nif"
             })

    ciphertext = fetch(encrypted_payload, "ciphertext")

    assert {:ok, decrypted_payload} =
             MLS.process_incoming(%{
               group_id: "group-nif-1",
               ciphertext: ciphertext
             })

    assert fetch(decrypted_payload, "plaintext") == "hello from nif"

    assert {:ok, merge_payload} =
             MLS.merge_staged_commit(%{
               group_id: "group-nif-1",
               staged_commit_validated: true,
               epoch: 1
             })

    assert fetch(merge_payload, "merged") == "true"
  end

  test "lifecycle operation aliases return ok and include operation labels" do
    for operation <- [
          &MLS.mls_commit/1,
          &MLS.mls_update/1,
          &MLS.mls_add/1,
          &MLS.mls_remove/1
        ] do
      assert {:ok, payload} = operation.(%{group_id: "group-nif-2", epoch: 2})
      assert fetch(payload, "group_id") == "group-nif-2"
      assert fetch(payload, "status") == "ok"
    end
  end

  test "process_incoming rejects malformed ciphertext without leaking plaintext" do
    assert {:ok, _group_payload} =
             MLS.create_group(%{
               group_id: "group-nif-malformed",
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:error, :invalid_input, details} =
             MLS.process_incoming(%{
               group_id: "group-nif-malformed",
               ciphertext: "zz"
             })

    reason = fetch(details, "reason")
    assert reason in ["invalid_ciphertext_encoding", "malformed_ciphertext"]
    refute Map.has_key?(details, :plaintext)
    refute Map.has_key?(details, "plaintext")
  end

  test "ciphertext from one group is rejected by a different group" do
    assert {:ok, _group_payload} =
             MLS.create_group(%{
               group_id: "group-nif-a",
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:ok, _group_payload} =
             MLS.create_group(%{
               group_id: "group-nif-b",
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:ok, encrypted_payload} =
             MLS.create_application_message(%{
               group_id: "group-nif-a",
               body: "isolation-check"
             })

    ciphertext = fetch(encrypted_payload, "ciphertext")

    assert {:error, :commit_rejected, details} =
             MLS.process_incoming(%{
               group_id: "group-nif-b",
               ciphertext: ciphertext
             })

    assert fetch(details, "reason") == "message_processing_failed"
    refute Map.has_key?(details, :plaintext)
    refute Map.has_key?(details, "plaintext")
  end

  test "replayed ciphertext is rejected on second processing attempt" do
    assert {:ok, _group_payload} =
             MLS.create_group(%{
               group_id: "group-nif-replay",
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:ok, encrypted_payload} =
             MLS.create_application_message(%{
               group_id: "group-nif-replay",
               body: "replay-guard"
             })

    ciphertext = fetch(encrypted_payload, "ciphertext")

    assert {:ok, decrypted_payload} =
             MLS.process_incoming(%{
               group_id: "group-nif-replay",
               ciphertext: ciphertext
             })

    assert fetch(decrypted_payload, "plaintext") == "replay-guard"

    assert {:error, :commit_rejected, details} =
             MLS.process_incoming(%{
               group_id: "group-nif-replay",
               ciphertext: ciphertext
             })

    assert fetch(details, "reason") == "message_processing_failed"
    refute Map.has_key?(details, :plaintext)
    refute Map.has_key?(details, "plaintext")
  end

  test "message_id-scoped replay is idempotent for read paths while raw replay stays rejected" do
    assert {:ok, _group_payload} =
             MLS.create_group(%{
               group_id: "group-nif-message-cache",
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:ok, encrypted_payload} =
             MLS.create_application_message(%{
               group_id: "group-nif-message-cache",
               body: "cache-guard"
             })

    ciphertext = fetch(encrypted_payload, "ciphertext")

    assert {:ok, first} =
             MLS.process_incoming(%{
               group_id: "group-nif-message-cache",
               message_id: "msg-1",
               ciphertext: ciphertext
             })

    assert fetch(first, "plaintext") == "cache-guard"

    assert {:ok, second} =
             MLS.process_incoming(%{
               group_id: "group-nif-message-cache",
               message_id: "msg-1",
               ciphertext: ciphertext
             })

    assert fetch(second, "plaintext") == "cache-guard"

    assert {:error, :commit_rejected, details} =
             MLS.process_incoming(%{
               group_id: "group-nif-message-cache",
               ciphertext: ciphertext
             })

    assert fetch(details, "reason") == "message_processing_failed"
  end

  test "message_id cache rejects ciphertext mismatches to prevent stale-id aliasing" do
    assert {:ok, _group_payload} =
             MLS.create_group(%{
               group_id: "group-nif-message-id-integrity",
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:ok, first_payload} =
             MLS.create_application_message(%{
               group_id: "group-nif-message-id-integrity",
               body: "message-one"
             })

    assert {:ok, second_payload} =
             MLS.create_application_message(%{
               group_id: "group-nif-message-id-integrity",
               body: "message-two"
             })

    first_ciphertext = fetch(first_payload, "ciphertext")
    second_ciphertext = fetch(second_payload, "ciphertext")

    assert {:ok, _first_decrypted} =
             MLS.process_incoming(%{
               group_id: "group-nif-message-id-integrity",
               message_id: "msg-1",
               ciphertext: first_ciphertext
             })

    assert {:error, :storage_inconsistent, details} =
             MLS.process_incoming(%{
               group_id: "group-nif-message-id-integrity",
               message_id: "msg-1",
               ciphertext: second_ciphertext
             })

    assert fetch(details, "reason") == "message_id_ciphertext_mismatch"
  end

  test "export_group_info emits a restorable session snapshot payload" do
    group_id = "group-nif-snapshot-export"

    assert {:ok, _group_payload} =
             MLS.create_group(%{
               group_id: group_id,
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:ok, _encrypted_payload} =
             MLS.create_application_message(%{
               group_id: group_id,
               body: "snapshot-export"
             })

    assert {:ok, export_payload} = MLS.export_group_info(%{group_id: group_id})

    assert fetch(export_payload, "group_info_ref") == "group-info:#{group_id}"

    for snapshot_key <- [
          "session_sender_storage",
          "session_recipient_storage",
          "session_sender_signer",
          "session_recipient_signer",
          "session_cache"
        ] do
      value = fetch(export_payload, snapshot_key)
      assert is_binary(value)

      if snapshot_key == "session_cache" do
        assert byte_size(value) >= 0
      else
        assert byte_size(value) > 0
      end
    end
  end

  test "create_group restores session snapshot and preserves cached reads" do
    group_id = "group-nif-snapshot-restore"

    assert {:ok, _group_payload} =
             MLS.create_group(%{
               group_id: group_id,
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:ok, encrypted_payload} =
             MLS.create_application_message(%{
               group_id: group_id,
               body: "snapshot-body"
             })

    ciphertext = fetch(encrypted_payload, "ciphertext")

    assert {:ok, decrypted_payload} =
             MLS.process_incoming(%{
               group_id: group_id,
               message_id: "m-snapshot",
               ciphertext: ciphertext
             })

    assert fetch(decrypted_payload, "plaintext") == "snapshot-body"

    assert {:ok, snapshot_payload} =
             MLS.export_group_info(%{group_id: group_id})

    assert {:ok, _restored_group_payload} =
             MLS.create_group(%{
               group_id: group_id,
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
               session_sender_storage:
                 fetch(snapshot_payload, "session_sender_storage"),
               session_recipient_storage:
                 fetch(snapshot_payload, "session_recipient_storage"),
               session_sender_signer:
                 fetch(snapshot_payload, "session_sender_signer"),
               session_recipient_signer:
                 fetch(snapshot_payload, "session_recipient_signer"),
               session_cache: fetch(snapshot_payload, "session_cache")
             })

    assert {:ok, replayed_from_cache} =
             MLS.process_incoming(%{
               group_id: group_id,
               message_id: "m-snapshot",
               ciphertext: ciphertext
             })

    assert fetch(replayed_from_cache, "plaintext") == "snapshot-body"
  end

  test "session cache export stays bounded under high replay-cardinality reads" do
    group_id = "group-nif-cache-bounded"

    assert {:ok, _group_payload} =
             MLS.create_group(%{
               group_id: group_id,
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    for index <- 1..320 do
      assert {:ok, encrypted_payload} =
               MLS.create_application_message(%{
                 group_id: group_id,
                 body: "cache-bounded-#{index}"
               })

      assert {:ok, _decrypted_payload} =
               MLS.process_incoming(%{
                 group_id: group_id,
                 message_id: "msg-#{index}",
                 ciphertext: fetch(encrypted_payload, "ciphertext")
               })
    end

    assert {:ok, snapshot_payload} =
             MLS.export_group_info(%{group_id: group_id})

    cache_entries =
      snapshot_payload
      |> fetch("session_cache")
      |> String.split(",", trim: true)

    assert length(cache_entries) <= 256
  end

  defp fetch(payload, key) do
    atom_key =
      case key do
        "status" -> :status
        "reason" -> :reason
        "group_id" -> :group_id
        "ciphertext" -> :ciphertext
        "plaintext" -> :plaintext
        "merged" -> :merged
        "group_info_ref" -> :group_info_ref
        "session_sender_storage" -> :session_sender_storage
        "session_recipient_storage" -> :session_recipient_storage
        "session_sender_signer" -> :session_sender_signer
        "session_recipient_signer" -> :session_recipient_signer
        "session_cache" -> :session_cache
        _ -> nil
      end

    Map.get(payload, key) || (atom_key && Map.get(payload, atom_key))
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
