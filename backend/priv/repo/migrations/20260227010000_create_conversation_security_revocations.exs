defmodule Famichat.Repo.Migrations.CreateConversationSecurityRevocations do
  use Ecto.Migration

  def change do
    create table(:conversation_security_revocations, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false

      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :revocation_ref, :string, null: false
      add :status, :string, null: false, default: "in_progress"
      add :subject_type, :string, null: false
      add :subject_id, :string, null: false
      add :revocation_reason, :string

      add :actor_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      add :error_code, :string
      add :error_reason, :string
      add :committed_epoch, :integer
      add :proposal_ref, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :conversation_security_revocations,
             [:conversation_id, :revocation_ref],
             name: :conversation_security_revocations_conversation_ref_index
           )

    create index(
             :conversation_security_revocations,
             [:conversation_id, :status]
           )

    create index(
             :conversation_security_revocations,
             [:subject_type, :subject_id, :status],
             name: :conversation_security_revocations_subject_status_index
           )

    create constraint(
             :conversation_security_revocations,
             :conversation_security_revocations_status_valid,
             check: "status IN ('in_progress', 'pending_commit', 'completed', 'failed')"
           )

    create constraint(
             :conversation_security_revocations,
             :conversation_security_revocations_subject_type_valid,
             check: "subject_type IN ('client', 'user')"
           )

    create constraint(
             :conversation_security_revocations,
             :conversation_security_revocations_revocation_ref_not_blank,
             check: "char_length(revocation_ref) > 0"
           )

    create constraint(
             :conversation_security_revocations,
             :conversation_security_revocations_committed_epoch_non_negative,
             check: "committed_epoch IS NULL OR committed_epoch >= 0"
           )
  end
end
