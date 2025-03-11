defmodule FamichatWeb.TestBroadcastController do
  @moduledoc """
  Controller for triggering test broadcast events via CLI.

  This controller enables CLI-based testing of Phoenix channels and real-time events,
  particularly useful for validating encryption-aware message handling without requiring
  a browser or LiveView client.

  ## Use Cases

  - Testing real-time message broadcasting
  - Verifying encryption metadata handling
  - Validating telemetry instrumentation
  - Testing error cases with invalid encryption parameters

  ## Curl Examples

  Basic Message:
  ```bash
  curl -X POST http://localhost:8001/api/test/test_events \\
    -H "Content-Type: application/json" \\
    -d '{"type": "new_message", "topic": "message:direct:test-conversation-123", "sender": "CLITest", "content": "Hello from CLI!"}'
  ```

  With Encryption:
  ```bash
  curl -X POST http://localhost:8001/api/test/test_events \\
    -H "Content-Type: application/json" \\
    -d '{"type": "new_message", "topic": "message:direct:test-conversation-123", "sender": "CLITest", "content": "Encrypted message", "encryption": true}'
  ```

  Invalid Encryption Metadata (for testing error handling):
  ```bash
  curl -X POST http://localhost:8001/api/test/test_events \\
    -H "Content-Type: application/json" \\
    -d '{"type": "new_message", "topic": "message:direct:test-conversation-123", "sender": "CLITest", "content": "Bad encryption", "encryption": true, "key_id": "INVALID_KEY", "version_tag": "bad-version"}'
  ```
  """
  use FamichatWeb, :controller
  require Logger

  @doc """
  Triggers a broadcast event based on the provided parameters.

  ## Parameters

  * `type` - The type of event to broadcast (e.g., "new_message")
  * `topic` - The channel topic to broadcast to (e.g., "message:direct:123")
  * `sender` - The sender identifier (default: "CLITest")
  * `content` - The message content (default: "Test message from CLI")
  * `encryption` - (Optional) Boolean indicating if encryption metadata should be included
  * `key_id` - (Optional) Custom encryption key ID (default: "KEY_TEST_v1")
  * `version_tag` - (Optional) Custom version tag (default: "v1.0.0")

  ## Response

  * 200 - Event broadcast successfully
  * 400 - Missing required parameters or invalid input
  * 422 - Invalid encryption metadata format

  ## Telemetry

  This endpoint emits telemetry events that can be monitored for testing:

  * `[:famichat, :test_broadcast, :trigger]` - When an event is triggered via CLI
  * Contains metadata about the event type, encryption status, and performance metrics
  """
  def trigger(conn, params) do
    # Start telemetry span
    :telemetry.span(
      [:famichat, :test_broadcast, :trigger],
      %{conn_id: to_string(System.unique_integer([:positive]))},
      fn -> process_trigger_request(conn, params) end
    )
  end

  # Extracts and validates parameters, then processes the broadcast request
  defp process_trigger_request(conn, params) do
    # Extract required parameters
    with {:ok, type} <- Map.fetch(params, "type"),
         {:ok, topic} <- Map.fetch(params, "topic"),
         # Additional validation could be added here
         true <- valid_event_type?(type) do
      process_valid_request(conn, params, type, topic)
    else
      :error ->
        # Required parameter missing
        respond_with_error(
          conn,
          400,
          "Required parameters: type, topic. Optional: content, sender, encryption, key_id, version_tag"
        )

      false ->
        # Invalid event type
        respond_with_error(
          conn,
          400,
          "Invalid event type. Supported types: new_message, presence_update, typing_indicator"
        )
    end
  end

  # Processes a valid broadcast request with encryption handling
  defp process_valid_request(conn, params, type, topic) do
    # Prepare the broadcast payload
    base_payload = %{
      "body" => Map.get(params, "content", "Test message from CLI"),
      "user_id" => Map.get(params, "sender", "CLITest"),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Process with encryption if requested
    encryption_result =
      if Map.get(params, "encryption") == true do
        add_encryption_metadata(conn, base_payload, params)
      else
        {:ok, base_payload}
      end

    case encryption_result do
      {:ok, payload} ->
        send_broadcast(conn, payload, type, topic)

      {:error, status, message} ->
        respond_with_error(conn, status, message)
    end
  end

  # Adds encryption metadata to the payload if requested
  defp add_encryption_metadata(_conn, payload, params) do
    # Get custom encryption parameters or use defaults
    key_id = Map.get(params, "key_id", "KEY_TEST_v1")
    version_tag = Map.get(params, "version_tag", "v1.0.0")

    # Validate encryption metadata format
    case validate_encryption_metadata(key_id, version_tag) do
      :ok ->
        # Merge encryption metadata into payload
        {:ok,
         Map.merge(payload, %{
           "encryption_flag" => true,
           "key_id" => key_id,
           "version_tag" => version_tag
         })}

      {:error, message} ->
        # Return validation error
        {:error, 422, message}
    end
  end

  # Sends the broadcast after all validation has passed
  defp send_broadcast(conn, payload, type, topic) do
    # Log the broadcast attempt
    Logger.info("CLI test broadcast to topic: #{topic}, event: #{type}")
    Logger.debug("Broadcast payload: #{inspect(payload)}")

    # Determine the event name based on the type
    event_name =
      case type do
        "new_message" -> "new_msg"
        _ -> type
      end

    # Broadcast the event
    FamichatWeb.Endpoint.broadcast!(topic, event_name, payload)

    # Return success response with the payload for verification
    result =
      {conn
       |> json(%{
         status: "success",
         message: "Event broadcast to #{topic}",
         event_type: type,
         event_name: event_name,
         payload: payload
       }), %{broadcast_success: true}}

    # Return the connection and measurements for telemetry
    result
  end

  # Returns an error response with specified status and message
  defp respond_with_error(conn, status, message) do
    {conn
     |> put_status(status)
     |> json(%{
       status: "error",
       message: message
     }), %{broadcast_success: false, error: message}}
  end

  # Helper function to validate event types
  defp valid_event_type?(type) do
    type in ["new_message", "presence_update", "typing_indicator"]
  end

  # Helper function to validate encryption metadata format
  defp validate_encryption_metadata(key_id, version_tag) do
    # Key ID should match pattern KEY_[A-Z]+_v[0-9]+
    key_id_valid = Regex.match?(~r/^KEY_[A-Z]+_v[0-9]+$/, key_id)

    # Version tag should match pattern v[0-9]+\.[0-9]+\.[0-9]+
    version_tag_valid = Regex.match?(~r/^v[0-9]+\.[0-9]+\.[0-9]+$/, version_tag)

    case {key_id_valid, version_tag_valid} do
      {true, true} ->
        :ok

      {false, true} ->
        {:error, "Invalid key_id format. Expected pattern: KEY_[A-Z]+_v[0-9]+"}

      {true, false} ->
        {:error,
         "Invalid version_tag format. Expected pattern: v[0-9]+.[0-9]+.[0-9]+"}

      {false, false} ->
        {:error, "Invalid key_id and version_tag format"}
    end
  end
end
