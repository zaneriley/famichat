---
name: telemetry
description: >
  Telemetry and observability guidelines for Elixir. Use when instrumenting
  functions, adding metrics, or working with :telemetry spans. Covers event
  naming conventions, performance budgets, centralized helpers, and sensitive
  data filtering.
---

# Telemetry Guidelines

## Instrumentation

### Use `:telemetry.span/3`

Wrap key functions (message retrieval, conversation creation) with telemetry spans
to capture execution times and emit results with measurements.

### Centralized Helpers

Use `Famichat.Telemetry.with_telemetry/4` to wrap business logic:

```elixir
def get_conversation_messages(conversation_id) do
  Famichat.Telemetry.with_telemetry(
    [:famichat, :message_service, :get_conversation_messages],
    fn -> MessageService.fetch(conversation_id) end,
    %{},
    performance_budget_ms: 200
  )
end
```

## Event Naming

Use the pattern `[:famichat, <module>, <function>]`:
- `[:famichat, :message_service, :get_conversation_messages]`

Include relevant measurements (execution time, message size) and metadata
(user_id, error types).

## Performance Budgets

- Target: **< 200ms** end-to-end for messaging operations
- Configure spans to measure durations automatically
- Write tests asserting critical operations meet budgets

## Monitoring Integration

- Instrumentation must be non-blocking — app continues even if Prometheus/Grafana
  are unavailable
- Export telemetry data for real-time visualization and alerting

## Best Practices

- Instrument every new or modified performance-critical function
- Use centralized helpers (`emit_event/4`, `with_telemetry/4`) for consistency
- For sensitive data operations, use `filter_sensitive_metadata: true` to prevent
  sensitive information from being logged or exported
