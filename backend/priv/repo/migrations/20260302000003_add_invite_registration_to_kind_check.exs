defmodule Famichat.Repo.Migrations.AddInviteRegistrationToKindCheck do
  use Ecto.Migration

  # The original constraint (20251024073731) was missing "invite_registration",
  # which is used by accept_invite/peek_invite in the onboarding flow.
  @new_kinds ~w(invite pair_qr pair_admin_code invite_registration passkey_reg passkey_assert magic_link otp recovery)
  @old_kinds ~w(invite pair_qr pair_admin_code passkey_reg passkey_assert magic_link otp recovery)

  def up do
    execute("ALTER TABLE user_tokens DROP CONSTRAINT IF EXISTS user_tokens_kind_check")

    execute(
      "ALTER TABLE user_tokens ADD CONSTRAINT user_tokens_kind_check CHECK (kind = ANY (ARRAY['" <>
        Enum.join(@new_kinds, "','") <> "']))"
    )
  end

  def down do
    execute("ALTER TABLE user_tokens DROP CONSTRAINT IF EXISTS user_tokens_kind_check")

    execute(
      "ALTER TABLE user_tokens ADD CONSTRAINT user_tokens_kind_check CHECK (kind = ANY (ARRAY['" <>
        Enum.join(@old_kinds, "','") <> "']))"
    )
  end
end
