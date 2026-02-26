defmodule Famichat.Repo.Migrations.CreateConversationSecurityClientInventories do
  use Ecto.Migration

  def change do
    create table(:conversation_security_client_inventories, primary_key: false) do
      add :client_id, :string, primary_key: true, null: false
      add :protocol, :string, null: false, default: "mls"
      add :key_packages_ciphertext, :binary, null: false
      add :key_packages_format, :string, null: false, default: "vault_term_v1"
      add :available_count, :integer, null: false, default: 0
      add :replenish_threshold, :integer, null: false, default: 2
      add :target_count, :integer, null: false, default: 5
      add :lock_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(
             :conversation_security_client_inventories,
             :convo_sec_inv_available_non_negative,
             check: "available_count >= 0"
           )

    create constraint(
             :conversation_security_client_inventories,
             :convo_sec_inv_replenish_threshold_valid,
             check: "replenish_threshold >= 1"
           )

    create constraint(
             :conversation_security_client_inventories,
             :convo_sec_inv_target_count_positive,
             check: "target_count >= 1"
           )

    create constraint(
             :conversation_security_client_inventories,
             :convo_sec_inv_target_above_threshold,
             check: "target_count > replenish_threshold"
           )

    create constraint(
             :conversation_security_client_inventories,
             :convo_sec_inv_lock_version_positive,
             check: "lock_version >= 1"
           )

    create constraint(
             :conversation_security_client_inventories,
             :convo_sec_inv_protocol_not_blank,
             check: "char_length(protocol) > 0"
           )

    create constraint(
             :conversation_security_client_inventories,
             :convo_sec_inv_client_id_not_blank,
             check: "char_length(client_id) > 0"
           )

    create constraint(
             :conversation_security_client_inventories,
             :convo_sec_inv_client_id_length,
             check: "char_length(client_id) <= 128"
           )
  end
end
