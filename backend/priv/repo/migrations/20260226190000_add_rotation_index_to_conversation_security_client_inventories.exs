defmodule Famichat.Repo.Migrations.AddRotationIndexToConversationSecurityClientInventories do
  use Ecto.Migration

  def change do
    create index(
             :conversation_security_client_inventories,
             [:updated_at, :client_id],
             name: :convo_sec_inv_updated_at_client_id_idx
           )
  end
end
