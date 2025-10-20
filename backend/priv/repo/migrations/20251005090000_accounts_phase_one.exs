defmodule Famichat.Repo.Migrations.AccountsPhaseOne do
  use Ecto.Migration

  def up do
    execute(~s/CREATE EXTENSION IF NOT EXISTS "pgcrypto";/)

    drop_if_exists(index(:users, [:email]))

    alter table(:users) do
      remove :email
      add :email, :binary
      add :email_fingerprint, :binary
      add :status, :string, null: false, default: "invited"
      add :password_hash, :string
      add :confirmed_at, :utc_datetime_usec
      add :last_login_at, :utc_datetime_usec
    end

    create unique_index(:users, [:email_fingerprint],
             name: :users_email_fingerprint_index,
             where: "email_fingerprint IS NOT NULL"
           )

    create index(:users, [:status])

    create table(:family_memberships, primary_key: false) do
      add :id, :binary_id,
        primary_key: true,
        default: fragment("gen_random_uuid()"),
        null: false

      add :family_id,
          references(:families, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :role, :string, null: false, default: "member"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:family_memberships, [:family_id, :user_id],
             name: :family_memberships_family_id_user_id_index
           )

    execute(~s/
    INSERT INTO family_memberships (family_id, user_id, role, inserted_at, updated_at)
    SELECT family_id, id, role, NOW(), NOW()
    FROM users
    WHERE family_id IS NOT NULL
    ON CONFLICT DO NOTHING
    /)

    create table(:user_tokens, primary_key: false) do
      add :id, :binary_id,
        primary_key: true,
        default: fragment("gen_random_uuid()"),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :context, :string, null: false
      add :token_hash, :binary, null: false
      add :payload, :map, null: false, default: %{}
      add :expires_at, :utc_datetime_usec, null: false
      add :used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_tokens, [:context, :token_hash],
             name: :user_tokens_context_token_hash_index
           )

    create index(:user_tokens, [:user_id, :context])
    create index(:user_tokens, [:expires_at])

    create table(:user_devices, primary_key: false) do
      add :id, :binary_id,
        primary_key: true,
        default: fragment("gen_random_uuid()"),
        null: false

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :device_id, :string, null: false
      add :refresh_token_hash, :binary
      add :previous_token_hash, :binary
      add :user_agent, :string
      add :ip, :string
      add :trusted_until, :utc_datetime_usec
      add :last_active_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_devices, [:device_id])
    create index(:user_devices, [:user_id])
    create index(:user_devices, [:revoked_at])

    create table(:passkeys, primary_key: false) do
      add :id, :binary_id,
        primary_key: true,
        default: fragment("gen_random_uuid()"),
        null: false

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :sign_count, :integer, default: 0
      add :aaguid, :binary
      add :label, :string
      add :last_used_at, :utc_datetime_usec
      add :disabled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:passkeys, [:credential_id])
    create index(:passkeys, [:user_id])
  end

  def down do
    drop_if_exists(index(:passkeys, [:credential_id]))
    drop_if_exists(index(:passkeys, [:user_id]))
    drop_if_exists table(:passkeys)

    drop_if_exists(index(:user_devices, [:revoked_at]))
    drop_if_exists(index(:user_devices, [:user_id]))
    drop_if_exists(index(:user_devices, [:device_id]))
    drop_if_exists table(:user_devices)

    drop_if_exists(index(:user_tokens, [:expires_at]))
    drop_if_exists(index(:user_tokens, [:user_id, :context]))
    drop_if_exists(index(:user_tokens, [:context, :token_hash]))
    drop_if_exists table(:user_tokens)

    drop_if_exists(index(:family_memberships, [:family_id, :user_id]))
    drop_if_exists table(:family_memberships)

    drop_if_exists(index(:users, [:status]))
    drop_if_exists(index(:users, [:email_fingerprint]))

    alter table(:users) do
      remove :last_login_at
      remove :confirmed_at
      remove :password_hash
      remove :status
      remove :email_fingerprint
      remove :email
      add :email, :string, null: false, default: ""
    end

    execute("UPDATE users SET email = NULL WHERE email = ''")

    create unique_index(:users, [:email])
  end
end
