defmodule Famichat.Repo.Migrations.AddPasskeyDueAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :passkey_due_at, :utc_datetime_usec
    end
  end
end
