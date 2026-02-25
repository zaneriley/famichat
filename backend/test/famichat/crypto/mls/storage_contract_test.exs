defmodule Famichat.Crypto.MLS.StorageContractTest do
  use ExUnit.Case, async: false

  alias Famichat.Crypto.MLS
  alias Famichat.TestSupport.MLS.FakeAdapter

  setup do
    previous_adapter = Application.get_env(:famichat, :mls_adapter)
    Application.put_env(:famichat, :mls_adapter, FakeAdapter)

    on_exit(fn ->
      restore_env(:mls_adapter, previous_adapter)
    end)

    :ok
  end

  test "missing required group state returns storage_inconsistent and redacts secrets" do
    assert {:error, :storage_inconsistent, details} =
             MLS.create_application_message(%{
               group_id: "group-1",
               body: "hello",
               force_error: :storage_inconsistent,
               error_details: %{
                 reason: :missing_group_state,
                 key_material: "never expose"
               }
             })

    assert details[:reason] == :missing_group_state
    refute Map.has_key?(details, :key_material)
  end

  test "deleted key material cannot be loaded again" do
    assert {:error, :storage_inconsistent, details} =
             MLS.process_incoming(%{
               group_id: "group-1",
               ciphertext: "ciphertext:old",
               force_error: :storage_inconsistent,
               error_details: %{reason: :deleted_key_material}
             })

    assert details[:reason] == :deleted_key_material
  end

  test "key package depletion is surfaced as storage_inconsistent" do
    assert {:error, :storage_inconsistent, details} =
             MLS.create_key_package(%{
               client_id: "client-1",
               force_error: :storage_inconsistent,
               error_details: %{reason: :key_package_depleted}
             })

    assert details[:reason] == :key_package_depleted
  end

  test "state-loss recovery path is deterministic and audit-addressable" do
    assert {:ok, first} =
             MLS.join_from_welcome(%{
               welcome: "welcome-payload",
               rejoin_token: "token-123"
             })

    assert {:ok, second} =
             MLS.join_from_welcome(%{
               welcome: "welcome-payload",
               rejoin_token: "token-123"
             })

    assert first == second
    assert first[:group_state_ref] == "state:token-123"
    assert first[:audit_id] == "audit:token-123"
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
