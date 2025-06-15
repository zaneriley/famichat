defmodule FamichatWeb.Telemetry do
  @moduledoc """
  Emit events at various stages of an application's lifecycle.

  This module has two primary responsibilities:
  1. Set up telemetry metrics for reporting and monitoring
  2. Provide common telemetry utilities for consistent instrumentation across the application
  """

  use Supervisor
  require Logger
  import Telemetry.Metrics

  # Common constants
  @sensitive_metadata_fields ~w(version_tag encryption_flag key_id)
  @default_performance_budget_ms 50

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Executes a telemetry event with standardized measurements and metadata.

  ## Parameters
    * `event_name` - List of atoms representing the telemetry event name
    * `start_time` - Monotonic time when the operation started
    * `metadata` - Map of contextual information about the operation
    * `opts` - Options to customize telemetry behavior:
      * `:performance_budget_ms` - Performance threshold in milliseconds (default: #{@default_performance_budget_ms})
      * `:filter_sensitive_metadata` - Whether to filter sensitive metadata (default: false)
      * `:log_event` - Whether to log the event details (default: true)

  ## Returns
    * `:ok`
  """
  @spec emit_event(list(atom()), integer(), map(), keyword()) :: :ok
  def emit_event(event_name, start_time, metadata, opts \\ []) do
    # Extract options with defaults
    performance_budget_ms =
      Keyword.get(opts, :performance_budget_ms, @default_performance_budget_ms)

    filter_sensitive = Keyword.get(opts, :filter_sensitive_metadata, false)
    log_event = Keyword.get(opts, :log_event, true)

    try do
      # Calculate measurements
      end_time = System.monotonic_time()
      duration_ms = calculate_duration_ms(start_time, end_time)

      # Build standard measurements
      measurements = %{
        start_time: start_time,
        end_time: end_time,
        duration_ms: duration_ms,
        system_time: System.system_time()
      }

      # Apply standard metadata transformations
      enriched_metadata =
        metadata
        |> Map.put_new(:timestamp, DateTime.utc_now())
        |> ensure_message_size()

      # Filter sensitive metadata if requested
      filtered_metadata =
        if filter_sensitive do
          filter_sensitive_metadata(enriched_metadata)
        else
          enriched_metadata
        end

      # Log the event if requested
      if log_event do
        log_operation(event_name, enriched_metadata, duration_ms)
      end

      # Emit the telemetry event
      :telemetry.execute(event_name, measurements, filtered_metadata)

      # Check performance budget (in a separate function to keep concerns separated)
      check_performance_budget(event_name, duration_ms, performance_budget_ms)

      :ok
    rescue
      e ->
        Logger.error(
          "Error emitting telemetry event #{inspect(event_name)}: #{Exception.message(e)}"
        )

        :error
    end
  end

  @doc """
  Executes a telemetry event in the context of a span.

  This function is ideal for wrapping operations to automatically
  measure their duration and ensure consistent telemetry emission.

  ## Parameters
    * `event_name` - List of atoms representing the telemetry event name
    * `metadata` - Map of contextual information about the operation
    * `function` - Function to execute and measure
    * `opts` - Options to customize telemetry behavior

  ## Returns
    * The result of the given function
  """
  @spec with_telemetry(list(atom()), map(), keyword(), function()) :: any()
  def with_telemetry(event_name, metadata, opts \\ [], function) do
    filter_sensitive = Keyword.get(opts, :filter_sensitive_metadata, false)

    performance_budget_ms =
      Keyword.get(opts, :performance_budget_ms, @default_performance_budget_ms)

    # Enrich metadata
    enriched_metadata =
      metadata
      |> Map.put_new(:timestamp, DateTime.utc_now())
      |> ensure_message_size()

    # Filter sensitive metadata if requested
    span_metadata =
      if filter_sensitive do
        filter_sensitive_metadata(enriched_metadata)
      else
        enriched_metadata
      end

    try do
      {result, measurements} =
        :telemetry.span(
          event_name,
          span_metadata,
          fn ->
            result = function.()
            {result, %{}}
          end
        )

      # Check performance budget
      if Map.has_key?(measurements, :duration) do
        duration_ms =
          System.convert_time_unit(measurements.duration, :native, :millisecond)

        check_performance_budget(event_name, duration_ms, performance_budget_ms)
      end

      result
    rescue
      e ->
        Logger.error(
          "Error in telemetry span #{inspect(event_name)}: #{Exception.message(e)}"
        )

        reraise e, __STACKTRACE__
    end
  end

  # Private helper functions

  defp calculate_duration_ms(start_time, end_time) do
    System.convert_time_unit(
      end_time - start_time,
      :native,
      :millisecond
    )
  end

  defp ensure_message_size(metadata) do
    if Map.has_key?(metadata, :message_size) do
      metadata
    else
      Map.put(metadata, :message_size, 0)
    end
  end

  defp filter_sensitive_metadata(metadata) do
    status = Map.get(metadata, :status)

    if status == :success or is_nil(status) do
      # For successful operations, only keep encryption_status
      Map.drop(metadata, @sensitive_metadata_fields)
    else
      # For failed operations, remove all encryption-related fields
      Map.drop(metadata, @sensitive_metadata_fields ++ ["encryption_status"])
    end
  end

  defp log_operation(
         [:famichat, :message_channel, :join],
         metadata,
         duration_ms
       ) do
    # Log join operations
    status = Map.get(metadata, :status, "unknown")
    user_id = Map.get(metadata, :user_id, "unknown")
    conversation_type = Map.get(metadata, :conversation_type, "unknown")
    conversation_id = Map.get(metadata, :conversation_id, "unknown")

    Logger.info(
      "[MessageChannel] Join: " <>
        "status=#{status} " <>
        "user_id=#{user_id} " <>
        "conversation_type=#{conversation_type} " <>
        "conversation_id=#{conversation_id} " <>
        "duration_ms=#{duration_ms}"
    )
  end

  defp log_operation(
         [:famichat, :message_channel, :broadcast],
         metadata,
         duration_ms
       ) do
    # Log broadcast operations
    conversation_type = Map.get(metadata, :conversation_type, "unknown")
    conversation_id = Map.get(metadata, :conversation_id, "unknown")
    user_id = Map.get(metadata, :user_id, "unknown")
    encryption_status = Map.get(metadata, :encryption_status, "unknown")
    message_size = Map.get(metadata, :message_size, 0)

    Logger.info(
      "[MessageChannel] Broadcast event: " <>
        "conversation_type=#{conversation_type} " <>
        "conversation_id=#{conversation_id} " <>
        "user_id=#{user_id} " <>
        "encryption_status=#{encryption_status} " <>
        "message_size=#{message_size} " <>
        "duration_ms=#{duration_ms}"
    )
  end

  defp log_operation([:famichat, :message_channel, :ack], metadata, duration_ms) do
    # Log acknowledgment operations
    conversation_type = Map.get(metadata, :conversation_type, "unknown")
    conversation_id = Map.get(metadata, :conversation_id, "unknown")
    user_id = Map.get(metadata, :user_id, "unknown")
    message_id = Map.get(metadata, :message_id, "unknown")

    Logger.info(
      "[MessageChannel] Message acknowledgment: " <>
        "conversation_type=#{conversation_type} " <>
        "conversation_id=#{conversation_id} " <>
        "user_id=#{user_id} " <>
        "message_id=#{message_id} " <>
        "duration_ms=#{duration_ms}"
    )
  end

  # Default case for other events
  defp log_operation(event_name, metadata, duration_ms) do
    # For any other event, log basic information
    Logger.debug(
      "Event #{inspect(event_name)} executed in #{duration_ms}ms with metadata: #{inspect(metadata)}"
    )
  end

  # Separate function for performance budget checking
  defp check_performance_budget(event_name, duration_ms, budget_ms)
       when duration_ms > budget_ms do
    Logger.warning(
      "Performance budget exceeded for #{inspect(event_name)}: " <>
        "#{duration_ms}ms (budget: #{budget_ms}ms)"
    )
  end

  defp check_performance_budget(_event_name, _duration_ms, _budget_ms), do: :ok

  def metrics do
    [
      # Message Channel Metrics
      summary("famichat.message_channel.join.duration",
        unit: {:native, :millisecond},
        description: "The time spent processing a channel join"
      ),
      counter("famichat.message_channel.join.total",
        event_name: [:famichat, :message_channel, :join],
        description: "Total number of channel joins"
      ),
      distribution("famichat.message_channel.join.status",
        event_name: [:famichat, :message_channel, :join],
        measurement: :status,
        description: "Distribution of channel join statuses"
      ),
      counter("famichat.message_channel.broadcast.total",
        event_name: [:famichat, :message_channel, :broadcast],
        description: "Total number of messages broadcast"
      ),
      summary("famichat.message_channel.broadcast.duration",
        unit: {:native, :millisecond},
        description: "The time spent broadcasting a message"
      ),

      # SetLocale Plug Metrics
      summary("famichat.plug.set_locale.call.duration",
        unit: {:native, :millisecond},
        description: "The time spent in the SetLocale plug's call function"
      ),
      summary("famichat.plug.set_locale.extract_locale.duration",
        unit: {:native, :millisecond},
        description:
          "The time spent extracting the locale in the SetLocale plug"
      ),
      summary("famichat.plug.set_locale.set_locale.duration",
        unit: {:native, :millisecond},
        description: "The time spent setting the locale in the SetLocale plug"
      ),
      distribution("famichat.plug.set_locale.extract_locale.source",
        event_name: [:famichat, :plug, :set_locale, :extract_locale],
        measurement: :source,
        description: "Distribution of locale sources"
      ),

      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("famichat.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("famichat.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "Time spent decoding the data received from the database"
      ),
      summary("famichat.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "Time spent executing the query"
      ),
      summary("famichat.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "Time spent waiting for a database connection"
      ),
      summary("famichat.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "Time spent waiting for the conn to be checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    []
  end
end
