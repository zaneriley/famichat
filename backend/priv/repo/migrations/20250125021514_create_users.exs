defmodule Famichat.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true, autogenerate: true
      add :username, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:username])
  end
end
