defmodule Famichat.TelemetryHandler do
  @moduledoc """
  A Telemetry handler that logs Famichat events for performance monitoring.

  This handler attaches to telemetry events across Famichat and logs measurements.
  """

  require Logger

  @doc """
  Attaches the telemetry handler to specified events.

  This currently attaches only to the `get_conversation_messages` event. As we
  instrument more functions, simply add their event names to the list.
  """
  def attach do
    events = [
      [:famichat, :message_service, :get_conversation_messages]
      # Add more events here as new telemetry-enabled functions are added.
    ]

    :telemetry.attach_many("famichat-logger", events, &handle_event/4, nil)
  end

  @doc false
  def handle_event(event_name, measurements, metadata, _config) do
    Logger.info(
      "[Telemetry] Event: #{inspect(event_name)}, Measurements: #{inspect(measurements)}, Metadata: #{inspect(metadata)}"
    )
  end
end
