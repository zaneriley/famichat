defmodule Famichat.Repo.Migrations.AddPendingStatusToUsers do
  use Ecto.Migration

  def up do
    # The users.status column is stored as :string (see accounts_phase_one
    # migration), so no ALTER TYPE is needed. The `:pending` value is added
    # purely at the application layer via Ecto.Enum.
    #
    # Add a nullable reference to the registration token that created this
    # pending user. Used for idempotent re-entry and cleanup queries.
    alter table(:users) do
      add :registration_token_id,
          references(:user_tokens, type: :binary_id, on_delete: :nilify_all),
          null: true
    end

    create index(:users, [:registration_token_id])

    create index(:users, [:status],
             where: "status = 'pending'",
             name: :users_pending_status_index
           )
  end

  def down do
    drop_if_exists index(:users, [:status], name: :users_pending_status_index)
    drop_if_exists index(:users, [:registration_token_id])

    alter table(:users) do
      remove :registration_token_id
    end
  end
end
