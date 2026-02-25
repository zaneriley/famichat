defmodule Famichat.Crypto.MLS.NifBridge do
  @moduledoc false

  use Rustler,
    otp_app: :famichat,
    crate: "mls_nif",
    path: "infra/mls_nif",
    mode: if(Mix.env() == :prod, do: :release, else: :debug)

  @spec nif_version() :: {:ok, map()} | {:error, atom(), map()}
  def nif_version, do: :erlang.nif_error(:nif_not_loaded)

  @spec nif_health() :: {:ok, map()} | {:error, atom(), map()}
  def nif_health, do: :erlang.nif_error(:nif_not_loaded)

  @spec create_key_package(map()) :: {:ok, map()} | {:error, atom(), map()}
  def create_key_package(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec create_group(map()) :: {:ok, map()} | {:error, atom(), map()}
  def create_group(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec join_from_welcome(map()) :: {:ok, map()} | {:error, atom(), map()}
  def join_from_welcome(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec process_incoming(map()) :: {:ok, map()} | {:error, atom(), map()}
  def process_incoming(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec commit_to_pending(map()) :: {:ok, map()} | {:error, atom(), map()}
  def commit_to_pending(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec mls_commit(map()) :: {:ok, map()} | {:error, atom(), map()}
  def mls_commit(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec mls_update(map()) :: {:ok, map()} | {:error, atom(), map()}
  def mls_update(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec mls_add(map()) :: {:ok, map()} | {:error, atom(), map()}
  def mls_add(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec mls_remove(map()) :: {:ok, map()} | {:error, atom(), map()}
  def mls_remove(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec merge_staged_commit(map()) :: {:ok, map()} | {:error, atom(), map()}
  def merge_staged_commit(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec clear_pending_commit(map()) :: {:ok, map()} | {:error, atom(), map()}
  def clear_pending_commit(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec create_application_message(map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def create_application_message(_params),
    do: :erlang.nif_error(:nif_not_loaded)

  @spec export_group_info(map()) :: {:ok, map()} | {:error, atom(), map()}
  def export_group_info(_params), do: :erlang.nif_error(:nif_not_loaded)

  @spec export_ratchet_tree(map()) :: {:ok, map()} | {:error, atom(), map()}
  def export_ratchet_tree(_params), do: :erlang.nif_error(:nif_not_loaded)
end
