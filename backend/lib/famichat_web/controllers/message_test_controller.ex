defmodule FamichatWeb.MessageTestController do
  @moduledoc """
  Test controller for verifying message broadcasting functionality.
  This controller is intended for development and testing purposes only.
  """
  use FamichatWeb, :controller
  require Logger

  @doc """
  Broadcasts a test message to a specified room.

  ## Parameters
    * `room` - The room to broadcast to (e.g., "lobby")
    * `body` - The message content
    * `encryption` - (Optional) Boolean indicating if the message should include encryption metadata

  ## Response
    * 200 - Message broadcast successfully
    * 400 - Missing required parameters
  """
  def broadcast(conn, params) do
    with {:ok, room} <- Map.fetch(params, "room"),
         {:ok, body} <- Map.fetch(params, "body") do
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

      Logger.info("Broadcasting test message to room: #{room}")
      Logger.debug("Broadcast payload: #{inspect(broadcast_payload)}")

      FamichatWeb.Endpoint.broadcast!("message:#{room}", "new_msg", broadcast_payload)

      json(conn, %{
        status: "ok",
        message: "Broadcast sent"
      })
    else
      :error ->
        conn
        |> put_status(400)
        |> json(%{
          status: "error",
          message: "Required parameters: room, body. Optional: encryption (boolean)"
        })
    end
  end
end
