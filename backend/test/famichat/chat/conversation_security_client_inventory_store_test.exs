defmodule Famichat.Chat.ConversationSecurityClientInventoryStoreTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.{
    ConversationSecurityClientInventory,
    ConversationSecurityClientInventoryStore
  }

  alias Famichat.Repo

  test "load returns not_found when inventory does not exist" do
    assert {:error, :not_found, details} =
             ConversationSecurityClientInventoryStore.load("client-missing")

    assert details[:reason] == :missing_inventory
  end

  test "upsert persists and loads client key-package inventory" do
    key_packages = [%{"key_package_ref" => "kp:client-1:1"}]

    assert {:ok, persisted} =
             ConversationSecurityClientInventoryStore.upsert(
               "client-1",
               %{
                 protocol: "mls",
                 key_packages: key_packages,
                 replenish_threshold: 1,
                 target_count: 3
               },
               nil
             )

    assert persisted.client_id == "client-1"
    assert persisted.protocol == "mls"
    assert persisted.key_packages == key_packages
    assert persisted.available_count == 1
    assert persisted.replenish_threshold == 1
    assert persisted.target_count == 3
    assert persisted.lock_version == 1

    assert {:ok, loaded} =
             ConversationSecurityClientInventoryStore.load("client-1")

    assert loaded == persisted
  end

  test "upsert enforces optimistic locking and reports stale_state on conflict" do
    assert {:ok, first} =
             ConversationSecurityClientInventoryStore.upsert(
               "client-lock",
               %{
                 key_packages: [%{"key_package_ref" => "kp:client-lock:1"}],
                 replenish_threshold: 1,
                 target_count: 2
               },
               nil
             )

    assert {:ok, second} =
             ConversationSecurityClientInventoryStore.upsert(
               "client-lock",
               %{
                 key_packages: [
                   %{"key_package_ref" => "kp:client-lock:2"},
                   %{"key_package_ref" => "kp:client-lock:3"}
                 ],
                 replenish_threshold: 1,
                 target_count: 3
               },
               first.lock_version
             )

    assert second.lock_version == first.lock_version + 1
    assert second.available_count == 2

    assert {:error, :stale_state, details} =
             ConversationSecurityClientInventoryStore.upsert(
               "client-lock",
               %{
                 key_packages: [%{"key_package_ref" => "kp:client-lock:4"}],
                 replenish_threshold: 1,
                 target_count: 3
               },
               first.lock_version
             )

    assert details[:reason] == :lock_version_mismatch
  end

  test "load fails closed when persisted key-package payload is tampered" do
    assert {:ok, _persisted} =
             ConversationSecurityClientInventoryStore.upsert(
               "client-tamper",
               %{
                 key_packages: [%{"key_package_ref" => "kp:client-tamper:1"}],
                 replenish_threshold: 1,
                 target_count: 2
               },
               nil
             )

    {count, _rows} =
      Repo.update_all(
        from(i in ConversationSecurityClientInventory,
          where: i.client_id == "client-tamper"
        ),
        set: [key_packages_ciphertext: <<1, 2, 3>>]
      )

    assert count == 1

    assert {:error, :state_decode_failed, details} =
             ConversationSecurityClientInventoryStore.load("client-tamper")

    assert details[:reason] == :state_decode_failed
    assert details[:operation] == :load
  end

  test "load fails closed when available_count does not match persisted payload size" do
    assert {:ok, _persisted} =
             ConversationSecurityClientInventoryStore.upsert(
               "client-count-mismatch",
               %{
                 key_packages: [%{"key_package_ref" => "kp:count:1"}],
                 replenish_threshold: 1,
                 target_count: 2
               },
               nil
             )

    {count, _rows} =
      Repo.update_all(
        from(i in ConversationSecurityClientInventory,
          where: i.client_id == "client-count-mismatch"
        ),
        set: [available_count: 5]
      )

    assert count == 1

    assert {:error, :state_decode_failed, details} =
             ConversationSecurityClientInventoryStore.load(
               "client-count-mismatch"
             )

    assert details[:reason] == :inventory_count_mismatch
    assert details[:operation] == :load
  end

  test "upsert rejects non-positive replenish_threshold" do
    assert {:error, :invalid_input, details} =
             ConversationSecurityClientInventoryStore.upsert(
               "client-threshold-invalid",
               %{
                 key_packages: [%{"key_package_ref" => "kp:client-threshold:1"}],
                 replenish_threshold: 0,
                 target_count: 2
               },
               nil
             )

    assert details[:reason] == :invalid_replenish_threshold
  end

  test "upsert rejects key packages missing key_package_ref" do
    assert {:error, :invalid_input, details} =
             ConversationSecurityClientInventoryStore.upsert(
               "client-invalid-package",
               %{
                 key_packages: [%{"unexpected" => "value"}],
                 replenish_threshold: 1,
                 target_count: 2
               },
               nil
             )

    assert details[:reason] == :invalid_key_packages_payload
  end

  test "load rejects oversized client_id input" do
    oversized_client_id = String.duplicate("a", 129)

    assert {:error, :invalid_input, details} =
             ConversationSecurityClientInventoryStore.load(oversized_client_id)

    assert details[:reason] == :invalid_client_id
  end
end
