defmodule Famichat.Chat.ConversationSecurityKeyPackagePolicyTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.{
    ConversationSecurityClientInventory,
    ConversationSecurityClientInventoryStore,
    ConversationSecurityKeyPackagePolicy
  }

  alias Famichat.Repo
  alias Famichat.TestSupport.MLS.FakeAdapter
  alias Famichat.TestSupport.TelemetryHelpers

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

  defmodule PartiallyFailingKeyPackageAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    alias Famichat.TestSupport.MLS.FakeAdapter

    @impl true
    def nif_version, do: FakeAdapter.nif_version()

    @impl true
    def nif_health, do: FakeAdapter.nif_health()

    @impl true
    def create_key_package(params) do
      client_id = Map.get(params, :client_id) || Map.get(params, "client_id")

      if client_id == "client-policy-rotate-batch-fail" do
        {:error, :storage_inconsistent,
         %{reason: :key_package_depleted, operation: :create_key_package}}
      else
        FakeAdapter.create_key_package(params)
      end
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

  test "ensure_inventory rotates stale inventory when rotation interval is exceeded" do
    client_id = "client-policy-rotate-trigger"

    assert {:ok, _seeded} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               client_id,
               target_count: 3,
               replenish_threshold: 1,
               rotation_interval_seconds: 60
             )

    assert {:ok, before_inventory} =
             ConversationSecurityClientInventoryStore.load(client_id)

    refs_before =
      before_inventory.key_packages
      |> Enum.map(&Map.fetch!(&1, "key_package_ref"))
      |> MapSet.new()

    stale_time = DateTime.add(DateTime.utc_now(:microsecond), -120, :second)

    {updated_count, _rows} =
      Repo.update_all(
        from(i in ConversationSecurityClientInventory,
          where: i.client_id == ^client_id
        ),
        set: [updated_at: stale_time]
      )

    assert updated_count == 1

    assert {:ok, result} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               client_id,
               target_count: 3,
               replenish_threshold: 1,
               rotation_interval_seconds: 60
             )

    assert result.rotated_count == 3

    assert {:ok, after_inventory} =
             ConversationSecurityClientInventoryStore.load(client_id)

    refs_after =
      after_inventory.key_packages
      |> Enum.map(&Map.fetch!(&1, "key_package_ref"))
      |> MapSet.new()

    refute MapSet.equal?(refs_before, refs_after)
  end

  test "rotate_stale_inventories rotates stale client inventories in batch" do
    stale_client_id = "client-policy-rotate-batch-stale"
    fresh_client_id = "client-policy-rotate-batch-fresh"

    assert {:ok, _} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               stale_client_id,
               target_count: 3,
               replenish_threshold: 1,
               rotation_interval_seconds: 60
             )

    assert {:ok, _} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               fresh_client_id,
               target_count: 3,
               replenish_threshold: 1,
               rotation_interval_seconds: 60
             )

    assert {:ok, stale_before} =
             ConversationSecurityClientInventoryStore.load(stale_client_id)

    assert {:ok, fresh_before} =
             ConversationSecurityClientInventoryStore.load(fresh_client_id)

    stale_before_refs =
      stale_before.key_packages
      |> Enum.map(&Map.fetch!(&1, "key_package_ref"))
      |> MapSet.new()

    fresh_before_refs =
      fresh_before.key_packages
      |> Enum.map(&Map.fetch!(&1, "key_package_ref"))
      |> MapSet.new()

    stale_time = DateTime.add(DateTime.utc_now(:microsecond), -120, :second)
    fresh_time = DateTime.utc_now(:microsecond)

    {stale_count, _rows} =
      Repo.update_all(
        from(i in ConversationSecurityClientInventory,
          where: i.client_id == ^stale_client_id
        ),
        set: [updated_at: stale_time]
      )

    {fresh_count, _rows} =
      Repo.update_all(
        from(i in ConversationSecurityClientInventory,
          where: i.client_id == ^fresh_client_id
        ),
        set: [updated_at: fresh_time]
      )

    assert stale_count == 1
    assert fresh_count == 1

    assert {:ok, summary} =
             ConversationSecurityKeyPackagePolicy.rotate_stale_inventories(
               rotation_interval_seconds: 60,
               batch_limit: 20,
               target_count: 3,
               replenish_threshold: 1
             )

    assert summary.scanned_count == 1
    assert summary.rotated_client_count == 1
    assert summary.rotated_key_package_count == 3
    assert summary.failed_client_count == 0
    assert summary.skipped_client_count == 0
    assert summary.errors == []

    assert {:ok, stale_after} =
             ConversationSecurityClientInventoryStore.load(stale_client_id)

    assert {:ok, fresh_after} =
             ConversationSecurityClientInventoryStore.load(fresh_client_id)

    stale_after_refs =
      stale_after.key_packages
      |> Enum.map(&Map.fetch!(&1, "key_package_ref"))
      |> MapSet.new()

    fresh_after_refs =
      fresh_after.key_packages
      |> Enum.map(&Map.fetch!(&1, "key_package_ref"))
      |> MapSet.new()

    refute MapSet.equal?(stale_before_refs, stale_after_refs)
    assert MapSet.equal?(fresh_before_refs, fresh_after_refs)
  end

  test "rotate_stale_inventories fails closed when any stale client rotation fails" do
    failing_client_id = "client-policy-rotate-batch-fail"
    success_client_id = "client-policy-rotate-batch-ok"

    assert {:ok, _} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               failing_client_id,
               target_count: 3,
               replenish_threshold: 1,
               rotation_interval_seconds: 60
             )

    assert {:ok, _} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               success_client_id,
               target_count: 3,
               replenish_threshold: 1,
               rotation_interval_seconds: 60
             )

    stale_time = DateTime.add(DateTime.utc_now(:microsecond), -120, :second)

    {failing_count, _rows} =
      Repo.update_all(
        from(i in ConversationSecurityClientInventory,
          where: i.client_id in [^failing_client_id, ^success_client_id]
        ),
        set: [updated_at: stale_time]
      )

    assert failing_count == 2

    Application.put_env(
      :famichat,
      :mls_adapter,
      PartiallyFailingKeyPackageAdapter
    )

    assert {:error, :storage_inconsistent, details} =
             ConversationSecurityKeyPackagePolicy.rotate_stale_inventories(
               rotation_interval_seconds: 60,
               batch_limit: 20,
               target_count: 3,
               replenish_threshold: 1
             )

    assert details[:reason] == :partial_rotation_failure
    assert details[:failed_client_count] == 1
    assert details[:rotated_client_count] == 1
    assert details[:scanned_count] == 2
  end

  test "key package lifecycle telemetry is emitted without payload leakage" do
    client_id = "client-policy-telemetry"

    events = [
      [
        :famichat,
        :chat,
        :conversation_security,
        :key_package_policy,
        :ensure_inventory
      ],
      [
        :famichat,
        :chat,
        :conversation_security,
        :key_package_policy,
        :consume_key_package
      ],
      [
        :famichat,
        :chat,
        :conversation_security,
        :key_package_policy,
        :rotate_stale_inventories
      ]
    ]

    stale_time = DateTime.add(DateTime.utc_now(:microsecond), -120, :second)

    captured_events =
      TelemetryHelpers.capture(events, fn ->
        assert {:ok, _} =
                 ConversationSecurityKeyPackagePolicy.ensure_inventory(
                   client_id,
                   target_count: 2,
                   replenish_threshold: 1,
                   rotation_interval_seconds: 60
                 )

        assert {:ok, _} =
                 ConversationSecurityKeyPackagePolicy.consume_key_package(
                   client_id,
                   target_count: 2,
                   replenish_threshold: 1,
                   rotation_interval_seconds: 60
                 )

        {count, _rows} =
          Repo.update_all(
            from(i in ConversationSecurityClientInventory,
              where: i.client_id == ^client_id
            ),
            set: [updated_at: stale_time]
          )

        assert count == 1

        assert {:ok, _} =
                 ConversationSecurityKeyPackagePolicy.rotate_stale_inventories(
                   rotation_interval_seconds: 60,
                   batch_limit: 20,
                   target_count: 2,
                   replenish_threshold: 1
                 )
      end)

    assert Enum.any?(captured_events, &(&1.event == Enum.at(events, 0)))
    assert Enum.any?(captured_events, &(&1.event == Enum.at(events, 1)))
    assert Enum.any?(captured_events, &(&1.event == Enum.at(events, 2)))

    Enum.each(captured_events, fn %{metadata: metadata} ->
      assert metadata[:result] in [:ok, :error]
      refute metadata_contains_key_package_fields?(metadata)
      refute Map.has_key?(metadata, :errors)
      refute Map.has_key?(metadata, :client_id)
    end)
  end

  test "policy rejects rotation interval below minimum bound" do
    assert {:error, :invalid_input, details} =
             ConversationSecurityKeyPackagePolicy.ensure_inventory(
               "client-policy-invalid-rotation",
               target_count: 2,
               replenish_threshold: 1,
               rotation_interval_seconds: 10
             )

    assert details[:reason] == :invalid_rotation_interval_seconds
  end

  defp metadata_contains_key_package_fields?(metadata) when is_map(metadata) do
    disallowed_fields =
      MapSet.new([:key_package, :key_packages, :key_package_ref])

    metadata
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.disjoint?(disallowed_fields)
    |> Kernel.not()
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
