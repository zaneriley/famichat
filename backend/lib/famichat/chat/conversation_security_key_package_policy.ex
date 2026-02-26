defmodule Famichat.Chat.ConversationSecurityKeyPackagePolicy do
  @moduledoc """
  Chat-domain policy for key-package inventory creation, consumption, and replenishment.
  """
  alias Famichat.Chat.ConversationSecurityClientInventoryStore
  alias Famichat.Chat.ConversationSecurityKeyPackagePolicy.KeyPackageFactory

  @max_client_id_length 128
  @default_protocol "mls"
  @default_replenish_threshold 2
  @default_target_count 5
  @default_rotation_interval_seconds 86_400
  @min_rotation_interval_seconds 60
  @default_rotation_batch_limit 100
  @max_rotation_batch_limit 1_000
  @max_stale_retries 24
  @base_retry_sleep_ms 1
  @max_retry_sleep_ms 10
  @telemetry_prefix [
    :famichat,
    :chat,
    :conversation_security,
    :key_package_policy
  ]

  @type policy_options :: [
          protocol: String.t(),
          replenish_threshold: pos_integer(),
          target_count: pos_integer(),
          rotation_interval_seconds: pos_integer()
        ]

  # Public API

  @spec ensure_inventory(String.t(), policy_options()) ::
          {:ok, map()} | {:error, atom(), map()}
  def ensure_inventory(client_id, opts \\ []) do
    capture_policy_result(:ensure_inventory, client_id, fn ->
      with {:ok, policy} <- normalize_policy(client_id, opts) do
        with_stale_retry(
          fn -> ensure_inventory_once(policy) end,
          @max_stale_retries
        )
      end
    end)
  end

  @spec consume_key_package(String.t(), policy_options()) ::
          {:ok, map()} | {:error, atom(), map()}
  def consume_key_package(client_id, opts \\ []) do
    capture_policy_result(:consume_key_package, client_id, fn ->
      with {:ok, policy} <- normalize_policy(client_id, opts) do
        with_stale_retry(
          fn -> consume_key_package_once(policy) end,
          @max_stale_retries
        )
      end
    end)
  end

  @spec rotate_stale_inventory(String.t(), policy_options()) ::
          {:ok, map()} | {:error, atom(), map()}
  def rotate_stale_inventory(client_id, opts \\ []) do
    capture_policy_result(:rotate_stale_inventory, client_id, fn ->
      with {:ok, policy} <- normalize_policy(client_id, opts) do
        with_stale_retry(
          fn -> rotate_stale_inventory_once(policy) end,
          @max_stale_retries
        )
      end
    end)
  end

  @spec rotate_stale_inventories(keyword()) ::
          {:ok, map()} | {:error, atom(), map()}
  def rotate_stale_inventories(opts \\ [])

  def rotate_stale_inventories(opts) when is_list(opts) do
    capture_policy_result(:rotate_stale_inventories, nil, fn ->
      with {:ok, interval_seconds} <- normalize_rotation_interval_seconds(opts),
           {:ok, batch_limit} <- normalize_rotation_batch_limit(opts),
           cutoff <-
             DateTime.add(
               DateTime.utc_now(:microsecond),
               -interval_seconds,
               :second
             ),
           {:ok, client_ids} <-
             ConversationSecurityClientInventoryStore.list_stale_client_ids(
               cutoff,
               batch_limit
             ) do
        case rotate_client_ids(client_ids, opts) do
          {:ok, summary} ->
            {:ok,
             summary
             |> Map.put(:scanned_count, length(client_ids))
             |> Map.put(:rotation_interval_seconds, interval_seconds)
             |> Map.put(:batch_limit, batch_limit)}

          {:error, code, details} ->
            {:error, code,
             details
             |> Map.put(:scanned_count, length(client_ids))
             |> Map.put(:rotation_interval_seconds, interval_seconds)
             |> Map.put(:batch_limit, batch_limit)}
        end
      end
    end)
  end

  def rotate_stale_inventories(_opts) do
    {:error, :invalid_input,
     %{
       reason: :invalid_rotate_stale_inventories_input,
       operation: :rotate_stale_inventories
     }}
  end

  # Policy Input Normalization and Validation

  defp normalize_policy(client_id, opts)
       when is_binary(client_id) and byte_size(client_id) > 0 and is_list(opts) do
    protocol = Keyword.get(opts, :protocol, @default_protocol)

    replenish_threshold =
      Keyword.get(opts, :replenish_threshold, @default_replenish_threshold)

    target_count = Keyword.get(opts, :target_count, @default_target_count)

    rotation_interval_seconds =
      Keyword.get(
        opts,
        :rotation_interval_seconds,
        @default_rotation_interval_seconds
      )

    with :ok <- validate_client_id(client_id),
         :ok <- validate_protocol(protocol),
         :ok <- validate_replenish_threshold(replenish_threshold),
         :ok <- validate_target_count(target_count),
         :ok <- validate_rotation_interval_seconds(rotation_interval_seconds),
         :ok <- validate_threshold_pair(replenish_threshold, target_count) do
      {:ok,
       %{
         client_id: client_id,
         protocol: protocol,
         replenish_threshold: replenish_threshold,
         target_count: target_count,
         rotation_interval_seconds: rotation_interval_seconds
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

  defp validate_rotation_interval_seconds(value)
       when is_integer(value) and value >= @min_rotation_interval_seconds,
       do: :ok

  defp validate_rotation_interval_seconds(_value) do
    {:error, :invalid_input,
     %{
       reason: :invalid_rotation_interval_seconds,
       operation: :key_package_policy
     }}
  end

  defp validate_threshold_pair(replenish_threshold, target_count)
       when target_count > replenish_threshold,
       do: :ok

  defp validate_threshold_pair(_replenish_threshold, _target_count) do
    {:error, :invalid_input,
     %{reason: :invalid_threshold_pair, operation: :key_package_policy}}
  end

  defp normalize_rotation_interval_seconds(opts) when is_list(opts) do
    opts
    |> Keyword.get(
      :rotation_interval_seconds,
      @default_rotation_interval_seconds
    )
    |> case do
      value
      when is_integer(value) and value >= @min_rotation_interval_seconds ->
        {:ok, value}

      _value ->
        {:error, :invalid_input,
         %{
           reason: :invalid_rotation_interval_seconds,
           operation: :rotate_stale_inventories
         }}
    end
  end

  defp normalize_rotation_batch_limit(opts) when is_list(opts) do
    opts
    |> Keyword.get(:batch_limit, @default_rotation_batch_limit)
    |> case do
      value
      when is_integer(value) and value >= 1 and
             value <= @max_rotation_batch_limit ->
        {:ok, value}

      _value ->
        {:error, :invalid_input,
         %{reason: :invalid_batch_limit, operation: :rotate_stale_inventories}}
    end
  end

  # Inventory Lifecycle

  defp ensure_inventory_once(policy) do
    case ConversationSecurityClientInventoryStore.load(policy.client_id) do
      {:ok, inventory} ->
        with {:ok, rotated_inventory, rotated_count} <-
               maybe_rotate_if_due(inventory, policy, :ensure) do
          maybe_replenish(rotated_inventory, policy, :ensure, rotated_count)
        end

      {:error, :not_found, _details} ->
        create_initial_inventory(policy)

      {:error, code, details} ->
        {:error, code, details}
    end
  end

  defp consume_key_package_once(policy) do
    with {:ok, inventory, rotated_count} <-
           ensure_inventory_for_consume(policy),
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
         rotated_count: rotated_count,
         replenished_count: replenished_count,
         lock_version: persisted.lock_version
       }}
    end
  end

  defp ensure_inventory_for_consume(policy) do
    case ConversationSecurityClientInventoryStore.load(policy.client_id) do
      {:ok, inventory} ->
        with {:ok, rotated_inventory, rotated_count} <-
               maybe_rotate_if_due(inventory, policy, :consume),
             {:ok, ensured_inventory} <-
               ensure_minimum_inventory(rotated_inventory, policy),
             :ok <- ensure_available_key_package(ensured_inventory) do
          {:ok, ensured_inventory, rotated_count}
        end

      {:error, :not_found, _details} ->
        with {:ok, inventory} <- create_initial_inventory_record(policy),
             :ok <- ensure_available_key_package(inventory) do
          {:ok, inventory, 0}
        end

      {:error, code, details} ->
        {:error, code, details}
    end
  end

  defp ensure_available_key_package(%{available_count: count})
       when is_integer(count) and count > 0,
       do: :ok

  defp ensure_available_key_package(_inventory) do
    {:error, :storage_inconsistent,
     %{reason: :key_package_depleted, operation: :consume_key_package}}
  end

  defp pop_key_package(%{key_packages: [key_package | remaining]}, _policy) do
    {:ok, key_package, remaining}
  end

  defp pop_key_package(_inventory, _policy) do
    {:error, :storage_inconsistent,
     %{reason: :key_package_depleted, operation: :consume_key_package}}
  end

  defp create_initial_inventory(policy) do
    with {:ok, persisted} <- create_initial_inventory_record(policy) do
      {:ok,
       %{
         client_id: persisted.client_id,
         protocol: persisted.protocol,
         available_count: persisted.available_count,
         replenish_threshold: persisted.replenish_threshold,
         target_count: persisted.target_count,
         created_count: policy.target_count,
         rotated_count: 0,
         replenished_count: 0,
         lock_version: persisted.lock_version
       }}
    end
  end

  defp create_initial_inventory_record(policy) do
    with {:ok, key_packages} <-
           generate_key_packages(policy.client_id, policy.target_count) do
      ConversationSecurityClientInventoryStore.upsert(
        policy.client_id,
        %{
          protocol: policy.protocol,
          key_packages: key_packages,
          replenish_threshold: policy.replenish_threshold,
          target_count: policy.target_count
        },
        nil
      )
    end
  end

  defp maybe_replenish(inventory, policy, operation, rotated_count) do
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
           rotated_count: rotated_count,
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
         rotated_count: rotated_count,
         replenished_count: 0,
         lock_version: inventory.lock_version,
         operation: operation
       }}
    end
  end

  defp maybe_rotate_if_due(inventory, policy, operation) do
    if stale_inventory?(inventory, policy.rotation_interval_seconds) do
      rotate_inventory(inventory, policy, operation)
    else
      {:ok, inventory, 0}
    end
  end

  defp stale_inventory?(
         %{updated_at: %DateTime{} = updated_at},
         rotation_interval_seconds
       )
       when is_integer(rotation_interval_seconds) and
              rotation_interval_seconds >= @min_rotation_interval_seconds do
    DateTime.diff(DateTime.utc_now(:microsecond), updated_at, :second) >=
      rotation_interval_seconds
  end

  defp stale_inventory?(_inventory, _rotation_interval_seconds), do: true

  defp rotate_inventory(inventory, policy, _operation) do
    with {:ok, key_packages} <-
           generate_key_packages(policy.client_id, policy.target_count),
         {:ok, persisted} <-
           ConversationSecurityClientInventoryStore.upsert(
             inventory.client_id,
             %{
               protocol: policy.protocol,
               key_packages: key_packages,
               replenish_threshold: policy.replenish_threshold,
               target_count: policy.target_count
             },
             inventory.lock_version
           ) do
      {:ok, persisted, policy.target_count}
    end
  end

  defp rotate_stale_inventory_once(policy) do
    case ConversationSecurityClientInventoryStore.load(policy.client_id) do
      {:ok, inventory} ->
        if stale_inventory?(inventory, policy.rotation_interval_seconds) do
          with {:ok, persisted, rotated_count} <-
                 rotate_inventory(inventory, policy, :rotate) do
            {:ok,
             %{
               client_id: persisted.client_id,
               available_count: persisted.available_count,
               lock_version: persisted.lock_version,
               rotated_count: rotated_count
             }}
          end
        else
          {:ok,
           %{
             client_id: inventory.client_id,
             available_count: inventory.available_count,
             lock_version: inventory.lock_version,
             rotated_count: 0
           }}
        end

      {:error, code, details} ->
        {:error, code, details}
    end
  end

  defp ensure_minimum_inventory(inventory, policy) do
    if inventory.available_count < policy.replenish_threshold do
      replenish_count = max(policy.target_count - inventory.available_count, 0)

      with {:ok, created_key_packages} <-
             generate_key_packages(policy.client_id, replenish_count) do
        merged_key_packages = inventory.key_packages ++ created_key_packages

        ConversationSecurityClientInventoryStore.upsert(
          inventory.client_id,
          %{
            protocol: policy.protocol,
            key_packages: merged_key_packages,
            replenish_threshold: policy.replenish_threshold,
            target_count: policy.target_count
          },
          inventory.lock_version
        )
      end
    else
      {:ok, inventory}
    end
  end

  # Batch Rotation

  defp rotate_client_ids(client_ids, opts) when is_list(client_ids) do
    summary =
      Enum.reduce(client_ids, initial_rotation_summary(), fn client_id, acc ->
        case rotate_client_id(client_id, opts) do
          {:ok, %{rotated_count: rotated_count}} when rotated_count > 0 ->
            %{acc | rotated_client_count: acc.rotated_client_count + 1}
            |> increment_rotated_key_package_count(rotated_count)

          {:ok, _result} ->
            %{acc | skipped_client_count: acc.skipped_client_count + 1}

          {:error, code, details} ->
            acc
            |> mark_rotation_failure(code)
            |> append_rotation_error(client_id, code, details)
        end
      end)

    normalized_summary = %{summary | errors: Enum.reverse(summary.errors)}

    if normalized_summary.failed_client_count > 0 do
      {:error, :storage_inconsistent,
       %{
         reason: :partial_rotation_failure,
         rotated_client_count: normalized_summary.rotated_client_count,
         rotated_key_package_count:
           normalized_summary.rotated_key_package_count,
         skipped_client_count: normalized_summary.skipped_client_count,
         failed_client_count: normalized_summary.failed_client_count
       }}
    else
      {:ok, normalized_summary}
    end
  end

  defp rotate_client_id(client_id, opts) do
    with {:ok, policy} <- normalize_policy(client_id, opts) do
      with_stale_retry(
        fn -> rotate_stale_inventory_once(policy) end,
        @max_stale_retries
      )
    end
  end

  defp initial_rotation_summary do
    %{
      rotated_client_count: 0,
      rotated_key_package_count: 0,
      skipped_client_count: 0,
      failed_client_count: 0,
      errors: []
    }
  end

  defp increment_rotated_key_package_count(summary, rotated_count) do
    %{
      summary
      | rotated_key_package_count:
          summary.rotated_key_package_count + rotated_count
    }
  end

  defp mark_rotation_failure(summary, _code) do
    %{summary | failed_client_count: summary.failed_client_count + 1}
  end

  defp append_rotation_error(summary, _client_id, code, details) do
    summarized_error = %{
      error_code: code,
      reason: summarize_reason(details)
    }

    %{summary | errors: [summarized_error | summary.errors]}
  end

  # Inventory Persistence Helpers

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

  # Key Package Generation

  defp generate_key_packages(client_id, count) do
    KeyPackageFactory.generate_key_packages(client_id, count)
  end

  # Telemetry

  defp capture_policy_result(event, client_id, fun) when is_function(fun, 0) do
    start_time = System.monotonic_time()
    result = fun.()

    :telemetry.execute(
      @telemetry_prefix ++ [event],
      %{duration: System.monotonic_time() - start_time},
      build_telemetry_metadata(client_id, result)
    )

    result
  end

  defp build_telemetry_metadata(client_id, {:ok, payload}) do
    %{
      result: :ok,
      client_ref: telemetry_client_ref(client_id),
      available_count: value_from_payload(payload, :available_count),
      created_count: value_from_payload(payload, :created_count),
      replenished_count: value_from_payload(payload, :replenished_count),
      rotated_count: value_from_payload(payload, :rotated_count),
      rotated_client_count: value_from_payload(payload, :rotated_client_count),
      rotated_key_package_count:
        value_from_payload(payload, :rotated_key_package_count),
      skipped_client_count: value_from_payload(payload, :skipped_client_count),
      failed_client_count: value_from_payload(payload, :failed_client_count),
      scanned_count: value_from_payload(payload, :scanned_count),
      batch_limit: value_from_payload(payload, :batch_limit),
      rotation_interval_seconds:
        value_from_payload(payload, :rotation_interval_seconds),
      error_count: payload_error_count(payload)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  defp build_telemetry_metadata(client_id, {:error, code, details}) do
    %{
      result: :error,
      client_ref: telemetry_client_ref(client_id),
      error_code: code,
      reason: summarize_reason(details),
      failed_client_count: value_from_payload(details, :failed_client_count),
      scanned_count: value_from_payload(details, :scanned_count),
      rotation_interval_seconds:
        value_from_payload(details, :rotation_interval_seconds),
      batch_limit: value_from_payload(details, :batch_limit)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  defp value_from_payload(payload, key) when is_map(payload) do
    Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
  end

  defp value_from_payload(_payload, _key), do: nil

  defp payload_error_count(payload) when is_map(payload) do
    errors = Map.get(payload, :errors) || Map.get(payload, "errors") || []

    if is_list(errors), do: length(errors), else: nil
  end

  defp payload_error_count(_payload), do: nil

  defp summarize_reason(details) when is_map(details) do
    Map.get(details, :reason) || Map.get(details, "reason")
  end

  defp summarize_reason(_details), do: nil

  defp telemetry_client_ref(client_id) when is_binary(client_id) do
    :crypto.hash(:sha256, client_id)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp telemetry_client_ref(_client_id), do: nil

  # Retry

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
