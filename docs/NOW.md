# Famichat NOW

**Last Updated**: 2026-02-25

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
   - MessageService now persists MLS session state as an encrypted envelope (`mls.session_snapshot_encrypted`) and no longer writes clear snapshot maps
   - Replay cache export is bounded (max 256 entries) to cap snapshot growth under high-cardinality reads
   - Adversarial contract tests cover malformed ciphertext, cross-group ciphertext rejection, and replay rejection

## What is still not done

1. MLS state is persisted in encrypted conversation metadata, but a dedicated versioned state model (group/epoch/pending commit lifecycle + optimistic locking) is still not implemented.
2. Key lifecycle and identity binding are incomplete for production trust posture (key package persistence/rotation, rejoin recovery durability, revocation strategy).
3. Multi-node/state-distribution strategy is still undefined for strict cross-node consistency and restart behavior.
4. Client integration documentation is still fragmented (the canonical operator workflow is now published).
5. Repo-wide lint/static-analysis gates still have baseline debt outside current MLS scope.

## What this means for the product

1. Good state for backend engineering validation and controlled internal drills.
2. Not yet a trust-ready family messaging product for broad dogfooding or release.
3. Main remaining risk is moving from vertical-slice crypto to durable, recoverable, production-safe MLS operations.

## Priority Model (Current)

1. **P0**: Core backend messaging security/correctness (MLS implementation + fail-closed guarantees + operational gates).
2. **P1**: LiveView UX and client presentation on top of the same canonical backend path.

## Top 3 next tasks (highest ROI)

1. Move from encrypted metadata envelope to a dedicated MLS state store with versioning and optimistic locking, then prove crash/restart and concurrent-read/write correctness.
2. Expand adversarial MLS matrix to commit/update/add/remove ordering and malformed protocol payloads with strict fail-closed assertions.
3. Lock operational feedback loops for backend confidence: canonical-flow timing capture, coverage snapshot, and lint/static baseline triage.

## Deferred TODO (Do Not Lose)

1. Add "insanely long message" support via attachment/upload overflow flow (for example, auto-convert oversized inline text to `.txt` attachment) while keeping strict inline `content` size caps for broadcast safety.
