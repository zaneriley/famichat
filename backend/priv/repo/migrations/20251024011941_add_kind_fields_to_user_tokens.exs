defmodule Famichat.Repo.Migrations.AddKindFieldsToUserTokens do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    alter table(:user_tokens) do
      add :kind, :string
      add :audience, :string
      add :subject_id, :string
    end

    create index(:user_tokens, [:kind], concurrently: true)
    create index(:user_tokens, [:kind, :subject_id], concurrently: true)
  end

  def down do
    drop_if_exists index(:user_tokens, [:kind, :subject_id], concurrently: true)
    drop_if_exists index(:user_tokens, [:kind], concurrently: true)

    alter table(:user_tokens) do
      remove :subject_id
      remove :audience
      remove :kind
    end
  end
end
