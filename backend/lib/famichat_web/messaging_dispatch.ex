defmodule FamichatWeb.MessagingDispatch do
  @moduledoc false

  alias Famichat.Chat.{Message, MessageRateLimiter, MessageService}

  @encryption_metadata_fields ~w(version_tag encryption_flag key_id)

  @spec send_message(map(), Ecto.UUID.t()) :: {:ok, map()} | {:error, any()}
  def send_message(message_params, device_id) do
    with :ok <- MessageRateLimiter.check(message_params, device_id),
         {:ok, %Message{} = message} <-
           MessageService.send_message(message_params) do
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

    %{
      "body" => message.content,
      "user_id" => message.sender_id,
      "device_id" => device_id
    }
    |> Map.merge(encryption_metadata)
  end
end
