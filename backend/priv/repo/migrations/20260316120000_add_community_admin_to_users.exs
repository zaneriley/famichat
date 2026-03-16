defmodule Famichat.Repo.Migrations.AddCommunityAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :community_admin, :boolean, default: false, null: false
    end
  end
end
