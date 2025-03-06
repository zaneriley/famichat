defmodule FamichatWeb.MessageTestController do
  @moduledoc """
  Test controller for verifying message broadcasting functionality.
  This controller is intended for development and testing purposes only.
  """
  use FamichatWeb, :controller
  require Logger

  @doc """
  Broadcasts a test message to a specified conversation.

  ## Parameters
    * `type` - The conversation type (e.g., "self", "direct", "group", "family")
    * `id` - The conversation ID
    * `body` - The message content
    * `encryption` - (Optional) Boolean indicating if the message should include encryption metadata

  ## Response
    * 200 - Message broadcast successfully
    * 400 - Missing required parameters
  """
  def broadcast(conn, params) do
    with {:ok, type} <- Map.fetch(params, "type"),
         {:ok, id} <- Map.fetch(params, "id"),
         {:ok, body} <- Map.fetch(params, "body"),
         true <- type in ["self", "direct", "group", "family", "legacy"] do
      broadcast_payload = %{
        "body" => body,
        "user_id" => "TEST_USER"
      }

      # Add encryption metadata if requested
      broadcast_payload =
        if Map.get(params, "encryption", false) do
          Map.merge(broadcast_payload, %{
            "version_tag" => "v1.0.0",
            "encryption_flag" => true,
            "key_id" => "KEY_TEST_v1"
          })
        else
          broadcast_payload
        end

      # Determine the topic based on the type
      topic =
        if type == "legacy" do
          "message:#{id}"
        else
          "message:#{type}:#{id}"
        end

      Logger.info("Broadcasting test message to topic: #{topic}")
      Logger.debug("Broadcast payload: #{inspect(broadcast_payload)}")

      FamichatWeb.Endpoint.broadcast!(topic, "new_msg", broadcast_payload)

      json(conn, %{
        status: "ok",
        message: "Broadcast sent to #{topic}"
      })
    else
      :error ->
        conn
        |> put_status(400)
        |> json(%{
          status: "error",
          message:
            "Required parameters: type, id, body. Optional: encryption (boolean)"
        })

      false ->
        conn
        |> put_status(400)
        |> json(%{
          status: "error",
          message: "Type must be one of: self, direct, group, family, legacy"
        })
    end
  end
end
