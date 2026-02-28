defmodule Famichat.Repo.Migrations.AddSnapshotMacToConversationSecurityStates do
  use Ecto.Migration

  def change do
    alter table(:conversation_security_states) do
      add :snapshot_mac, :string, null: true
    end
  end
end
