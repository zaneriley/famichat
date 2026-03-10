defmodule FamichatWeb.MessagingDispatch do
  @moduledoc false

  alias Famichat.Accounts.User
  alias Famichat.Chat.{Message, MessageRateLimiter, MessageService}
  alias Famichat.Repo

  @encryption_metadata_fields ~w(version_tag encryption_flag key_id)

  @spec send_message(map(), Ecto.UUID.t()) :: {:ok, map()} | {:error, any()}
  def send_message(message_params, device_id) do
    with :ok <- MessageRateLimiter.check(message_params, device_id),
         {:ok, %Message{} = message} <-
           MessageService.send_message(message_params) do
      # Preload sender here so build_broadcast_payload can include sender_name
      # without a separate DB query. This is a web-layer concern (presentation
      # data for notifications), not a Chat domain concern.
      message = Repo.preload(message, :sender)
      {:ok, build_broadcast_payload(message, device_id)}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec build_broadcast_payload(Message.t(), Ecto.UUID.t()) :: map()
  def build_broadcast_payload(%Message{} = message, device_id) do
    encryption_metadata =
      message
      |> Map.get(:metadata, %{})
      |> Map.get("encryption", %{})
      |> Map.take(@encryption_metadata_fields)

    sender_name =
      case message.sender do
        %User{username: username} when is_binary(username) -> username
        _ -> nil
      end

    %{
      "message_id" => message.id,
      "body" => message.content,
      "user_id" => message.sender_id,
      "device_id" => device_id,
      "sender_name" => sender_name
    }
    |> Map.merge(encryption_metadata)
  end
end
