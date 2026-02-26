defmodule Famichat.Auth.Runtime.AuditLog do
  @moduledoc """
  Persistent audit trail for authentication actions (write owner: `Famichat.Auth.Runtime.Audit`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "auth_audit_logs" do
    field :event, :string
    field :actor_id, :binary_id
    field :subject_id, :binary_id
    field :household_id, :binary_id
    field :scope, :string
    field :metadata, :map, default: %{}

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @cast_fields [
    :event,
    :actor_id,
    :subject_id,
    :household_id,
    :scope,
    :metadata
  ]
  @required_fields [:event, :scope]

  @doc false
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_length(:event, max: 100)
    |> validate_length(:scope, max: 50)
    |> validate_metadata()
    |> put_default_metadata()
  end

  defp validate_metadata(changeset) do
    validate_change(changeset, :metadata, fn :metadata, value ->
      if is_map(value) do
        []
      else
        [metadata: "must be a map"]
      end
    end)
  end

  defp put_default_metadata(changeset) do
    case get_field(changeset, :metadata) do
      nil -> put_change(changeset, :metadata, %{})
      _ -> changeset
    end
  end
end
