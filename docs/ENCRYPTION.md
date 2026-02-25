# Famichat - Encryption & Security Architecture

**Last Updated**: 2026-02-25

---

## Security Model

Famichat uses a layered security model:

1. **Server-side E2EE path**: MLS via OpenMLS (Rust NIF adapter).
2. **Field-level encryption**: Cloak.Ecto for sensitive account/auth fields.
3. **Infrastructure encryption**: database/storage encryption at rest.

**Trust model**: self-hosted infrastructure with a product requirement that admins cannot read message content once MLS is active.

---

## Authoritative Direction

The active protocol direction is **MLS-first**.

1. Canonical decision: [ADR 010](decisions/010-mls-first-for-neighborhood-scale.md).
2. Sprint implementation contract: [Sprint 9 MLS NIF contract](sprints/9.0-mls-rust-nif-contract-deep-dive.md).
3. TDD sequencing: [Sprint 9 MLS contract TDD plan](sprints/9.1-mls-contract-tdd-plan.md).

Historical Signal-era analysis is retained only in deprecated ADRs and is not an implementation source.

---

## Current State (As of 2026-02-25)

### Implemented

1. Encryption metadata plumbing in message/domain paths.
2. Telemetry filtering to prevent sensitive encryption metadata leakage.
3. Channel/API auth foundations and canonical verification runbook path.

### Not Implemented Yet

1. No production OpenMLS cryptography integrated.
2. No Rustler NIF bridge wired into production messaging path.
3. No MLS key package lifecycle persisted end-to-end.
4. No MLS group epoch/commit lifecycle persisted end-to-end.

**Current risk**: messages are effectively plaintext from a product-trust perspective until Sprint 9 MLS work lands.

---

## Non-Negotiable Invariants

1. No plaintext fallback when encryption is required.
2. One shared production path (no LLM-only or test-only runtime branches).
3. NIF boundary must be fail-closed with explicit error taxonomy.
4. NIF code path does no DB/network/file IO.
5. Sensitive crypto metadata is redacted in logs/telemetry.

---

## Sprint 9 Delivery Scope (MLS/OpenMLS)

1. `backend/infra/mls_nif` Rust NIF adapter scaffold and boundary.
2. Elixir domain wrapper at `backend/lib/famichat/crypto/mls.ex`.
3. Contract tests for:
   - API/error shape (`{:ok, payload}` or `{:error, code, details}`)
   - protocol invariants (pending proposals, commit/welcome ordering)
   - storage/recovery semantics
   - fail-closed message-service integration
   - telemetry contract and rollout gating
4. Observability for steady-state app messages and group lifecycle operations.

---

## Performance Policy

1. Steady-state app-message path target: <= 200ms end-to-end user path.
2. Encrypt/decrypt budget tracked separately from commit/update/add/remove operations.
3. Rollout beyond dev/test is blocked if required MLS telemetry gates are missing.

See [PERFORMANCE.md](PERFORMANCE.md) for the canonical latency model and rollout checks.

---

## Dependency and Security Policy

1. Keep OpenMLS on patched, non-vulnerable ranges.
2. Monthly dependency review for crypto stack.
3. High/critical advisory publication triggers patch SLA and release gate.

---

## Historical Documents

The following are retained for historical context only:

1. [ADR 006 (Deprecated)](decisions/006-signal-protocol-for-e2ee.md)
2. [ADR 002 (Deprecated)](decisions/002-encryption-approach.md)

If historical guidance conflicts with ADR 010 or Sprint 9 MLS docs, follow ADR 010 + Sprint 9 docs.
