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
    assert fetch(health_payload, "reason") == "openmls_not_wired"
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

  defp fetch(payload, key) do
    atom_key =
      case key do
        "status" -> :status
        "reason" -> :reason
        "group_id" -> :group_id
        "ciphertext" -> :ciphertext
        "plaintext" -> :plaintext
        "merged" -> :merged
        _ -> nil
      end

    Map.get(payload, key) || (atom_key && Map.get(payload, atom_key))
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
