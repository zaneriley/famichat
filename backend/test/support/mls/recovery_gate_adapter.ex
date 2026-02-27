defmodule Famichat.TestSupport.MLS.RecoveryGateAdapter do
  @moduledoc false
  @behaviour Famichat.Crypto.MLS.Adapter

  alias Famichat.TestSupport.MLS.FakeAdapter

  @snapshot_keys [
    "session_sender_storage",
    "session_recipient_storage",
    "session_sender_signer",
    "session_recipient_signer",
    "session_cache"
  ]
  @snapshot_atom_keys %{
    "session_sender_storage" => :session_sender_storage,
    "session_recipient_storage" => :session_recipient_storage,
    "session_sender_signer" => :session_sender_signer,
    "session_recipient_signer" => :session_recipient_signer,
    "session_cache" => :session_cache
  }

  @impl true
  def nif_version, do: FakeAdapter.nif_version()

  @impl true
  def nif_health, do: {:ok, %{status: "ok"}}

  @impl true
  def create_key_package(params), do: FakeAdapter.create_key_package(params)

  @impl true
  def create_group(params), do: FakeAdapter.create_group(params)

  @impl true
  def join_from_welcome(params) do
    token = fetch_param(params, :rejoin_token) || "welcome-token"
    group_id = fetch_param(params, :group_id) || "group:#{token}"

    {:ok,
     %{
       group_id: group_id,
       group_state_ref: "state:#{token}",
       audit_id: "audit:#{token}",
       epoch: 1,
       session_sender_storage: Base.encode64("sender-storage:#{token}"),
       session_recipient_storage: Base.encode64("recipient-storage:#{token}"),
       session_sender_signer: Base.encode64("sender-signer:#{token}"),
       session_recipient_signer: Base.encode64("recipient-signer:#{token}"),
       session_cache: ""
     }}
  end

  @impl true
  def process_incoming(params) do
    ciphertext =
      fetch_param(params, :ciphertext) || fetch_param(params, :message) || ""

    {:ok,
     %{
       plaintext: ciphertext,
       epoch: fetch_epoch(params)
     }}
  end

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
  def clear_pending_commit(params), do: FakeAdapter.clear_pending_commit(params)

  @impl true
  def create_application_message(params) do
    if fetch_param(params, :pending_proposals) == true do
      {:error, :pending_proposals,
       %{
         reason: :pending_proposals,
         operation: :create_application_message
       }}
    else
      do_create_application_message(params)
    end
  end

  defp do_create_application_message(params) do
    if snapshot_present?(params) do
      body = fetch_param(params, :body) || ""

      {:ok,
       %{
         ciphertext: body,
         epoch: fetch_epoch(params)
       }}
    else
      {:error, :storage_inconsistent,
       %{
         reason: :missing_group_state,
         operation: :create_application_message
       }}
    end
  end

  @impl true
  def export_group_info(params), do: FakeAdapter.export_group_info(params)

  @impl true
  def export_ratchet_tree(params), do: FakeAdapter.export_ratchet_tree(params)

  defp snapshot_present?(params) when is_map(params) do
    Enum.all?(@snapshot_keys, fn key ->
      case snapshot_value(params, key) do
        value when is_binary(value) -> true
        _ -> false
      end
    end)
  end

  defp snapshot_present?(_params), do: false

  defp snapshot_value(params, key) when is_binary(key) do
    atom_key = Map.get(@snapshot_atom_keys, key)

    case atom_key do
      nil -> Map.get(params, key)
      _ -> Map.get(params, key) || Map.get(params, atom_key)
    end
  end

  defp fetch_epoch(params) when is_map(params) do
    case fetch_param(params, :epoch) do
      value when is_integer(value) and value >= 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} when parsed >= 0 -> parsed
          _ -> 1
        end

      _ ->
        1
    end
  end

  defp fetch_epoch(_params), do: 1

  defp fetch_param(params, key) when is_atom(key) and is_map(params) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end
end
