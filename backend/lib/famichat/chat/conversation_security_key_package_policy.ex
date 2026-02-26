defmodule Famichat.Chat.ConversationSecurityKeyPackagePolicy do
  @moduledoc """
  Chat-domain policy for key-package inventory creation, consumption, and replenishment.
  """
  alias Famichat.Chat.ConversationSecurityClientInventoryStore
  alias Famichat.Crypto.MLS

  @max_client_id_length 128
  @default_protocol "mls"
  @default_replenish_threshold 2
  @default_target_count 5
  @max_stale_retries 24
  @base_retry_sleep_ms 1
  @max_retry_sleep_ms 10

  @type policy_options :: [
          protocol: String.t(),
          replenish_threshold: pos_integer(),
          target_count: pos_integer()
        ]

  @spec ensure_inventory(String.t(), policy_options()) ::
          {:ok, map()} | {:error, atom(), map()}
  def ensure_inventory(client_id, opts \\ []) do
    with {:ok, policy} <- normalize_policy(client_id, opts) do
      with_stale_retry(
        fn -> ensure_inventory_once(policy) end,
        @max_stale_retries
      )
    end
  end

  @spec consume_key_package(String.t(), policy_options()) ::
          {:ok, map()} | {:error, atom(), map()}
  def consume_key_package(client_id, opts \\ []) do
    with {:ok, policy} <- normalize_policy(client_id, opts) do
      with_stale_retry(
        fn -> consume_key_package_once(policy) end,
        @max_stale_retries
      )
    end
  end

  defp normalize_policy(client_id, opts)
       when is_binary(client_id) and byte_size(client_id) > 0 and is_list(opts) do
    protocol = Keyword.get(opts, :protocol, @default_protocol)

    replenish_threshold =
      Keyword.get(opts, :replenish_threshold, @default_replenish_threshold)

    target_count = Keyword.get(opts, :target_count, @default_target_count)

    with :ok <- validate_client_id(client_id),
         :ok <- validate_protocol(protocol),
         :ok <- validate_replenish_threshold(replenish_threshold),
         :ok <- validate_target_count(target_count),
         :ok <- validate_threshold_pair(replenish_threshold, target_count) do
      {:ok,
       %{
         client_id: client_id,
         protocol: protocol,
         replenish_threshold: replenish_threshold,
         target_count: target_count
       }}
    end
  end

  defp normalize_policy(_client_id, _opts) do
    {:error, :invalid_input,
     %{reason: :invalid_policy_input, operation: :key_package_policy}}
  end

  defp validate_protocol(protocol)
       when is_binary(protocol) and byte_size(protocol) > 0,
       do: :ok

  defp validate_protocol(_protocol) do
    {:error, :invalid_input,
     %{reason: :invalid_protocol, operation: :key_package_policy}}
  end

  defp validate_client_id(client_id)
       when byte_size(client_id) <= @max_client_id_length,
       do: :ok

  defp validate_client_id(_client_id) do
    {:error, :invalid_input,
     %{reason: :invalid_client_id, operation: :key_package_policy}}
  end

  defp validate_replenish_threshold(value)
       when is_integer(value) and value >= 1,
       do: :ok

  defp validate_replenish_threshold(_value) do
    {:error, :invalid_input,
     %{reason: :invalid_replenish_threshold, operation: :key_package_policy}}
  end

  defp validate_target_count(value) when is_integer(value) and value >= 1,
    do: :ok

  defp validate_target_count(_value) do
    {:error, :invalid_input,
     %{reason: :invalid_target_count, operation: :key_package_policy}}
  end

  defp validate_threshold_pair(replenish_threshold, target_count)
       when target_count > replenish_threshold,
       do: :ok

  defp validate_threshold_pair(_replenish_threshold, _target_count) do
    {:error, :invalid_input,
     %{reason: :invalid_threshold_pair, operation: :key_package_policy}}
  end

  defp ensure_inventory_once(policy) do
    case ConversationSecurityClientInventoryStore.load(policy.client_id) do
      {:ok, inventory} ->
        maybe_replenish(inventory, policy, :ensure)

      {:error, :not_found, _details} ->
        create_initial_inventory(policy)

      {:error, code, details} ->
        {:error, code, details}
    end
  end

  defp consume_key_package_once(policy) do
    with {:ok, inventory} <- ensure_inventory_for_consume(policy),
         {:ok, consumed_key_package, remaining_key_packages} <-
           pop_key_package(inventory, policy),
         {:ok, persisted, replenished_count} <-
           persist_remaining_inventory(
             inventory,
             remaining_key_packages,
             policy,
             :consume
           ) do
      {:ok,
       %{
         client_id: persisted.client_id,
         protocol: persisted.protocol,
         key_package: consumed_key_package,
         available_count: persisted.available_count,
         replenish_threshold: persisted.replenish_threshold,
         target_count: persisted.target_count,
         replenished_count: replenished_count,
         lock_version: persisted.lock_version
       }}
    end
  end

  defp ensure_inventory_for_consume(policy) do
    case ConversationSecurityClientInventoryStore.load(policy.client_id) do
      {:ok, %{available_count: count} = inventory}
      when is_integer(count) and count > 0 ->
        {:ok, inventory}

      {:ok, _inventory} ->
        refresh_inventory(policy)

      {:error, :not_found, _details} ->
        refresh_inventory(policy)

      {:error, code, details} ->
        {:error, code, details}
    end
  end

  defp refresh_inventory(policy) do
    with {:ok, _inventory_state} <- ensure_inventory_once(policy) do
      ConversationSecurityClientInventoryStore.load(policy.client_id)
    end
  end

  defp pop_key_package(%{key_packages: [key_package | remaining]}, _policy) do
    {:ok, key_package, remaining}
  end

  defp pop_key_package(_inventory, _policy) do
    {:error, :storage_inconsistent,
     %{reason: :key_package_depleted, operation: :consume_key_package}}
  end

  defp create_initial_inventory(policy) do
    with {:ok, key_packages} <-
           generate_key_packages(policy.client_id, policy.target_count),
         {:ok, persisted} <-
           ConversationSecurityClientInventoryStore.upsert(
             policy.client_id,
             %{
               protocol: policy.protocol,
               key_packages: key_packages,
               replenish_threshold: policy.replenish_threshold,
               target_count: policy.target_count
             },
             nil
           ) do
      {:ok,
       %{
         client_id: persisted.client_id,
         protocol: persisted.protocol,
         available_count: persisted.available_count,
         replenish_threshold: persisted.replenish_threshold,
         target_count: persisted.target_count,
         created_count: policy.target_count,
         replenished_count: 0,
         lock_version: persisted.lock_version
       }}
    end
  end

  defp maybe_replenish(inventory, policy, operation) do
    if inventory.available_count < policy.replenish_threshold do
      replenish_count = max(policy.target_count - inventory.available_count, 0)

      with {:ok, created_key_packages} <-
             generate_key_packages(policy.client_id, replenish_count),
           merged_key_packages <-
             inventory.key_packages ++ created_key_packages,
           {:ok, persisted} <-
             ConversationSecurityClientInventoryStore.upsert(
               inventory.client_id,
               %{
                 protocol: policy.protocol,
                 key_packages: merged_key_packages,
                 replenish_threshold: policy.replenish_threshold,
                 target_count: policy.target_count
               },
               inventory.lock_version
             ) do
        {:ok,
         %{
           client_id: persisted.client_id,
           protocol: persisted.protocol,
           available_count: persisted.available_count,
           replenish_threshold: persisted.replenish_threshold,
           target_count: persisted.target_count,
           created_count: 0,
           replenished_count: replenish_count,
           lock_version: persisted.lock_version,
           operation: operation
         }}
      end
    else
      {:ok,
       %{
         client_id: inventory.client_id,
         protocol: inventory.protocol,
         available_count: inventory.available_count,
         replenish_threshold: inventory.replenish_threshold,
         target_count: inventory.target_count,
         created_count: 0,
         replenished_count: 0,
         lock_version: inventory.lock_version,
         operation: operation
       }}
    end
  end

  defp persist_remaining_inventory(
         inventory,
         remaining_key_packages,
         policy,
         _operation
       ) do
    with {:ok, final_key_packages, replenished_count} <-
           maybe_replenished_packages(remaining_key_packages, policy),
         {:ok, persisted} <-
           ConversationSecurityClientInventoryStore.upsert(
             inventory.client_id,
             %{
               protocol: policy.protocol,
               key_packages: final_key_packages,
               replenish_threshold: policy.replenish_threshold,
               target_count: policy.target_count
             },
             inventory.lock_version
           ) do
      {:ok, persisted, replenished_count}
    end
  end

  defp maybe_replenished_packages(remaining_key_packages, policy) do
    if length(remaining_key_packages) < policy.replenish_threshold do
      replenish_count =
        max(policy.target_count - length(remaining_key_packages), 0)

      with {:ok, created_key_packages} <-
             generate_key_packages(policy.client_id, replenish_count) do
        {:ok, remaining_key_packages ++ created_key_packages, replenish_count}
      end
    else
      {:ok, remaining_key_packages, 0}
    end
  end

  defp generate_key_packages(_client_id, count) when count <= 0, do: {:ok, []}

  defp generate_key_packages(client_id, count) do
    1..count
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn _index, {:ok, acc, refs} ->
      params = %{client_id: client_id}

      reduce_generated_key_package(
        MLS.create_key_package(params),
        client_id,
        acc,
        refs
      )
    end)
    |> case do
      {:ok, generated, _refs} -> {:ok, Enum.reverse(generated)}
      other -> other
    end
  end

  defp reduce_generated_key_package(
         {:ok, key_package_payload},
         client_id,
         acc,
         refs
       )
       when is_map(key_package_payload) do
    with {:ok, normalized_payload, key_package_ref} <-
           normalize_generated_key_package(key_package_payload, client_id),
         :ok <- ensure_unique_key_package_ref(refs, key_package_ref) do
      {:cont,
       {:ok, [normalized_payload | acc], MapSet.put(refs, key_package_ref)}}
    else
      {:error, code, details} ->
        {:halt, {:error, code, details}}
    end
  end

  defp reduce_generated_key_package(
         {:ok, _invalid_payload},
         _client_id,
         _acc,
         _refs
       ) do
    {:halt,
     {:error, :storage_inconsistent,
      %{
        reason: :invalid_key_package_payload,
        operation: :create_key_package
      }}}
  end

  defp reduce_generated_key_package(
         {:error, code, details},
         _client_id,
         _acc,
         _refs
       ) do
    {:halt, {:error, code, details}}
  end

  defp ensure_unique_key_package_ref(refs, key_package_ref) do
    if MapSet.member?(refs, key_package_ref) do
      {:error, :storage_inconsistent,
       %{
         reason: :duplicate_key_package_ref,
         operation: :create_key_package
       }}
    else
      :ok
    end
  end

  defp normalize_generated_key_package(key_package_payload, client_id) do
    key_package_ref =
      Map.get(key_package_payload, "key_package_ref") ||
        Map.get(key_package_payload, :key_package_ref)

    if is_binary(key_package_ref) and byte_size(key_package_ref) > 0 do
      normalized_payload =
        key_package_payload
        |> Map.put("client_id", client_id)
        |> Map.put("key_package_ref", key_package_ref)

      {:ok, normalized_payload, key_package_ref}
    else
      {:error, :storage_inconsistent,
       %{reason: :invalid_key_package_payload, operation: :create_key_package}}
    end
  end

  defp with_stale_retry(fun, retries_left, attempt \\ 0)

  defp with_stale_retry(fun, retries_left, attempt) when retries_left >= 0 do
    case fun.() do
      {:error, :stale_state, _details} when retries_left > 0 ->
        Process.sleep(retry_sleep_ms(attempt))
        with_stale_retry(fun, retries_left - 1, attempt + 1)

      result ->
        result
    end
  end

  defp retry_sleep_ms(attempt) when is_integer(attempt) and attempt >= 0 do
    min(@max_retry_sleep_ms, @base_retry_sleep_ms * (attempt + 1))
  end
end
