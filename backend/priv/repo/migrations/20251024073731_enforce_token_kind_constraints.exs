defmodule Famichat.Repo.Migrations.EnforceTokenKindConstraints do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @kinds ~w(invite pair_qr pair_admin_code passkey_reg passkey_assert magic_link otp recovery)

  def up do
    execute(update_existing_rows_sql())

    alter table(:user_tokens) do
      modify :kind, :string, null: false
      modify :audience, :string, null: false
    end

    execute("DROP INDEX CONCURRENTLY IF EXISTS user_tokens_context_token_hash_index")

    create unique_index(:user_tokens, [:kind, :token_hash],
             concurrently: true,
             name: :user_tokens_kind_token_hash_index
           )

    execute(
      "ALTER TABLE user_tokens ADD CONSTRAINT user_tokens_kind_check CHECK (kind = ANY (ARRAY['" <>
        Enum.join(@kinds, "','") <> "']))"
    )
  end

  def down do
    execute("ALTER TABLE user_tokens DROP CONSTRAINT IF EXISTS user_tokens_kind_check")

    execute("DROP INDEX CONCURRENTLY IF EXISTS user_tokens_kind_token_hash_index")

    execute(
      "CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS user_tokens_context_token_hash_index ON user_tokens (context, token_hash)"
    )

    alter table(:user_tokens) do
      modify :kind, :string, null: true
      modify :audience, :string, null: true
    end
  end

  defp update_existing_rows_sql do
    """
    UPDATE user_tokens
    SET
      kind = COALESCE(kind, CASE
        WHEN context = 'invite' THEN 'invite'
        WHEN context = 'magic_link' THEN 'magic_link'
        WHEN context = 'recovery' THEN 'recovery'
        WHEN context = 'passkey_register' THEN 'passkey_reg'
        WHEN context = 'passkey_register_challenge' THEN 'passkey_reg'
        WHEN context = 'passkey_assert_challenge' THEN 'passkey_assert'
        WHEN context = 'pair' AND payload->>'mode' = 'qr' THEN 'pair_qr'
        WHEN context = 'pair' AND payload->>'mode' = 'admin_code' THEN 'pair_admin_code'
        WHEN context LIKE 'otp:%' THEN 'otp'
        ELSE kind
      END),
      audience = COALESCE(audience, CASE
        WHEN context IN ('invite', 'magic_link', 'passkey_register', 'passkey_register_challenge', 'passkey_assert_challenge', 'otp') THEN 'user'
        WHEN context = 'recovery' THEN 'admin'
        WHEN context = 'pair' THEN 'device'
        ELSE audience
      END),
      subject_id = COALESCE(subject_id, CASE
        WHEN context LIKE 'otp:%' THEN substring(context FROM 5)
        WHEN context IN ('magic_link', 'recovery', 'passkey_register', 'passkey_register_challenge', 'passkey_assert_challenge') THEN payload->>'user_id'
        ELSE subject_id
      END)
    """
  end
end
