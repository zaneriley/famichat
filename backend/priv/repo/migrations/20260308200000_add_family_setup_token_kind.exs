defmodule Famichat.Repo.Migrations.AddFamilySetupTokenKind do
  use Ecto.Migration

  def up do
    # Drop the old constraint first so the UPDATE statements below don't violate it.
    execute("""
    ALTER TABLE user_tokens DROP CONSTRAINT IF EXISTS user_tokens_kind_check
    """)

    # Canonicalize legacy short-form token kinds before adding the new constraint.
    # These renames match the aliases defined in Famichat.Auth.Tokens.Policy.
    execute("UPDATE user_tokens SET kind = 'passkey_registration' WHERE kind = 'passkey_reg'")
    execute("UPDATE user_tokens SET kind = 'passkey_assertion'    WHERE kind = 'passkey_assert'")
    execute("UPDATE user_tokens SET kind = 'session_refresh'      WHERE kind = 'device_refresh'")

    execute("""
    ALTER TABLE user_tokens ADD CONSTRAINT user_tokens_kind_check
      CHECK (kind IN (
        'invite', 'pair_qr', 'pair_admin_code', 'invite_registration',
        'passkey_registration', 'passkey_assertion', 'magic_link',
        'otp', 'recovery', 'access', 'session_refresh', 'channel_bootstrap',
        'family_setup'
      ))
    """)
  end

  def down do
    execute("""
    ALTER TABLE user_tokens DROP CONSTRAINT IF EXISTS user_tokens_kind_check
    """)

    execute("""
    ALTER TABLE user_tokens ADD CONSTRAINT user_tokens_kind_check
      CHECK (kind IN (
        'invite', 'pair_qr', 'pair_admin_code', 'invite_registration',
        'passkey_registration', 'passkey_assertion', 'magic_link',
        'otp', 'recovery', 'access', 'session_refresh', 'channel_bootstrap'
      ))
    """)
  end
end
