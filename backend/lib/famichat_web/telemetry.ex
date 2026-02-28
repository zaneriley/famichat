defmodule FamichatWeb.Telemetry do
  @moduledoc """
  Emit events at various stages of an application's lifecycle.

  This module has two primary responsibilities:
  1. Set up telemetry metrics for reporting and monitoring
  2. Provide common telemetry utilities for consistent instrumentation across the application
  """

  use Supervisor
  import Telemetry.Metrics
  require Logger

  # Common constants
  @sensitive_metadata_fields ~w(version_tag encryption_flag key_id)
  @default_performance_budget_ms 200

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
        count: 1,
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
      # =========================================================================
      # SECTION 1: SYSTEM VITAL SIGNS & SATURATION
      # =========================================================================
      # Question: Is the system stable? Are we hitting resource limits?
      # Critical: High utilization (>80%) indicates CPU saturation

      # 1.1 BEAM Scheduler Utilization
      summary("vm.total_run_queue_lengths.total",
        description: "Tasks waiting for CPU - saturation indicator"
      ),
      summary("vm.total_run_queue_lengths.cpu",
        description: "CPU scheduler queue length"
      ),
      summary("vm.total_run_queue_lengths.io",
        description: "IO scheduler queue length"
      ),

      # 1.2 P95 Endpoint Latency (must stay below 200ms SLO)
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond},
        description: "Request latency by route - watch P95/P99"
      ),

      # 1.3 Application Throughput
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        description: "Overall endpoint latency - correlate with load"
      ),

      # 1.4 VM Memory Usage
      summary("vm.memory.total",
        unit: {:byte, :kilobyte},
        description: "Total VM memory - watch for leaks"
      ),

      # =========================================================================
      # SECTION 2: AUTHENTICATION SECURITY & INTEGRITY
      # =========================================================================
      # Monitors auth refactor (Phases 1-2) and token rotation (ADR-004)

      # 2.1 CRITICAL: Refresh Token Reuse Detection (MUST BE ZERO)
      counter("famichat.auth.session.refresh.reuse_detected",
        event_name: [:famichat, :auth, :sessions, :refresh_reuse_detected],
        description: "⚠️ CRITICAL: Token theft indicator - must be zero"
      ),

      # 2.2 Session Lifecycle Events
      counter("famichat.auth.session.start.count",
        event_name: [:famichat, :auth, :sessions, :start],
        description: "New sessions started"
      ),
      counter("famichat.auth.session.refresh.count",
        event_name: [:famichat, :auth, :sessions, :refresh],
        description: "Session refreshes - ratio to starts shows stickiness"
      ),
      counter("famichat.auth.session.revoke.count",
        event_name: [:famichat, :auth, :sessions, :revoke],
        description: "Session revocations - spikes need investigation"
      ),

      # 2.3 Token Issuance Distribution
      counter("famichat.auth.token.issued.total",
        event_name: [:famichat, :auth, :tokens, :issued],
        measurement: :count,
        tags: [:kind, :class, :audience],
        description: "Tokens issued grouped by kind/class/audience"
      ),
      counter("famichat.auth.token.subject_id_present.total",
        event_name: [:auth_tokens, :issue, :subject_id_present],
        measurement: :count,
        tags: [:kind],
        tag_values: &%{kind: (Map.get(&1, :kind) || :unknown) |> to_string()},
        description: "Issued tokens with subject_id populated"
      ),
      counter("famichat.auth.token.subject_id_missing.total",
        event_name: [:auth_tokens, :issue, :missing_subject_id],
        measurement: :count,
        tags: [:kind],
        tag_values: &%{kind: (Map.get(&1, :kind) || :unknown) |> to_string()},
        description: "Issued tokens missing subject_id (should remain zero)"
      ),

      # 2.4 Rate Limiter Activations
      counter("famichat.rate_limiter.throttled.total",
        event_name: [:famichat, :rate_limiter, :throttled],
        measurement: :count,
        tags: [:bucket],
        tag_values: &%{bucket: Map.get(&1, :bucket)},
        description: "Rate limiter throttles by bucket"
      ),

      # =========================================================================
      # SECTION 3: REAL-TIME MESSAGING PERFORMANCE (CRITICAL PATH)
      # =========================================================================
      # Track latency against 200ms budget and WebSocket stability

      # 3.1 Message Broadcast Latency (major component of end-to-end budget)
      summary("famichat.message_channel.broadcast.duration",
        unit: {:native, :millisecond},
        description: "Server-side message fan-out time - watch P95"
      ),
      counter("famichat.message_channel.broadcast.total",
        event_name: [:famichat, :message_channel, :broadcast],
        description: "Total messages broadcast"
      ),

      # 3.2 Channel Join Latency (impacts initial connection)
      summary("famichat.message_channel.join.duration",
        unit: {:native, :millisecond},
        description: "Auth + authorization time for channel join"
      ),
      counter("famichat.message_channel.join.total",
        event_name: [:famichat, :message_channel, :join],
        description: "Total channel joins"
      ),

      # 3.3 Message Acknowledgments
      counter("famichat.message_channel.ack.total",
        event_name: [:famichat, :message_channel, :ack],
        measurement: :count,
        description: "Message acknowledgments received from clients"
      ),
      summary("famichat.message_channel.ack.duration",
        event_name: [:famichat, :message_channel, :ack],
        measurement: :duration_ms,
        unit: :millisecond,
        description: "ACK processing latency"
      ),

      # 3.4 Channel Authorization Failures
      distribution("famichat.message_channel.join.status",
        event_name: [:famichat, :message_channel, :join],
        measurement: :status,
        description: "Join outcomes - filter by error for auth failures"
      ),

      # =========================================================================
      # SECTION 4: ENCRYPTION POLICY ADHERENCE
      # =========================================================================
      # Metadata infrastructure live, actual crypto pending Sprint 9

      # 4.1 Encryption Status Coverage
      counter("famichat.message.serialized.total",
        event_name: [:famichat, :message, :serialized],
        measurement: :count,
        tags: [:encryption_status],
        tag_values:
          &%{
            encryption_status:
              (Map.get(&1, :encryption_status) || :unknown) |> to_string()
          },
        description: "Messages serialized grouped by encryption status"
      ),

      # 4.2 Decryption Error Rate
      counter("famichat.message.decryption_error.total",
        event_name: [:famichat, :message, :decryption_error],
        measurement: :count,
        tags: [:error_type],
        tag_values:
          &%{error_type: (Map.get(&1, :error_type) || :unknown) |> to_string()},
        description: "Decryption errors (should remain near zero)"
      ),

      # 4.4 MLS Failure Rate (G1 gate: must stay below 5%)
      # Emitted by MessageService.emit_mls_failure/5 on any MLS encrypt/decrypt/state
      # failure. The gate_report.json mls_failure_rate field is computed from this
      # counter during qa:messaging:deep runs.
      counter("famichat.message.mls_failure.total",
        event_name: [:famichat, :message, :mls_failure],
        measurement: :count,
        tags: [:action, :reason],
        tag_values:
          &%{
            action: (Map.get(&1, :action) || :unknown) |> to_string(),
            reason: (Map.get(&1, :reason) || :unknown) |> to_string()
          },
        description: "MLS failures by action and reason (gate threshold: < 5%)"
      ),

      # 4.3 Serialization/Deserialization Latency
      summary("famichat.message.serialized.duration",
        event_name: [:famichat, :message, :serialized],
        measurement: :duration_ms,
        unit: :millisecond,
        description: "Serialization latency (metadata pipeline)"
      ),
      summary("famichat.message.deserialized.duration",
        event_name: [:famichat, :message, :deserialized],
        measurement: :duration_ms,
        unit: :millisecond,
        description: "Deserialization latency"
      ),

      # =========================================================================
      # SECTION 5: DATABASE (ECTO) PERFORMANCE INSIGHTS
      # =========================================================================
      # Identify bottlenecks: query execution, decoding, connection pool

      # 5.1 Database Latency Breakdown
      summary("famichat.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "Total DB operation time (query + decode + queue)"
      ),
      summary("famichat.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "SQL execution time - high values = inefficient queries"
      ),
      summary("famichat.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "Result decoding time"
      ),
      summary("famichat.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "Pool wait time - high values = saturation"
      ),
      summary("famichat.repo.query.idle_time",
        unit: {:native, :millisecond},
        description: "Connection checkout wait time"
      ),

      # 5.2 Ecto Pool Saturation
      # ⚠️ Approximated from high queue_time - no direct metric available

      # =========================================================================
      # SECTION 6: OTHER INSTRUMENTATION
      # =========================================================================

      # Locale Detection (not in control panel spec)
      summary("famichat.plug.set_locale.call.duration",
        unit: {:native, :millisecond},
        description: "SetLocale plug processing time"
      ),
      summary("famichat.plug.set_locale.extract_locale.duration",
        unit: {:native, :millisecond},
        description: "Locale extraction time"
      ),
      summary("famichat.plug.set_locale.set_locale.duration",
        unit: {:native, :millisecond},
        description: "Locale setting time"
      ),
      distribution("famichat.plug.set_locale.extract_locale.source",
        event_name: [:famichat, :plug, :set_locale, :extract_locale],
        measurement: :source,
        description: "Locale source distribution"
      )
    ]
  end

  defp periodic_measurements do
    []
  end
end
