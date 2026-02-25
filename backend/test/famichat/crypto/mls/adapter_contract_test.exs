defmodule Famichat.Crypto.MLS.AdapterContractTest do
  use ExUnit.Case, async: false

  alias Famichat.Crypto.MLS
  alias Famichat.Crypto.MLS.Adapter.Unimplemented

  setup do
    previous_adapter = Application.get_env(:famichat, :mls_adapter)
    Application.put_env(:famichat, :mls_adapter, Unimplemented)

    on_exit(fn ->
      restore_env(:mls_adapter, previous_adapter)
    end)

    :ok
  end

  describe "current integration state without Rust NIF" do
    test "zero-arg operations return unsupported capability" do
      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :nif_version}} =
               MLS.nif_version()

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :nif_health}} =
               MLS.nif_health()
    end

    test "map-accepting operations return unsupported capability until adapter is implemented" do
      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :create_key_package}} =
               MLS.create_key_package(%{client_id: "c1"})

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :create_group}} =
               MLS.create_group(%{
                 group_id: "g1",
                 ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
               })

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :join_from_welcome}} =
               MLS.join_from_welcome(%{welcome: "w1"})

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :process_incoming}} =
               MLS.process_incoming(%{group_id: "g1", message: "m1"})

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :commit_to_pending}} =
               MLS.commit_to_pending(%{group_id: "g1"})

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :mls_commit}} =
               MLS.mls_commit(%{group_id: "g1"})

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :mls_update}} =
               MLS.mls_update(%{group_id: "g1"})

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :mls_add}} =
               MLS.mls_add(%{group_id: "g1"})

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :mls_remove}} =
               MLS.mls_remove(%{group_id: "g1"})

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :merge_staged_commit}} =
               MLS.merge_staged_commit(%{
                 group_id: "g1",
                 staged_commit_validated: true
               })

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :clear_pending_commit}} =
               MLS.clear_pending_commit(%{group_id: "g1"})

      assert {:error, :unsupported_capability,
              %{
                reason: :not_implemented,
                operation: :create_application_message
              }} =
               MLS.create_application_message(%{group_id: "g1", body: "hello"})

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :export_group_info}} =
               MLS.export_group_info(%{group_id: "g1"})

      assert {:error, :unsupported_capability,
              %{reason: :not_implemented, operation: :export_ratchet_tree}} =
               MLS.export_ratchet_tree(%{group_id: "g1"})
    end
  end

  describe "wrapper guardrails (adapter-agnostic)" do
    test "non-map params are rejected as invalid_input for all /1 operations" do
      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.create_key_package("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.create_group("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.join_from_welcome("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.process_incoming("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.commit_to_pending("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.mls_commit("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.mls_update("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.mls_add("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.mls_remove("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.merge_staged_commit("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.clear_pending_commit("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.create_application_message("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.export_group_info("invalid")

      assert {:error, :invalid_input, %{reason: "params must be a map"}} =
               MLS.export_ratchet_tree("invalid")
    end

    test "create_group requires group_id and ciphersuite before adapter invocation" do
      assert {:error, :invalid_input, details} = MLS.create_group(%{})
      assert details == %{group_id: "is required", ciphersuite: "is required"}
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
