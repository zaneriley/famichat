defmodule Famichat.TelemetryTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  alias FamichatWeb.Telemetry

  test "telemetry span emits basic event" do
    handler_id = "test-handler-span-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:test_span, :stop],
      fn event, measurements, metadata, _config ->
        send(
          self(),
          {:telemetry_event, event, measurements, metadata, handler_id}
        )
      end,
      nil
    )

    :telemetry.span([:test_span], %{}, fn ->
      result = {:ok, %{}}
      measurements = %{test: 1}
      {result, measurements}
    end)

    assert_receive {
                     :telemetry_event,
                     [:test_span, :stop],
                     measurements,
                     metadata,
                     ^handler_id
                   },
                   500

    # Assert that the measurements include a numeric :duration
    assert is_integer(Map.get(measurements, :duration))
    # Assert that our custom value appears in metadata (not in measurements)
    assert Map.get(metadata, :test) == 1

    :telemetry.detach(handler_id)
  end

  test "logs a warning when performance budget is exceeded via emit_event" do
    event_name = [:test, :budget_exceeded_event_emit]
    budget_ms = 50
    duration_to_simulate_ms = 75

    # Simulate a start time that, when compared to now, will exceed the budget
    start_time_simulated =
      System.monotonic_time() -
        System.convert_time_unit(duration_to_simulate_ms, :millisecond, :native)

    log_output =
      capture_log(fn ->
        FamichatWeb.Telemetry.emit_event(
          event_name,
          start_time_simulated,
          %{},
          performance_budget_ms: budget_ms
        )
      end)

    assert log_output =~
             "Performance budget exceeded for #{inspect(event_name)}"

    # Regex to match the duration, allowing for slight variations due to timing
    assert log_output =~ ~r/duration_ms=\d+ms \(budget: #{budget_ms}ms\)/

    # A more precise check for the logged duration being around what we simulated
    # This extracts the logged duration and checks if it's close to our simulated one.
    [_, logged_duration_str | _] =
      Regex.run(~r/duration_ms=(\d+)ms/, log_output) || []

    logged_duration =
      if logged_duration_str,
        do: String.to_integer(logged_duration_str),
        else: 0

    # Check if the logged duration is at least what we simulated.
    # It could be slightly higher due to the time taken by the test itself.
    assert logged_duration >= duration_to_simulate_ms
  end
end
