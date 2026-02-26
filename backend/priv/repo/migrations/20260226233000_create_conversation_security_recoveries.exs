defmodule Famichat.Repo.Migrations.CreateConversationSecurityRecoveries do
  use Ecto.Migration

  def change do
    create table(:conversation_security_recoveries, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false

      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :recovery_ref, :string, null: false
      add :status, :string, null: false, default: "in_progress"
      add :recovery_reason, :string
      add :error_code, :string
      add :error_reason, :string
      add :recovered_epoch, :integer
      add :audit_id, :string
      add :group_state_ref, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :conversation_security_recoveries,
             [:conversation_id, :recovery_ref],
             name: :conversation_security_recoveries_conversation_ref_index
           )

    create index(
             :conversation_security_recoveries,
             [:conversation_id, :status]
           )

    create constraint(
             :conversation_security_recoveries,
             :conversation_security_recoveries_status_valid,
             check: "status IN ('in_progress', 'completed', 'failed')"
           )

    create constraint(
             :conversation_security_recoveries,
             :conversation_security_recoveries_recovery_ref_not_blank,
             check: "char_length(recovery_ref) > 0"
           )

    create constraint(
             :conversation_security_recoveries,
             :conversation_security_recoveries_recovered_epoch_non_negative,
             check: "recovered_epoch IS NULL OR recovered_epoch >= 0"
           )
  end
end
