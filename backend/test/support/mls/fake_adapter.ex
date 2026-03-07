defmodule Famichat.TestSupport.MLS.FakeAdapter do
  @moduledoc false
  @behaviour Famichat.Crypto.MLS.Adapter

  @impl true
  def nif_version, do: {:ok, %{adapter: "fake", version: "0.0.0-test"}}

  @impl true
  def nif_health, do: {:ok, %{status: "ok"}}

  @impl true
  def create_key_package(params), do: respond(:create_key_package, params)

  @impl true
  def create_group(params), do: respond(:create_group, params)

  @impl true
  def join_from_welcome(params), do: respond(:join_from_welcome, params)

  @impl true
  def process_incoming(params), do: respond(:process_incoming, params)

  @impl true
  def commit_to_pending(params), do: respond(:commit_to_pending, params)

  @impl true
  def mls_commit(params), do: respond(:mls_commit, params)

  @impl true
  def mls_update(params), do: respond(:mls_update, params)

  @impl true
  def mls_add(params), do: respond(:mls_add, params)

  @impl true
  def mls_remove(params), do: respond(:mls_remove, params)

  @impl true
  def merge_staged_commit(params), do: respond(:merge_staged_commit, params)

  @impl true
  def clear_pending_commit(params), do: respond(:clear_pending_commit, params)

  @impl true
  def create_application_message(params),
    do: respond(:create_application_message, params)

  @impl true
  def export_group_info(params), do: respond(:export_group_info, params)

  @impl true
  def export_ratchet_tree(params), do: respond(:export_ratchet_tree, params)

  @impl true
  def list_member_credentials(params),
    do: respond(:list_member_credentials, params)

  defp respond(operation, params) when is_map(params) do
    case fetch_param(params, :raise_exception) do
      true ->
        raise "forced fake adapter exception for #{inspect(operation)}"

      _ ->
        maybe_forced_error(operation, params)
    end
  end

  defp maybe_forced_error(operation, params) do
    case fetch_param(params, :force_error) do
      code when is_atom(code) and not is_nil(code) ->
        {:error, code, build_error_details(operation, params)}

      _ ->
        maybe_forced_success(operation, params)
    end
  end

  defp maybe_forced_success(operation, params) do
    case fetch_param(params, :success_payload) do
      payload when is_map(payload) ->
        {:ok, payload}

      _ ->
        success(operation, params)
    end
  end

  defp success(:create_application_message, params) do
    body = fetch_param(params, :body) || ""

    {:ok,
     %{
       ciphertext: "ciphertext:#{body}",
       epoch: fetch_param(params, :epoch) || 1
     }}
  end

  defp success(:process_incoming, params) do
    ciphertext =
      fetch_param(params, :ciphertext) || fetch_param(params, :message) || ""

    {:ok,
     %{
       plaintext: "plaintext:#{ciphertext}",
       epoch: fetch_param(params, :epoch) || 1
     }}
  end

  defp success(:join_from_welcome, params) do
    token = fetch_param(params, :rejoin_token) || "welcome-token"
    group_id = fetch_param(params, :group_id) || "group:#{token}"

    sender_storage = Base.encode64("sender-storage:#{token}")
    recipient_storage = Base.encode64("recipient-storage:#{token}")
    sender_signer = Base.encode64("sender-signer:#{token}")
    recipient_signer = Base.encode64("recipient-signer:#{token}")

    {:ok,
     %{
       group_id: group_id,
       group_state_ref: "state:#{token}",
       audit_id: "audit:#{token}",
       epoch: 1,
       session_sender_storage: sender_storage,
       session_recipient_storage: recipient_storage,
       session_sender_signer: sender_signer,
       session_recipient_signer: recipient_signer,
       session_cache: ""
     }}
  end

  defp success(:create_key_package, params) do
    client_id = fetch_param(params, :client_id) || "fake-client"
    ref = System.unique_integer([:positive, :monotonic])

    {:ok,
     %{
       client_id: client_id,
       key_package_ref: "kp:#{client_id}:#{ref}",
       status: "created"
     }}
  end

  defp success(_operation, _params), do: {:ok, %{}}

  defp build_error_details(operation, params) do
    details =
      fetch_param(params, :error_details) ||
        %{}

    Map.put_new(details, :operation, operation)
  end

  defp fetch_param(params, key) when is_atom(key) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end
end
