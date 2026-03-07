defmodule Famichat.Crypto.MLS.Adapter.Unimplemented do
  @moduledoc """
  Placeholder adapter used until the Rust NIF bridge is implemented.
  """

  @behaviour Famichat.Crypto.MLS.Adapter

  @impl true
  def nif_version, do: not_implemented(:nif_version)

  @impl true
  def nif_health, do: not_implemented(:nif_health)

  @impl true
  def create_key_package(_params), do: not_implemented(:create_key_package)

  @impl true
  def create_group(_params), do: not_implemented(:create_group)

  @impl true
  def join_from_welcome(_params), do: not_implemented(:join_from_welcome)

  @impl true
  def process_incoming(_params), do: not_implemented(:process_incoming)

  @impl true
  def commit_to_pending(_params), do: not_implemented(:commit_to_pending)

  @impl true
  def mls_commit(_params), do: not_implemented(:mls_commit)

  @impl true
  def mls_update(_params), do: not_implemented(:mls_update)

  @impl true
  def mls_add(_params), do: not_implemented(:mls_add)

  @impl true
  def mls_remove(_params), do: not_implemented(:mls_remove)

  @impl true
  def merge_staged_commit(_params), do: not_implemented(:merge_staged_commit)

  @impl true
  def clear_pending_commit(_params), do: not_implemented(:clear_pending_commit)

  @impl true
  def create_application_message(_params),
    do: not_implemented(:create_application_message)

  @impl true
  def export_group_info(_params), do: not_implemented(:export_group_info)

  @impl true
  def export_ratchet_tree(_params), do: not_implemented(:export_ratchet_tree)

  @impl true
  def list_member_credentials(_params),
    do: not_implemented(:list_member_credentials)

  defp not_implemented(operation) do
    {:error, :unsupported_capability,
     %{reason: :not_implemented, operation: operation}}
  end
end
