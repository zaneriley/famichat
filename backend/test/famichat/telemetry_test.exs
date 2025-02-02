defmodule Famichat.TelemetryTest do
  use ExUnit.Case

  test "telemetry span emits basic event" do
    handler_id = "test-handler-span-#{System.unique_integer([:positive])}"
    :telemetry.attach(handler_id, [:test_span, :stop],
      fn event, measurements, metadata, _config ->
        send(self(), {:telemetry_event, event, measurements, metadata, handler_id})
      end,
      nil
    )

    :telemetry.span([:test_span], %{}, fn ->
      result = {:ok, %{}}
      measurements = %{test: 1}
      {result, measurements}
    end)

    assert_receive {
      :telemetry_event, [:test_span, :stop],
      measurements,
      metadata,
      ^handler_id
    }, 500

    # Assert that the measurements include a numeric :duration
    assert is_integer(Map.get(measurements, :duration))
    # Assert that our custom value appears in metadata (not in measurements)
    assert Map.get(metadata, :test) == 1

    :telemetry.detach(handler_id)
  end
end
