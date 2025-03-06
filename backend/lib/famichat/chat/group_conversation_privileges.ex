defmodule Famichat.Chat.GroupConversationPrivileges do
  @moduledoc """
  Schema for tracking role-based permissions in group conversations.

  This schema tracks the roles (admin/member) of users in group conversations,
  separate from basic participation tracking. It includes audit information
  such as who granted the privilege and when it was granted.

  Key design principles:
  - Only applies to group conversations (not direct or self)
  - Tracks roles with admin/member enum values
  - Records who granted the privilege for audit purposes
  - Enforces uniqueness constraints to prevent duplicate privileges
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Famichat.Chat.{Conversation, User}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "group_conversation_privileges" do
    belongs_to :conversation, Conversation
    belongs_to :user, User
    belongs_to :granted_by, User, foreign_key: :granted_by_id

    field :role, Ecto.Enum, values: [:admin, :member]
    field :granted_at, :utc_datetime

    timestamps()
  end

  @doc """
  Creates a changeset for group conversation privileges.

  Required fields:
  - conversation_id
  - user_id
  - role (admin or member)

  Optional fields:
  - granted_by_id (who granted the privilege)
  - granted_at (when the privilege was granted, defaults to now)
  """
  def changeset(privilege, attrs) do
    now = DateTime.utc_now(:second)
    attrs = Map.put_new(attrs, :granted_at, now)

    privilege
    |> cast(attrs, [
      :conversation_id,
      :user_id,
      :role,
      :granted_by_id,
      :granted_at
    ])
    |> validate_required([:conversation_id, :user_id, :role, :granted_at])
    |> validate_inclusion(:role, [:admin, :member])
    |> unique_constraint([:conversation_id, :user_id],
      name: :group_conversation_privileges_conversation_id_user_id_index,
      message: "has already been taken",
      error_key: :conversation_id_user_id
    )
  end
end
