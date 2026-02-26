# Famichat NOW

**Last Updated**: 2026-02-26

Use [ia-lexicon.md](ia-lexicon.md) for canonical naming (`conversation security state`, `conversation security policy`) and ownership language.
Enforcement guardrail: [ia-boundary-guardrails.md](ia-boundary-guardrails.md) (`cd backend && ./run docs:boundary-check`).
Execution checklist: [sprints/9.3-mls-definition-of-done.md](sprints/9.3-mls-definition-of-done.md).

## One-line reality

Famichat has a solid backend messaging foundation and now includes a real OpenMLS-backed Rust NIF vertical slice with fail-closed gates, encrypted MLS snapshot persistence, and adversarial tests, but it is not production-ready for real family usage yet.

## What works today

1. Real-time channel infrastructure is in place with authenticated joins and telemetry.
2. Core chat domain flows exist for direct/self/group messaging and conversation membership checks.
3. Story 7.4.2 is implemented:
   - Canonical secure endpoint: `POST /api/test/broadcast`
   - Compatibility alias: `POST /api/test/test_events` (deprecated path)
   - Auth + membership authorization enforced
   - Contract outcomes covered (`200/401/403/422`) with no-broadcast guarantees on non-200
4. Accounts/auth foundation is in place (token/session/device/passkey flows), enabling authenticated API and channel behavior.
5. Sprint 9.2 MLS vertical slice is implemented in backend scope:
   - Real OpenMLS-backed NIF path for `create_group -> create_application_message -> process_incoming`
   - MessageService fail-closed runtime health gate (`nif_health`) before encrypt/decrypt operations
   - Canonical MessageService path is characterized with real NIF for ciphertext-at-rest and idempotent repeated reads
   - NIF session snapshot export/restore contract is implemented (state blobs emitted + accepted in core MLS operations)
   - MessageService now persists conversation security state in `conversation_security_states` via `ConversationSecurityStateStore`
   - Legacy metadata envelopes are read for compatibility and migrated into the dedicated store on access
   - Conversation lifecycle orchestration exists in `ConversationSecurityLifecycle` (stage/merge/clear pending commit with optimistic locking)
   - Send path fails closed when a pending commit is staged (`:pending_proposals`), preventing application-message progression during unresolved lifecycle transitions
   - Replay cache export is bounded (max 256 entries) to cap snapshot growth under high-cardinality reads
   - Adversarial contract tests now also cover out-of-order merge/clear sequencing, tampered pending-commit metadata rejection, stage/merge epoch regression rejection, partial snapshot payload tampering rejection, and concurrent stage/merge race outcomes
   - Messaging contract tests continue to cover malformed ciphertext, cross-group ciphertext rejection, and replay rejection
   - Durable client inventory policy is implemented via `ConversationSecurityClientInventoryStore` + `ConversationSecurityKeyPackagePolicy` (`create`, `consume`, `replenish threshold` behavior with optimistic locking; planned rename target remains `ConversationSecurityClientInventoryPolicy`)
   - Client inventory rotation policy is active with trigger-based stale rotation on canonical paths and scheduled batch rotation APIs (`rotate_stale_inventory/2`, `rotate_stale_inventories/1`)
   - Client-inventory lifecycle telemetry events are emitted for ensure/consume/rotation with aggregate counts only (no inventory payload leakage)
   - Rejoin/state-loss recovery durability is implemented via `ConversationSecurityRecoveryLifecycle` + `conversation_security_recoveries` (idempotent recovery refs, fail-closed `:recovery_required` semantics, deterministic recovery tests)
6. Messaging QA is now productized behind first-class run commands:
   - `cd backend && ./run qa:messaging:preflight` (includes migration preflight gate)
   - `cd backend && ./run qa:messaging:fast` (live matrix + WS/HTTP parity + timing artifacts)
   - `cd backend && ./run qa:messaging:deep` (fast loop + canonical-flow coverage artifact)
   - Matrix seed context: `cd backend && ./run runbook:seed:matrix`

## What is still not done

1. Key lifecycle and identity binding are still incomplete for production trust posture (revocation strategy remains open), while client-inventory durability/rotation/telemetry and rejoin recovery durability are now in place.
2. Commit/update/add/remove lifecycle handling needs deeper OpenMLS-backed semantics (pending-commit payload integrity and epoch transition assertions under churn).
3. Multi-node/state-distribution strategy is still undefined for strict cross-node consistency and restart behavior.
4. Client integration documentation is still fragmented (the canonical operator workflow is now published).
5. Repo-wide lint/static-analysis gates still have baseline debt outside current MLS scope.
6. CI wiring for the new QA fast/deep commands is not yet mandatory on PR/nightly.

## What this means for the product

1. Good state for backend engineering validation and controlled internal drills.
2. Not yet a trust-ready family messaging product for broad dogfooding or release.
3. Main remaining risk is moving from vertical-slice crypto to durable, recoverable, production-safe MLS operations.

## Priority Model (Current)

1. **P0**: Core backend messaging security/correctness (MLS implementation + fail-closed guarantees + operational gates).
2. **P1**: LiveView UX and client presentation on top of the same canonical backend path.

## Top 3 next tasks (highest ROI)

1. Complete deeper OpenMLS lifecycle semantics for commit/update/add/remove (payload integrity constraints and epoch transition assertions under churn).
2. Complete remaining key lifecycle hardening (revocation strategy and device/user removal semantics).
3. Wire the new QA fast/deep command path into CI required checks (PR fast + nightly deep) and keep lint/static baseline triage separate.

## Deferred TODO (Do Not Lose)

1. Add "insanely long message" support via attachment/upload overflow flow (for example, auto-convert oversized inline text to `.txt` attachment) while keeping strict inline `content` size caps for broadcast safety.
