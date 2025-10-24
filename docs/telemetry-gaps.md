# Telemetry Coverage Gaps - Backend Implementation Needed

**Dashboard Frontend**: `/dev/dashboard/control_panel`
**Status**: Dashboard UI complete, awaiting backend telemetry
**Last Updated**: 2025-10-24

---

## Summary

The Famichat Control Panel dashboard has been implemented per the design spec. This document lists telemetry events and metrics that **exist but aren't exposed** vs. those that **need to be implemented**.

---

## Coverage Status

| Section | Metrics Available | Metrics Needed | Coverage % |
|---------|-------------------|----------------|------------|
| 1. System Vital Signs | 4/4 | 0 | 100% ✅ |
| 2. Authentication Security | 4/4 | 0 | 100% ✅ |
| 3. Real-Time Messaging | 4/4 | 0 | 100% ✅ |
| 4. Encryption Policy | 3/3 | 0 | 100% ✅ |
| 5. Database Performance | 5/6 | 1 | 83% ⚠️ |
| **TOTAL** | **20/21** | **1** | **95%** |

---

## Priority 1: Events Exist, Need Metrics Definition 🟡

These telemetry events are **already being emitted** but aren't registered in `FamichatWeb.Telemetry.metrics()`. Adding them is a simple update to the metrics list.

### 2.3 Token Issuance Distribution

✅ Implemented. Counters now track issuance by kind alongside subject-id quality metrics.
---

### 4.1 Encryption Status Coverage

✅ Implemented. Serialized event metrics expose encryption mix and throughput.
---

### 4.2 Decryption Error Rate

✅ Implemented. Counter `famichat.message.decryption_error.total` triggers the red panel when failures surface.
---

### 4.3 Serialization/Deserialization Latency

✅ Implemented. Duration summaries ensure metadata transforms stay within the 200ms budget.
---

## Priority 2: Needs Backend Implementation ❌

These require actual telemetry emission in backend code.

### 2.4 Rate Limiter Activations

✅ Implemented. Event `[:famichat, :rate_limiter, :throttled]` now emits with hashed keys; counter metric drives the brute-force alert.
---

### 3.3 Message Acknowledgment Tracking

✅ Implemented. `famichat.message_channel.ack.total` and `ack.duration` power delivery confirmation monitoring.
---

### 5.2 Ecto Pool Saturation

**Status**: ⚠️ Can be approximated from queue_time
**Ideal Solution**: Emit pool metrics from Ecto
**Workaround**: High `repo.query.queue_time` indicates saturation

**Possible Custom Metric** (requires Ecto pool inspection):
```elixir
# In periodic_measurements/0:
{:ecto_pool_stats, fn ->
  pool_config = Famichat.Repo.config()
  pool_size = pool_config[:pool_size] || 10

  # Would need to inspect DBConnection pool state
  # This is non-trivial and might not be worth it

  %{
    pool_size: pool_size,
    # checked_out: ??? (not easily accessible)
  }
end}
```

**Alternative**: Document that `queue_time > 50ms` is a proxy for saturation.

---

## Implementation Checklist

### Quick Wins (5 min each) ✅
- [ ] Add token issuance distribution metric (Section 2.3)
- [ ] Add encryption status coverage metric (Section 4.1)
- [ ] Add decryption error counter (Section 4.2)
- [ ] Add serialization/deserialization latency metrics (Section 4.3)

### Backend Work Required (30 min each) 🛠️
- [ ] Implement rate limiter telemetry (Section 2.4)
- [ ] Implement message ack tracking (Section 3.3)
- [ ] Document pool saturation proxy (Section 5.2)

---

## Testing the Dashboard

1. Start the dev server: `./run mix phx.server`
2. Navigate to: `http://localhost:4000/dev/dashboard/control_panel`
3. Verify sections with ✅ show real data
4. Sections with ⚠️ show "waiting for backend" placeholders

---

## Questions for Discussion

1. **Rate limiter priority**: How critical is rate limiter visibility for Sprint 7?
2. **Message ack tracking**: Is this a Sprint 8+ feature or needed now?
3. **Pool saturation**: Accept queue_time as proxy or invest in custom metric?
4. **Encryption events**: Do we need the metrics now even though crypto is Sprint 9?

