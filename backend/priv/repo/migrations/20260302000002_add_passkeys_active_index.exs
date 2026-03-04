defmodule Famichat.Repo.Migrations.AddPasskeysActiveIndex do
  use Ecto.Migration

  def change do
    create index(:passkeys, [:user_id],
      where: "disabled_at IS NULL",
      name: :passkeys_user_id_active_index
    )
  end
end
