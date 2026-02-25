# Famichat - Encryption & Security Architecture

**Last Updated**: 2026-02-25

---

Use [ia-lexicon.md](ia-lexicon.md) as the terminology authority for `conversation security state` and related ownership language.
Boundary drift guardrails: [ia-boundary-guardrails.md](ia-boundary-guardrails.md) (`cd backend && ./run docs:boundary-check`).

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

## Terminology and Ownership Contract

1. Product default term: `conversation security state`.
2. Engineering default term: `conversation security state record`.
3. Protocol-qualified implementation term: `MLS protocol state` (when needed).
4. Chat-domain policy term: `conversation security policy`.
5. Canonical policy module boundary: `Famichat.Chat.ConversationSecurityPolicy` (`requires_encryption?/1` wording can remain as compatibility API surface).
6. Durable state write ownership belongs to `Famichat.Chat`.
7. `Famichat.Crypto.MLS` and Rust NIF (`backend/infra/mls_nif`) are adapter-only and do not own DB persistence tables.
8. `Famichat.Chat.MessageService` remains the orchestrator that loads/persists through Chat-owned state boundaries.

---

## Current State (As of 2026-02-25)

### Implemented

1. Real OpenMLS cryptography is integrated via Rustler NIF for `create_group -> create_application_message -> process_incoming`.
2. MessageService enforces fail-closed runtime health gating (`nif_health`) before MLS encrypt/decrypt paths.
3. Canonical message path stores ciphertext at rest and decrypts on read via the shared backend path.
4. Durable conversation security state persistence is active in `conversation_security_states` through `Famichat.Chat.ConversationSecurityStateStore` (encrypted state blobs + optimistic locking).
5. Replay-idempotency cache is bounded (`max 256`) to cap snapshot growth under high replay-cardinality reads.
6. Adversarial coverage includes malformed ciphertext, cross-group misuse rejection, replay/idempotency behavior, tampered-snapshot fail-closed behavior, and lifecycle misuse checks (out-of-order merge/clear, tampered pending metadata, concurrent stage races).
7. Transactional send path now fails closed on stale state conflicts (message insert is rolled back if state write cannot commit).
8. Pending-commit lifecycle orchestration exists at the Chat boundary, and send-path app messages fail closed while pending commits are unresolved.

### Not Implemented Yet

1. Full key package and credential lifecycle hardening (rotation, rejoin durability, revocation strategy).
2. Commit/update/add/remove lifecycle hardening on the dedicated store (deeper OpenMLS payload/epoch semantics beyond current stage/merge/clear orchestration).
3. Multi-node/state-distribution strategy for deterministic MLS state recovery across instances.

**Current risk**: encryption is active, but production trust still depends on finishing state lifecycle hardening and key lifecycle controls.

### Transitional Persistence Policy

1. `conversations.metadata.mls.session_snapshot_encrypted` remains a compatibility-only read path for legacy state.
2. Canonical writes/reads now use `conversation_security_states` with optimistic lock-version checks.
3. Metadata-envelope fallback must be removed after migration completion criteria are met.

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
