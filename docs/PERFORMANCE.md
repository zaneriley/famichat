# Performance Architecture

**Last Updated**: 2026-02-25
**Status**: Canonical (MLS-first)

---

## Scope and Principles

Performance is a product and security requirement.
This document defines the canonical latency model and measurement plan for the active MLS-first direction.

Key principles:

1. Measure externally observable outcomes, not implementation trivia.
2. Keep one shared production path for frontend, API, CLI, and agent workflows.
3. Separate steady-state message latency from group lifecycle operations.
4. Treat crypto dependency hygiene as an operational performance and safety concern.

---

## Current Reality

1. Realtime channels, auth boundaries, and broadcast verification flows are implemented.
2. Encryption metadata infrastructure exists (`messages.metadata`, telemetry filtering, policy hooks).
3. Actual MLS cryptography is not integrated yet; message content remains effectively plaintext today.

Implication: current latency can validate transport and workflow shape, but not final encrypted-path cost.

---

## Authoritative Protocol Direction

Famichat is MLS-first via OpenMLS (ADR 010).
ADR 006 (Signal-first) is historical and superseded.

Protocol planning assumptions:

1. Do not split protocol by conversation size.
2. Plan for inter-family and neighborhood-scale group behavior.
3. Track tree health and churn as first-order performance factors.

References:

- [ADR 010](decisions/010-mls-first-for-neighborhood-scale.md)
- [ENCRYPTION.md](ENCRYPTION.md)

---

## SLO Model

### 1) Steady-State Application Message Path

Primary user-facing target:

- Sender-to-receiver p95 <= 200ms for normal app-message flow

Budget model (target allocation):

1. Client capture/render: <= 10ms each side
2. Server encrypt path (post-MLS integration): <= 50ms target
3. Persist + broadcast path: <= 30ms target
4. Network send/receive combined: <= 100ms target

These are planning budgets and must be validated with production-path measurements.

### 2) Group Lifecycle Path (Separate SLO Class)

`commit`, `update`, `add`, and `remove` are not the typing critical path.
They require dedicated SLOs and alerts because latency is sensitive to churn and tree state.

Track p50/p95/p99 independently from steady-state message flow.

### 3) State Growth and Synchronization Health

Track:

1. Serialized group state size over time
2. Ratchet tree growth characteristics
3. Epoch advancement lag and drift across active devices

---

## Required Telemetry and Metrics

Before broad dogfooding, capture and alert on:

1. `send_application_message` latency (p50/p95/p99)
2. `process_application_message` latency (p50/p95/p99)
3. `mls_commit` / `mls_update` / `mls_add` / `mls_remove` latency (p50/p95/p99)
4. `mls_group_state_bytes` and related storage growth
5. `mls_epoch_lag` and synchronization drift indicators
6. Error counters: decrypt failure, commit rejection, key package depletion

Telemetry output must avoid sensitive key material and ciphertext leakage.

---

## Test and Benchmark Plan

1. Establish plaintext-path transport baseline (current state).
2. Add MLS NIF boundary microbenchmarks (encrypt/decrypt, commit/update).
3. Add churn characterization tests (low, medium, high membership-change profiles).
4. Run end-to-end load tests (100-500 concurrent users) on canonical product paths.
5. Add CI regression checks for latency regressions and failure-rate spikes.

---

## Operational Guardrails

1. Pin OpenMLS versions and apply security updates on a defined SLA.
2. Do not silently fall back to plaintext when encrypted operations fail.
3. Keep one shared execution path across UI, API, CLI, and agent validation workflows.
4. Fail loudly with actionable errors on encryption and state-sync failures.

---

## Near-Term Priorities

1. Publish one canonical runbook with measurable checkpoints: `auth -> subscribe -> send -> receive`.
2. Add timing capture to that runbook and lock outcome-focused integration assertions.
3. Implement MLS Rust NIF skeleton plus performance harness.
4. Add churn and epoch-drift characterization tests before broader rollout.

---

## Related Documentation

- [NOW.md](NOW.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [ENCRYPTION.md](ENCRYPTION.md)
- [ADR 010](decisions/010-mls-first-for-neighborhood-scale.md)
- [sprints/STATUS.md](sprints/STATUS.md)
