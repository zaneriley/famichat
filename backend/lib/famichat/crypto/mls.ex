defmodule Famichat.Crypto.MLS do
  @moduledoc """
  Elixir-facing MLS wrapper.

  This module defines a stable contract before the Rust NIF adapter is wired.
  """

  use Boundary, top_level?: true, deps: [Famichat], exports: :all

  alias Famichat.Crypto.MLS.Adapter.Unimplemented

  @telemetry_prefix [:famichat, :crypto, :mls]

  @error_codes [
    :invalid_input,
    :unauthorized_operation,
    :stale_epoch,
    :pending_proposals,
    :commit_rejected,
    :storage_inconsistent,
    :crypto_failure,
    :unsupported_capability,
    # N1: Distinct atom for a poisoned Mutex/RwLock — a concurrency failure,
    # not a storage integrity issue. Callers must NOT attempt state-repair
    # recovery for this code; the correct response is to surface the error
    # and let the supervisor restart the affected process.
    :lock_poisoned
  ]

  @sensitive_error_key_atoms [
    :ciphertext,
    :key_material,
    :plaintext,
    :private_key,
    :secret,
    :seed,
    :raw_result
  ]
  @sensitive_error_key_strings Enum.map(
                                 @sensitive_error_key_atoms,
                                 &Atom.to_string/1
                               )

  @spec nif_version() :: {:ok, map()} | {:error, atom(), map()}
  def nif_version, do: call_0(:nif_version)

  @spec nif_health() :: {:ok, map()} | {:error, atom(), map()}
  def nif_health, do: call_0(:nif_health)

  @spec create_key_package(map()) :: {:ok, map()} | {:error, atom(), map()}
  def create_key_package(params), do: call_1(:create_key_package, params)

  @spec create_group(map()) :: {:ok, map()} | {:error, atom(), map()}
  def create_group(params), do: call_1(:create_group, params)

  @spec join_from_welcome(map()) :: {:ok, map()} | {:error, atom(), map()}
  def join_from_welcome(params), do: call_1(:join_from_welcome, params)

  @spec process_incoming(map()) :: {:ok, map()} | {:error, atom(), map()}
  def process_incoming(params), do: call_1(:process_incoming, params)

  @spec commit_to_pending(map()) :: {:ok, map()} | {:error, atom(), map()}
  def commit_to_pending(params), do: call_1(:commit_to_pending, params)

  @spec mls_commit(map()) :: {:ok, map()} | {:error, atom(), map()}
  def mls_commit(params), do: call_1(:mls_commit, params)

  @spec mls_update(map()) :: {:ok, map()} | {:error, atom(), map()}
  def mls_update(params), do: call_1(:mls_update, params)

  @spec mls_add(map()) :: {:ok, map()} | {:error, atom(), map()}
  def mls_add(params), do: call_1(:mls_add, params)

  @spec mls_remove(map()) :: {:ok, map()} | {:error, atom(), map()}
  def mls_remove(params), do: call_1(:mls_remove, params)

  @doc """
  Resolves a device ID to an MLS leaf index by calling `list_member_credentials`
  and matching on credential identity.

  Returns `{:ok, leaf_index}` or `{:error, code, details}`.
  """
  @spec resolve_leaf_index(map(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, atom(), map()}
  def resolve_leaf_index(group_params, device_id)
      when is_map(group_params) and is_binary(device_id) do
    with {:ok, payload} <- list_member_credentials(group_params) do
      credentials_str =
        Map.get(payload, "credentials") || Map.get(payload, :credentials, "")

      case find_leaf_index(credentials_str, device_id) do
        {:ok, index} ->
          {:ok, index}

        :not_found ->
          {:error, :commit_rejected,
           %{reason: :client_not_in_group, device_id: device_id}}
      end
    end
  end

  defp find_leaf_index(credentials_str, device_id)
       when is_binary(credentials_str) do
    device_id_hex = Base.encode16(device_id, case: :lower)

    credentials_str
    |> String.split(",", trim: true)
    |> Enum.find_value(:not_found, fn entry ->
      case String.split(entry, ":", parts: 2) do
        [index_str, hex_identity] when hex_identity == device_id_hex ->
          case Integer.parse(index_str) do
            {index, ""} -> {:ok, index}
            _ -> nil
          end

        _ ->
          nil
      end
    end)
  end

  @spec merge_staged_commit(map()) :: {:ok, map()} | {:error, atom(), map()}
  def merge_staged_commit(params), do: call_1(:merge_staged_commit, params)

  @spec clear_pending_commit(map()) :: {:ok, map()} | {:error, atom(), map()}
  def clear_pending_commit(params), do: call_1(:clear_pending_commit, params)

  @spec create_application_message(map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def create_application_message(params),
    do: call_1(:create_application_message, params)

  @spec export_group_info(map()) :: {:ok, map()} | {:error, atom(), map()}
  def export_group_info(params), do: call_1(:export_group_info, params)

  @spec export_ratchet_tree(map()) :: {:ok, map()} | {:error, atom(), map()}
  def export_ratchet_tree(params), do: call_1(:export_ratchet_tree, params)

  @spec list_member_credentials(map()) :: {:ok, map()} | {:error, atom(), map()}
  def list_member_credentials(params),
    do: call_1(:list_member_credentials, params)

  defp call_0(operation), do: call_adapter(operation, [])

  defp call_1(_operation, params) when not is_map(params) do
    {:error, :invalid_input, %{reason: "params must be a map"}}
  end

  defp call_1(operation, params) do
    with :ok <- validate_required_params(operation, params),
         :ok <- enforce_protocol_invariants(operation, params) do
      call_adapter(operation, [params])
    end
  end

  defp call_adapter(operation, args) do
    :telemetry.span(
      @telemetry_prefix ++ [operation],
      %{operation: operation},
      fn ->
        result = do_call_adapter(operation, args)
        {result, telemetry_metadata(result)}
      end
    )
  end

  defp do_call_adapter(operation, args) do
    adapter = adapter_module()

    try do
      case apply(adapter, operation, args) do
        {:ok, payload} when is_map(payload) ->
          {:ok, payload}

        {:error, code, details} when is_atom(code) and is_map(details) ->
          normalize_error(operation, code, details)

        {:error, code} when is_atom(code) ->
          normalize_error(operation, code, %{})

        _result ->
          {:error, :unsupported_capability,
           %{operation: operation, reason: :invalid_adapter_response}}
      end
    rescue
      UndefinedFunctionError ->
        {:error, :unsupported_capability,
         %{operation: operation, reason: :adapter_not_configured}}

      _exception ->
        {:error, :crypto_failure,
         %{operation: operation, cause: :adapter_exception}}
    end
  end

  defp adapter_module do
    Application.get_env(:famichat, :mls_adapter, Unimplemented)
  end

  defp validate_required_params(:create_group, params) do
    details =
      %{}
      |> put_missing(:group_id, params)
      |> put_missing(:ciphersuite, params)

    if details == %{} do
      :ok
    else
      {:error, :invalid_input, details}
    end
  end

  defp validate_required_params(_operation, _params), do: :ok

  defp enforce_protocol_invariants(
         :create_application_message,
         params
       ) do
    if fetch_param(params, :pending_proposals) == true do
      {:error, :pending_proposals,
       %{operation: :create_application_message, reason: :pending_proposals}}
    else
      :ok
    end
  end

  defp enforce_protocol_invariants(
         :merge_staged_commit,
         params
       ) do
    if fetch_param(params, :staged_commit_validated) == true do
      :ok
    else
      {:error, :commit_rejected,
       %{
         operation: :merge_staged_commit,
         reason: :staged_commit_not_validated
       }}
    end
  end

  defp enforce_protocol_invariants(
         :process_incoming,
         params
       ) do
    incoming_type =
      fetch_param(params, :incoming_type) || fetch_param(params, :message_type)

    pending_commit = fetch_param(params, :pending_commit)

    if pending_commit == true and incoming_type in [:welcome, "welcome"] do
      {:error, :commit_rejected,
       %{
         operation: :process_incoming,
         reason: :welcome_before_commit_merge
       }}
    else
      :ok
    end
  end

  defp enforce_protocol_invariants(_operation, _params), do: :ok

  defp put_missing(details, key, params) do
    atom_value = fetch_param(params, key)
    string_value = fetch_param(params, Atom.to_string(key))

    if is_nil(atom_value) and is_nil(string_value) do
      Map.put(details, key, "is required")
    else
      details
    end
  end

  defp normalize_error(_operation, code, details) when code in @error_codes do
    {:error, code, redact_sensitive_details(details)}
  end

  defp normalize_error(operation, code, _details) do
    {:error, :crypto_failure, %{operation: operation, cause: code}}
  end

  defp telemetry_metadata({:ok, _payload}), do: %{result: :ok}

  defp telemetry_metadata({:error, code, _details}) do
    %{result: :error, error_code: code}
  end

  defp fetch_param(params, key) when is_atom(key) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  defp fetch_param(params, key) when is_binary(key) do
    Map.get(params, key)
  end

  defp redact_sensitive_details(details) do
    redact_sensitive_value(details)
  end

  defp redact_sensitive_value(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      if sensitive_error_key?(key) do
        acc
      else
        Map.put(acc, key, redact_sensitive_value(nested_value))
      end
    end)
  end

  defp redact_sensitive_value(value) when is_list(value) do
    Enum.map(value, &redact_sensitive_value/1)
  end

  defp redact_sensitive_value(value), do: value

  defp sensitive_error_key?(key) when is_atom(key) do
    key in @sensitive_error_key_atoms
  end

  defp sensitive_error_key?(key) when is_binary(key) do
    key in @sensitive_error_key_strings
  end

  defp sensitive_error_key?(_key), do: false
end
