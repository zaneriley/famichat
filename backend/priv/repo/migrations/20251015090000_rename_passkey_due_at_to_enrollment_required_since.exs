defmodule Famichat.Repo.Migrations.RenamePasskeyDueAtOnUsers do
  use Ecto.Migration

  def up do
    rename(
      table(:users),
      :passkey_due_at,
      to: :enrollment_required_since
    )
  end

  def down do
    rename(
      table(:users),
      :enrollment_required_since,
      to: :passkey_due_at
    )
  end
end
