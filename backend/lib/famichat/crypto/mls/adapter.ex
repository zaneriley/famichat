defmodule Famichat.Crypto.MLS.Adapter do
  @moduledoc """
  Behavior contract for MLS operations behind the Elixir wrapper.
  """

  @type payload :: map()
  @type error_code :: atom()
  @type error_details :: map()
  @type result :: {:ok, payload()} | {:error, error_code(), error_details()}

  @callback nif_version() :: result()
  @callback nif_health() :: result()
  @callback create_key_package(map()) :: result()
  @callback create_group(map()) :: result()
  @callback join_from_welcome(map()) :: result()
  @callback process_incoming(map()) :: result()
  @callback commit_to_pending(map()) :: result()
  @callback mls_commit(map()) :: result()
  @callback mls_update(map()) :: result()
  @callback mls_add(map()) :: result()
  @callback mls_remove(map()) :: result()
  @callback merge_staged_commit(map()) :: result()
  @callback clear_pending_commit(map()) :: result()
  @callback create_application_message(map()) :: result()
  @callback export_group_info(map()) :: result()
  @callback export_ratchet_tree(map()) :: result()
end
