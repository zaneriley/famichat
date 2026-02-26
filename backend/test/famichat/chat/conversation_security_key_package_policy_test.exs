defmodule Famichat.Chat.ConversationSecurityKeyPackagePolicyTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.{
    ConversationSecurityClientInventoryStore,
    ConversationSecurityKeyPackagePolicy
  }

  alias Famichat.TestSupport.MLS.FakeAdapter

  defmodule FailingKeyPackageAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    alias Famichat.TestSupport.MLS.FakeAdapter

    @impl true
    def nif_version, do: FakeAdapter.nif_version()

    @impl true
    def nif_health, do: FakeAdapter.nif_health()

    @impl true
    def create_key_package(_params) do
      {:error, :storage_inconsistent,
       %{reason: :key_package_depleted, operation: :create_key_package}}
    end

    @impl true
    def create_group(params), do: FakeAdapter.create_group(params)

    @impl true
    def join_from_welcome(params), do: FakeAdapter.join_from_welcome(params)

    @impl true
    def process_incoming(params), do: FakeAdapter.process_incoming(params)

    @impl true
    def commit_to_pending(params), do: FakeAdapter.commit_to_pending(params)

    @impl true
    def mls_commit(params), do: FakeAdapter.mls_commit(params)

    @impl true
    def mls_update(params), do: FakeAdapter.mls_update(params)

    @impl true
    def mls_add(params), do: FakeAdapter.mls_add(params)

    @impl true
    def mls_remove(params), do: FakeAdapter.mls_remove(params)

    @impl true
    def merge_staged_commit(params), do: FakeAdapter.merge_staged_commit(params)

    @impl true
    def clear_pending_commit(params),
      do: FakeAdapter.clear_pending_commit(params)

    @impl true
    def create_application_message(params),
      do: FakeAdapter.create_application_message(params)

    @impl true
    def export_group_info(params), do: FakeAdapter.export_group_info(params)

    @impl true
    def export_ratchet_tree(params), do: FakeAdapter.export_ratchet_tree(params)
  end

  defmodule InvalidKeyPackageAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    alias Famichat.TestSupport.MLS.FakeAdapter

    @impl true
    def nif_version, do: FakeAdapter.nif_version()

    @impl true
    def nif_health, do: FakeAdapter.nif_health()

    @impl true
    def create_key_package(params) do
      client_id = Map.get(params, :client_id) || Map.get(params, "client_id")
      {:ok, %{"client_id" => client_id, "status" => "created"}}
    end

    @impl true
    def create_group(params), do: FakeAdapter.create_group(params)

    @impl true
    def join_from_welcome(params), do: FakeAdapter.join_from_welcome(params)

    @impl true
    def process_incoming(params), do: FakeAdapter.process_incoming(params)

    @impl true
    def commit_to_pending(params), do: FakeAdapter.commit_to_pending(params)

    @impl true
    def mls_commit(params), do: FakeAdapter.mls_commit(params)

    @impl true
    def mls_update(params), do: FakeAdapter.mls_update(params)

    @impl true
    def mls_add(params), do: FakeAdapter.mls_add(params)

    @impl true
    def mls_remove(params), do: FakeAdapter.mls_remove(params)

    @impl true
    def merge_staged_commit(params), do: FakeAdapter.merge_staged_commit(params)

    @impl true
    def clear_pending_commit(params),
      do: FakeAdapter.clear_pending_commit(params)

    @impl true
    def create_application_message(params),
      do: FakeAdapter.create_application_message(params)

    @impl true
    def export_group_info(params), do: FakeAdapter.export_group_info(params)

    @impl true
    def export_ratchet_tree(params), do: FakeAdapter.export_ratchet_tree(params)
  end

  setup do
    previous_adapter = Application.get_env(:famichat, :mls_adapter)
    Application.put_env(:famichat, :mls_adapter, FakeAdapter)

    on_exit(fn ->
      restore_env(:mls_adapter, previous_adapter)
    end)

    :ok
  end

  test "ensure_inventory creates initial durable inventory with target count" do
    assert {:ok, result} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               "client-policy-init",
               target_count: 3,
               replenish_threshold: 1
             )

    assert result.client_id == "client-policy-init"
    assert result.created_count == 3
    assert result.available_count == 3
    assert result.replenished_count == 0

    assert {:ok, inventory} =
             ConversationSecurityClientInventoryStore.load("client-policy-init")

    assert inventory.available_count == 3
    assert length(inventory.key_packages) == 3
    assert inventory.target_count == 3
    assert inventory.replenish_threshold == 1

    refs =
      inventory.key_packages
      |> Enum.map(&Map.get(&1, "key_package_ref"))

    assert Enum.uniq(refs) == refs
  end

  test "consume_key_package consumes one key package and replenishes when below threshold" do
    assert {:ok, _seeded} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               "client-policy-consume",
               target_count: 3,
               replenish_threshold: 2
             )

    assert {:ok, first} =
             ConversationSecurityKeyPackagePolicy.consume_key_package(
               "client-policy-consume",
               target_count: 3,
               replenish_threshold: 2
             )

    assert first.available_count == 2
    assert first.replenished_count == 0
    assert is_map(first.key_package)

    assert {:ok, second} =
             ConversationSecurityKeyPackagePolicy.consume_key_package(
               "client-policy-consume",
               target_count: 3,
               replenish_threshold: 2
             )

    assert second.available_count == 3
    assert second.replenished_count == 2
    assert is_map(second.key_package)

    assert {:ok, inventory} =
             ConversationSecurityClientInventoryStore.load(
               "client-policy-consume"
             )

    assert inventory.available_count == 3
    assert length(inventory.key_packages) == 3
  end

  test "consume_key_package retries optimistic-lock contention and converges deterministically" do
    client_id = "client-policy-race"

    assert {:ok, _seeded} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               client_id,
               target_count: 10,
               replenish_threshold: 3
             )

    results =
      1..20
      |> Task.async_stream(
        fn _ ->
          ConversationSecurityKeyPackagePolicy.consume_key_package(
            client_id,
            target_count: 10,
            replenish_threshold: 3
          )
        end,
        max_concurrency: 8,
        timeout: 15_000
      )
      |> Enum.to_list()

    assert Enum.count(results) == 20

    assert Enum.all?(results, fn
             {:ok, {:ok, payload}} ->
               is_map(payload) and is_map(payload.key_package)

             _ ->
               false
           end)

    assert {:ok, inventory} =
             ConversationSecurityClientInventoryStore.load(client_id)

    assert inventory.available_count <= 10
    assert inventory.available_count >= 1
    assert length(inventory.key_packages) == inventory.available_count
  end

  test "ensure_inventory fails closed when key-package generation fails" do
    Application.put_env(:famichat, :mls_adapter, FailingKeyPackageAdapter)

    assert {:error, :storage_inconsistent, details} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               "client-policy-fail",
               target_count: 2,
               replenish_threshold: 1
             )

    assert details[:reason] == :key_package_depleted

    assert {:error, :not_found, _details} =
             ConversationSecurityClientInventoryStore.load("client-policy-fail")
  end

  test "policy rejects non-positive replenish_threshold" do
    assert {:error, :invalid_input, details} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               "client-policy-threshold",
               target_count: 2,
               replenish_threshold: 0
             )

    assert details[:reason] == :invalid_replenish_threshold
  end

  test "ensure_inventory fails closed when adapter omits key_package_ref" do
    Application.put_env(:famichat, :mls_adapter, InvalidKeyPackageAdapter)

    assert {:error, :storage_inconsistent, details} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               "client-policy-invalid-payload",
               target_count: 2,
               replenish_threshold: 1
             )

    assert details[:reason] == :invalid_key_package_payload
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
