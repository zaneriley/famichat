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

  test "create_key_package returns unique references per call" do
    assert {:ok, first_payload} =
             MLS.create_key_package(%{client_id: "nif-kp-unique"})

    assert {:ok, second_payload} =
             MLS.create_key_package(%{client_id: "nif-kp-unique"})

    first_ref = fetch(first_payload, "key_package_ref")
    second_ref = fetch(second_payload, "key_package_ref")

    assert is_binary(first_ref)
    assert is_binary(second_ref)
    assert String.starts_with?(first_ref, "kp:nif-kp-unique:")
    assert String.starts_with?(second_ref, "kp:nif-kp-unique:")
    refute first_ref == second_ref
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

  test "create_application_message fails closed when group state is missing" do
    assert {:error, :storage_inconsistent, details} =
             MLS.create_application_message(%{
               group_id: "group-nif-missing-state",
               body: "hello"
             })

    assert fetch(details, "reason") == "missing_group_state"
  end

  test "lifecycle operation aliases return ok and include operation labels" do
    # mls_remove is now a real implementation (not a stub) and requires group state.
    # It is tested separately in the mls_remove spirit tests describe block.
    for operation <- [
          &MLS.mls_commit/1,
          &MLS.mls_update/1,
          &MLS.mls_add/1
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

  # Phase 1: Credential Binding Tests

  test "list_member_credentials returns real credential identities" do
    group_id = "group-cred-test-#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             MLS.create_group(%{
               group_id: group_id,
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:ok, payload} = MLS.list_member_credentials(%{group_id: group_id})
    credentials_str = Map.fetch!(payload, "credentials")

    # Must return exactly 2 entries (sender + recipient in two-actor model)
    entries = String.split(credentials_str, ",", trim: true)
    assert length(entries) == 2, "expected 2 members, got: #{inspect(entries)}"

    # Each entry must be "leaf_index:identity_hex"
    for entry <- entries do
      assert [_index, identity_hex] = String.split(entry, ":", parts: 2)
      assert byte_size(identity_hex) > 0, "identity_hex must be non-empty"
      # Identity must decode to valid UTF-8 bytes containing group_id
      {:ok, decoded} = Base.decode16(String.upcase(identity_hex))
      assert String.contains?(decoded, group_id),
             "identity must contain group_id #{group_id}, got: #{inspect(decoded)}"
    end
  end

  test "list_member_credentials with credential_identity param uses supplied identity" do
    group_id = "group-cred-supplied-#{System.unique_integer([:positive])}"
    device_id = "device-abc-123"

    assert {:ok, _} =
             MLS.create_group(%{
               group_id: group_id,
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
               credential_identity: device_id
             })

    assert {:ok, payload} = MLS.list_member_credentials(%{group_id: group_id})
    credentials_str = Map.fetch!(payload, "credentials")
    entries = String.split(credentials_str, ",", trim: true)

    # At least one entry must have the supplied device_id as identity
    identities =
      Enum.map(entries, fn entry ->
        [_index, hex] = String.split(entry, ":", parts: 2)
        {:ok, bytes} = Base.decode16(String.upcase(hex))
        bytes
      end)

    assert Enum.any?(identities, &(&1 == device_id)),
           "expected device_id #{device_id} in identities: #{inspect(identities)}"
  end

  test "list_member_credentials fails closed for unknown group" do
    assert {:error, _code, _details} =
             MLS.list_member_credentials(%{
               group_id: "nonexistent-group-#{System.unique_integer([:positive])}"
             })
  end

  test "create_group without credential_identity still works (backward compat)" do
    group_id = "group-backward-compat-#{System.unique_integer([:positive])}"

    assert {:ok, payload} =
             MLS.create_group(%{
               group_id: group_id,
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    # Must still succeed and return expected keys
    assert Map.has_key?(payload, "epoch") or Map.has_key?(payload, :epoch)
    assert Map.has_key?(payload, "session_sender_storage") or
             Map.has_key?(payload, :session_sender_storage)
  end

  describe "mls_remove spirit tests" do
    setup do
      group_id = "group-remove-spirit-#{System.unique_integer([:positive])}"

      {:ok, group_payload} =
        MLS.create_group(%{
          group_id: group_id,
          ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
        })

      %{group_id: group_id, group_payload: group_payload}
    end

    test "epoch advances after mls_remove", %{group_id: group_id, group_payload: group_payload} do
      epoch_before = String.to_integer(Map.get(group_payload, "epoch") || Map.get(group_payload, :epoch))

      assert {:ok, remove_payload} =
               MLS.mls_remove(
                 Map.merge(group_payload, %{
                   "group_id" => group_id,
                   "remove_target" => "recipient"
                 })
               )

      remove_epoch =
        String.to_integer(Map.get(remove_payload, "epoch") || Map.get(remove_payload, :epoch))

      assert remove_epoch == epoch_before + 1,
             "epoch must advance by exactly 1 after remove, got #{remove_epoch} expected #{epoch_before + 1}"

      assert {:ok, msg_payload} =
               MLS.create_application_message(
                 Map.merge(remove_payload, %{
                   "group_id" => group_id,
                   "body" => "post-remove message"
                 })
               )

      msg_epoch =
        String.to_integer(Map.get(msg_payload, "epoch") || Map.get(msg_payload, :epoch))

      assert msg_epoch == remove_epoch,
             "create_application_message epoch must equal mls_remove epoch"
    end

    test "removed member cannot send after mls_remove", %{
      group_id: group_id,
      group_payload: group_payload
    } do
      assert {:ok, remove_payload} =
               MLS.mls_remove(
                 Map.merge(group_payload, %{
                   "group_id" => group_id,
                   "remove_target" => "recipient"
                 })
               )

      # Attempt to send as the removed member — must fail
      # The removed member's session snapshot is in remove_payload under recipient keys
      assert {:error, _code, _details} =
               MLS.create_application_message(%{
                 "group_id" => group_id,
                 "body" => "should fail",
                 "session_sender_storage" =>
                   Map.get(remove_payload, "session_recipient_storage") ||
                     Map.get(remove_payload, :session_recipient_storage),
                 "session_sender_signer" =>
                   Map.get(remove_payload, "session_recipient_signer") ||
                     Map.get(remove_payload, :session_recipient_signer),
                 "session_recipient_storage" =>
                   Map.get(remove_payload, "session_sender_storage") ||
                     Map.get(remove_payload, :session_sender_storage),
                 "session_recipient_signer" =>
                   Map.get(remove_payload, "session_sender_signer") ||
                     Map.get(remove_payload, :session_sender_signer),
                 "session_cache" =>
                   Map.get(remove_payload, "session_cache") ||
                     Map.get(remove_payload, :session_cache)
               })
    end

    test "group size decreases after mls_remove", %{
      group_id: group_id,
      group_payload: group_payload
    } do
      {:ok, before_payload} =
        MLS.list_member_credentials(
          Map.merge(group_payload, %{"group_id" => group_id})
        )

      before_count =
        (Map.get(before_payload, "credentials") || Map.get(before_payload, :credentials))
        |> String.split(",", trim: true)
        |> length()

      assert before_count == 2

      assert {:ok, remove_payload} =
               MLS.mls_remove(
                 Map.merge(group_payload, %{
                   "group_id" => group_id,
                   "remove_target" => "recipient"
                 })
               )

      {:ok, after_payload} =
        MLS.list_member_credentials(
          Map.merge(remove_payload, %{"group_id" => group_id})
        )

      after_count =
        (Map.get(after_payload, "credentials") || Map.get(after_payload, :credentials))
        |> String.split(",", trim: true)
        |> length()

      assert after_count == 1, "group must have 1 member after remove, got #{after_count}"
    end

    test "commit_ciphertext is non-empty in remove payload", %{
      group_id: group_id,
      group_payload: group_payload
    } do
      assert {:ok, remove_payload} =
               MLS.mls_remove(
                 Map.merge(group_payload, %{
                   "group_id" => group_id,
                   "remove_target" => "recipient"
                 })
               )

      commit_ciphertext = Map.get(remove_payload, "commit_ciphertext", "")
      assert byte_size(commit_ciphertext) > 0,
             "commit_ciphertext must be non-empty; lifecycle_ok stub never calls remove_members()"
    end

    test "replay of mls_remove fails when using post-remove snapshot", %{
      group_id: group_id,
      group_payload: group_payload
    } do
      assert {:ok, remove_payload} =
               MLS.mls_remove(
                 Map.merge(group_payload, %{
                   "group_id" => group_id,
                   "remove_target" => "recipient"
                 })
               )

      # Attempt remove again using the post-remove snapshot — recipient is already gone
      # from the ratchet tree so remove_members will fail with an invalid leaf index.
      assert {:error, _code, _details} =
               MLS.mls_remove(
                 Map.merge(remove_payload, %{
                   "group_id" => group_id,
                   "remove_target" => "recipient"
                 })
               )
    end
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
        "key_package_ref" -> :key_package_ref
        "credentials" -> :credentials
        "epoch" -> :epoch
        _ -> nil
      end

    Map.get(payload, key) || (atom_key && Map.get(payload, atom_key))
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
