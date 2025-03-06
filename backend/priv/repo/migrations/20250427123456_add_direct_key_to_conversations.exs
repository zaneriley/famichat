defmodule Famichat.Repo.Migrations.AddDirectKeyToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :direct_key, :string
    end

    create unique_index(:conversations, [:direct_key],
             name: :unique_direct_key_index,
             where: "conversation_type = 'direct'"
           )
  end
end
