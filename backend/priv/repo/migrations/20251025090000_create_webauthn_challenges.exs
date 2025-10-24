defmodule Famichat.Repo.Migrations.CreateWebauthnChallenges do
  use Ecto.Migration

  def change do
    create table(:webauthn_challenges, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :type, :string, null: false
      add :challenge, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:webauthn_challenges, [:user_id])
    create index(:webauthn_challenges, [:type])
    create index(:webauthn_challenges, [:expires_at])
    create index(:webauthn_challenges, [:consumed_at])
    create index(:webauthn_challenges, [:user_id, :type, :expires_at])
  end
end
