defmodule Famichat.Chat.ConversationSecurityClientInventory do
  @moduledoc """
  Durable conversation-security inventory record per client identity.

  Write owner: `Famichat.Chat.ConversationSecurityClientInventoryStore`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          client_id: String.t(),
          protocol: String.t(),
          key_packages_ciphertext: binary(),
          key_packages_format: String.t(),
          available_count: non_neg_integer(),
          replenish_threshold: pos_integer(),
          target_count: pos_integer(),
          lock_version: pos_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key false
  schema "conversation_security_client_inventories" do
    field :client_id, :string, primary_key: true
    field :protocol, :string, default: "mls"
    field :key_packages_ciphertext, :binary
    field :key_packages_format, :string, default: "vault_term_v1"
    field :available_count, :integer, default: 0
    field :replenish_threshold, :integer, default: 2
    field :target_count, :integer, default: 5
    field :lock_version, :integer, default: 1

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec create_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(record, attrs) do
    record
    |> cast(attrs, [
      :client_id,
      :protocol,
      :key_packages_ciphertext,
      :key_packages_format,
      :available_count,
      :replenish_threshold,
      :target_count,
      :lock_version
    ])
    |> validate_required([
      :client_id,
      :protocol,
      :key_packages_ciphertext,
      :key_packages_format,
      :available_count,
      :replenish_threshold,
      :target_count,
      :lock_version
    ])
    |> validate_number(:available_count, greater_than_or_equal_to: 0)
    |> validate_number(:replenish_threshold, greater_than_or_equal_to: 1)
    |> validate_number(:target_count, greater_than_or_equal_to: 1)
    |> validate_number(:lock_version, greater_than_or_equal_to: 1)
  end
end
