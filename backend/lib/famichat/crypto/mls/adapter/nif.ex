defmodule Famichat.Crypto.MLS.Adapter.Nif do
  @moduledoc """
  Rust NIF-backed MLS adapter.
  """

  @behaviour Famichat.Crypto.MLS.Adapter

  alias Famichat.Crypto.MLS.NifBridge

  @nif_operations [
    :create_key_package,
    :create_group,
    :join_from_welcome,
    :process_incoming,
    :commit_to_pending,
    :mls_commit,
    :mls_update,
    :mls_add,
    :mls_remove,
    :merge_staged_commit,
    :clear_pending_commit,
    :create_application_message,
    :export_group_info,
    :export_ratchet_tree,
    :list_member_credentials
  ]

  @impl true
  def nif_version, do: call_0(:nif_version)

  @impl true
  def nif_health, do: call_0(:nif_health)

  @impl true
  def create_key_package(params), do: call_1(:create_key_package, params)

  @impl true
  def create_group(params), do: call_1(:create_group, params)

  @impl true
  def join_from_welcome(params), do: call_1(:join_from_welcome, params)

  @impl true
  def process_incoming(params), do: call_1(:process_incoming, params)

  @impl true
  def commit_to_pending(params), do: call_1(:commit_to_pending, params)

  @impl true
  def mls_commit(params), do: call_1(:mls_commit, params)

  @impl true
  def mls_update(params), do: call_1(:mls_update, params)

  @impl true
  def mls_add(params), do: call_1(:mls_add, params)

  @impl true
  def mls_remove(params), do: call_1(:mls_remove, params)

  @impl true
  def merge_staged_commit(params), do: call_1(:merge_staged_commit, params)

  @impl true
  def clear_pending_commit(params), do: call_1(:clear_pending_commit, params)

  @impl true
  def create_application_message(params),
    do: call_1(:create_application_message, params)

  @impl true
  def export_group_info(params), do: call_1(:export_group_info, params)

  @impl true
  def export_ratchet_tree(params), do: call_1(:export_ratchet_tree, params)

  @impl true
  def list_member_credentials(params),
    do: call_1(:list_member_credentials, params)

  defp call_0(operation) do
    try do
      apply(NifBridge, operation, [])
    rescue
      error in ErlangError ->
        nif_error(operation, error)
    end
  end

  defp call_1(operation, params) when operation in @nif_operations do
    payload = stringify_payload(params)

    try do
      apply(NifBridge, operation, [payload])
    rescue
      error in ErlangError ->
        nif_error(operation, error)
    end
  end

  defp stringify_payload(params) when is_map(params) do
    Enum.reduce(params, %{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc ->
        Map.put(acc, stringify_key(key), stringify_value(value))
    end)
  end

  defp stringify_payload(_params), do: %{}

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key) when is_binary(key), do: key
  defp stringify_key(key), do: to_string(key)

  defp stringify_value(value) when is_binary(value), do: value
  defp stringify_value(value) when is_boolean(value), do: to_string(value)
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)

  defp stringify_value(value) when is_integer(value),
    do: Integer.to_string(value)

  defp stringify_value(value) when is_float(value) do
    :erlang.float_to_binary(value, [:compact])
  end

  defp stringify_value(value) when is_map(value) or is_list(value) do
    Jason.encode!(value)
  end

  defp stringify_value(value), do: inspect(value)

  defp nif_error(operation, %{original: :nif_not_loaded}) do
    {:error, :unsupported_capability,
     %{operation: operation, reason: :nif_not_loaded}}
  end

  defp nif_error(operation, _error) do
    {:error, :crypto_failure, %{operation: operation, reason: :nif_call_failed}}
  end
end
