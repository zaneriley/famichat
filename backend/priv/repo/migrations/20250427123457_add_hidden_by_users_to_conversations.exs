defmodule Famichat.Repo.Migrations.AddHiddenByUsersToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :hidden_by_users, {:array, :binary_id}, null: false, default: []
    end

    # Add an index on the hidden_by_users array
    create index(:conversations, [:hidden_by_users], using: "gin")
  end
end
