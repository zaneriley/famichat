defmodule Famichat.Repo.Migrations.CreateFamilies do
  use Ecto.Migration

  def change do
    create table(:families, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :settings, :map, default: fragment("'{}'::jsonb"), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:families, [:name])
  end
end
