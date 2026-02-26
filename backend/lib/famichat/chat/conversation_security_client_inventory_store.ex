defmodule Famichat.Chat.ConversationSecurityClientInventoryStore do
  @moduledoc """
  Chat-owned persistence boundary for durable client key-package inventory.
  """
  import Ecto.Query, warn: false

  alias Famichat.Chat.ConversationSecurityClientInventory
  alias Famichat.Repo
  alias Famichat.Vault

  @max_client_id_length 128
  @payload_format "vault_term_v1"
  @default_protocol "mls"
  @default_replenish_threshold 2
  @default_target_count 5

  @type record_payload :: %{
          client_id: String.t(),
          protocol: String.t(),
          key_packages: [map()],
          available_count: non_neg_integer(),
          replenish_threshold: pos_integer(),
          target_count: pos_integer(),
          lock_version: pos_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @spec load(String.t()) :: {:ok, record_payload()} | {:error, atom(), map()}
  def load(client_id)
      when is_binary(client_id) and byte_size(client_id) > 0 and
             byte_size(client_id) <= @max_client_id_length do
    case Repo.get(ConversationSecurityClientInventory, client_id) do
      %ConversationSecurityClientInventory{} = record ->
        decode_record(record)

      nil ->
        {:error, :not_found, %{reason: :missing_inventory}}
    end
  end

  def load(_client_id) do
    {:error, :invalid_input, %{reason: :invalid_client_id, operation: :load}}
  end

  @spec upsert(String.t(), map(), pos_integer() | nil) ::
          {:ok, record_payload()} | {:error, atom(), map()}
  def upsert(client_id, attrs, expected_lock_version \\ nil)

  def upsert(client_id, attrs, expected_lock_version)
      when is_binary(client_id) and byte_size(client_id) > 0 and
             byte_size(client_id) <= @max_client_id_length and is_map(attrs) do
    with :ok <- validate_expected_lock_version(expected_lock_version),
         {:ok, encoded_attrs} <- encode_attrs(client_id, attrs) do
      do_upsert(client_id, encoded_attrs, expected_lock_version)
    end
  end

  def upsert(_client_id, _attrs, _expected_lock_version) do
    {:error, :invalid_input,
     %{reason: :invalid_upsert_input, operation: :upsert}}
  end

  @spec delete(String.t()) :: :ok | {:error, atom(), map()}
  def delete(client_id)
      when is_binary(client_id) and byte_size(client_id) > 0 and
             byte_size(client_id) <= @max_client_id_length do
    _ =
      Repo.delete_all(
        from i in ConversationSecurityClientInventory,
          where: i.client_id == ^client_id
      )

    :ok
  end

  def delete(_client_id) do
    {:error, :invalid_input, %{reason: :invalid_client_id, operation: :delete}}
  end

  @spec list_stale_client_ids(DateTime.t(), pos_integer()) ::
          {:ok, [String.t()]} | {:error, atom(), map()}
  def list_stale_client_ids(cutoff, limit \\ 100)

  def list_stale_client_ids(cutoff, limit)
      when is_struct(cutoff, DateTime) and is_integer(limit) and limit >= 1 do
    client_ids =
      from(i in ConversationSecurityClientInventory,
        where: i.updated_at <= ^cutoff,
        order_by: [asc: i.updated_at, asc: i.client_id],
        limit: ^limit,
        select: i.client_id
      )
      |> Repo.all()

    {:ok, client_ids}
  rescue
    _ ->
      {:error, :storage_inconsistent,
       %{
         reason: :list_stale_clients_failed,
         operation: :list_stale_client_ids
       }}
  end

  def list_stale_client_ids(_cutoff, _limit) do
    {:error, :invalid_input,
     %{
       reason: :invalid_list_stale_client_ids_input,
       operation: :list_stale_client_ids
     }}
  end

  defp validate_expected_lock_version(nil), do: :ok

  defp validate_expected_lock_version(value)
       when is_integer(value) and value >= 1,
       do: :ok

  defp validate_expected_lock_version(_value) do
    {:error, :invalid_input,
     %{reason: :invalid_expected_lock_version, operation: :upsert}}
  end

  defp encode_attrs(client_id, attrs) do
    key_packages =
      Map.get(attrs, :key_packages) || Map.get(attrs, "key_packages")

    protocol =
      Map.get(attrs, :protocol) || Map.get(attrs, "protocol") ||
        @default_protocol

    replenish_threshold =
      Map.get(attrs, :replenish_threshold) ||
        Map.get(attrs, "replenish_threshold") || @default_replenish_threshold

    target_count =
      Map.get(attrs, :target_count) || Map.get(attrs, "target_count") ||
        @default_target_count

    with {:ok, key_packages_payload} <- normalize_key_packages(key_packages),
         :ok <- validate_protocol(protocol),
         :ok <- validate_replenish_threshold(replenish_threshold),
         :ok <- validate_target_count(target_count),
         :ok <- validate_threshold_pair(replenish_threshold, target_count),
         {:ok, key_packages_ciphertext} <- encode_payload(key_packages_payload) do
      {:ok,
       %{
         client_id: client_id,
         protocol: protocol,
         key_packages_ciphertext: key_packages_ciphertext,
         key_packages_format: @payload_format,
         available_count: length(key_packages_payload),
         replenish_threshold: replenish_threshold,
         target_count: target_count
       }}
    end
  end

  defp normalize_key_packages(key_packages) when is_list(key_packages) do
    if Enum.all?(key_packages, &valid_key_package?/1) do
      {:ok, key_packages}
    else
      {:error, :invalid_input,
       %{reason: :invalid_key_packages_payload, operation: :upsert}}
    end
  end

  defp normalize_key_packages(_invalid) do
    {:error, :invalid_input,
     %{reason: :missing_or_invalid_key_packages, operation: :upsert}}
  end

  defp valid_key_package?(key_package) when is_map(key_package) do
    case Map.get(key_package, "key_package_ref") do
      value when is_binary(value) and byte_size(value) > 0 ->
        true

      _ ->
        false
    end
  end

  defp valid_key_package?(_key_package), do: false

  defp validate_protocol(protocol)
       when is_binary(protocol) and byte_size(protocol) > 0,
       do: :ok

  defp validate_protocol(_protocol) do
    {:error, :invalid_input, %{reason: :invalid_protocol, operation: :upsert}}
  end

  defp validate_replenish_threshold(value)
       when is_integer(value) and value >= 1,
       do: :ok

  defp validate_replenish_threshold(_value) do
    {:error, :invalid_input,
     %{reason: :invalid_replenish_threshold, operation: :upsert}}
  end

  defp validate_target_count(value) when is_integer(value) and value >= 1,
    do: :ok

  defp validate_target_count(_value) do
    {:error, :invalid_input,
     %{reason: :invalid_target_count, operation: :upsert}}
  end

  defp validate_threshold_pair(replenish_threshold, target_count)
       when target_count > replenish_threshold,
       do: :ok

  defp validate_threshold_pair(_replenish_threshold, _target_count) do
    {:error, :invalid_input,
     %{reason: :invalid_threshold_pair, operation: :upsert}}
  end

  defp encode_payload(payload) do
    ciphertext =
      payload
      |> :erlang.term_to_binary([:compressed])
      |> Vault.encrypt!()

    {:ok, ciphertext}
  rescue
    _ ->
      {:error, :state_encode_failed,
       %{reason: :state_encode_failed, operation: :upsert}}
  end

  defp decode_payload(ciphertext) when is_binary(ciphertext) do
    with decrypted when is_binary(decrypted) <- Vault.decrypt!(ciphertext),
         decoded <- :erlang.binary_to_term(decrypted, [:safe]),
         true <- is_list(decoded),
         true <- Enum.all?(decoded, &is_map/1) do
      {:ok, decoded}
    else
      _ ->
        {:error, :state_decode_failed,
         %{reason: :state_decode_failed, operation: :load}}
    end
  rescue
    _ ->
      {:error, :state_decode_failed,
       %{reason: :state_decode_failed, operation: :load}}
  end

  defp decode_payload(_ciphertext) do
    {:error, :state_decode_failed,
     %{reason: :state_decode_failed, operation: :load}}
  end

  defp decode_record(%ConversationSecurityClientInventory{} = record) do
    with {:ok, key_packages} <- decode_payload(record.key_packages_ciphertext),
         :ok <-
           validate_available_count(
             record.available_count,
             key_packages,
             record.client_id
           ) do
      {:ok,
       %{
         client_id: record.client_id,
         protocol: record.protocol,
         key_packages: key_packages,
         available_count: record.available_count,
         replenish_threshold: record.replenish_threshold,
         target_count: record.target_count,
         lock_version: record.lock_version,
         inserted_at: record.inserted_at,
         updated_at: record.updated_at
       }}
    end
  end

  defp validate_available_count(available_count, key_packages, _client_id)
       when available_count == length(key_packages),
       do: :ok

  defp validate_available_count(_available_count, _key_packages, _client_id) do
    {:error, :state_decode_failed,
     %{reason: :inventory_count_mismatch, operation: :load}}
  end

  defp do_upsert(client_id, encoded_attrs, nil) do
    now = DateTime.utc_now(:microsecond)

    insert_attrs =
      encoded_attrs
      |> Map.put(:lock_version, 1)
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)

    {inserted_count, _rows} =
      Repo.insert_all(
        ConversationSecurityClientInventory,
        [insert_attrs],
        on_conflict: :nothing,
        conflict_target: [:client_id]
      )

    if inserted_count == 1 do
      load(client_id)
    else
      {:error, :stale_state, %{reason: :concurrent_insert}}
    end
  end

  defp do_upsert(client_id, encoded_attrs, expected_lock_version) do
    now = DateTime.utc_now(:microsecond)
    next_lock_version = expected_lock_version + 1

    {updated_count, _rows} =
      Repo.update_all(
        from(i in ConversationSecurityClientInventory,
          where:
            i.client_id == ^client_id and
              i.lock_version == ^expected_lock_version
        ),
        set: [
          protocol: encoded_attrs.protocol,
          key_packages_ciphertext: encoded_attrs.key_packages_ciphertext,
          key_packages_format: encoded_attrs.key_packages_format,
          available_count: encoded_attrs.available_count,
          replenish_threshold: encoded_attrs.replenish_threshold,
          target_count: encoded_attrs.target_count,
          lock_version: next_lock_version,
          updated_at: now
        ]
      )

    if updated_count == 1 do
      load(client_id)
    else
      {:error, :stale_state, %{reason: :lock_version_mismatch}}
    end
  end
end
