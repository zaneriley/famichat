defmodule Famichat.Repo.Migrations.AddLocaleCheckConstraint do
  use Ecto.Migration

  def change do
    create constraint(:users, :locale_must_be_supported,
             check: "locale IS NULL OR locale IN ('en', 'ja')"
           )
  end
end
