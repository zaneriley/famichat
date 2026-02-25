defmodule Famichat.Repo.Migrations.CreateConversationSecurityStates do
  use Ecto.Migration

  def change do
    create table(:conversation_security_states, primary_key: false) do
      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          primary_key: true,
          null: false

      add :protocol, :string, null: false, default: "mls"
      add :state_ciphertext, :binary, null: false
      add :state_format, :string, null: false, default: "vault_term_v1"
      add :epoch, :integer, null: false, default: 0
      add :pending_commit_ciphertext, :binary
      add :pending_commit_format, :string
      add :lock_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(
             :conversation_security_states,
             :conversation_security_states_epoch_non_negative,
             check: "epoch >= 0"
           )

    create constraint(
             :conversation_security_states,
             :conversation_security_states_lock_version_positive,
             check: "lock_version >= 1"
           )

    create constraint(
             :conversation_security_states,
             :conversation_security_states_protocol_not_blank,
             check: "char_length(protocol) > 0"
           )
  end
end
