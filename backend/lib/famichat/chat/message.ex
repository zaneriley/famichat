defmodule Famichat.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true} # Explicit primary key type if needed - defaults to UUID
  schema "messages" do
    field :message_type, :string, default: "text"
    field :content, :string
    field :media_url, :string
    field :metadata, :map, default: %{} # Added metadata field
    field :timestamp, :utc_datetime_usec
    belongs_to :sender, Famichat.Chat.User, foreign_key: :sender_id, type: :binary_id # Define belongs_to relationship

    timestamps(type: :utc_datetime_usec) # Keep timestamps type in timestamps macro as :utc_datetime_usec
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:message_type, :content, :media_url, :sender_id, :timestamp, :metadata]) # Include metadata in changeset
    |> validate_required([:message_type, :sender_id]) # content and media_url can be optional, but sender_id and type are required
    |> put_timestamp()
  end

  defp put_timestamp(changeset) do
    if get_field(changeset, :timestamp) do
      changeset
    else
      put_change(changeset, :timestamp, DateTime.utc_now())
    end
  end
end
