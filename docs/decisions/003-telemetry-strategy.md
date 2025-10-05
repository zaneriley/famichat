# ADR 003: Telemetry Performance Budgets

**Date**: 2025-03-15
**Status**: Accepted

---

## Context

Need performance monitoring strategy that doesn't slow down the app.

## Decision

Use `:telemetry.span/3` with **200ms performance budget** for all critical operations.

## Rationale

- **200ms**: Industry standard for "fast" response time
- **Telemetry**: Low overhead, widely supported
- **Event naming**: `[:famichat, :context, :action]` convention

## Implementation

All service operations wrapped in telemetry spans:
```elixir
:telemetry.span([:famichat, :message, :send], %{}, fn ->
  result = send_message_impl(attrs)
  {result, %{status: elem(result, 0)}}
end)
```

## Consequences

### Positive
- Visibility into performance
- Early detection of slow operations
- Budget violations logged (not blocked)

### Negative
- Small overhead per operation
- Requires monitoring infrastructure (Prometheus/Grafana)

---

**Related**: [backend/guides/telemetry.md](../../backend/guides/telemetry.md)
