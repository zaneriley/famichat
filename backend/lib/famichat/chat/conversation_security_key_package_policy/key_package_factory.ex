defmodule Famichat.Chat.ConversationSecurityKeyPackagePolicy.KeyPackageFactory do
  @moduledoc false

  alias Famichat.Crypto.MLS

  @spec generate_key_packages(String.t(), integer()) ::
          {:ok, [map()]} | {:error, atom(), map()}
  def generate_key_packages(_client_id, count) when count <= 0, do: {:ok, []}

  def generate_key_packages(client_id, count) do
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
end
