# Famichat NOW

**Last Updated**: 2026-02-27

Use [ia-lexicon.md](ia-lexicon.md) for canonical naming (`conversation security state`, `conversation security policy`) and ownership language.
Enforcement guardrail: [ia-boundary-guardrails.md](ia-boundary-guardrails.md) (`cd backend && ./run docs:boundary-check`).
Execution checklist: [sprints/9.3-mls-definition-of-done.md](sprints/9.3-mls-definition-of-done.md).
Product done point: [sprints/9.4-mls-product-diff-done-state.md](sprints/9.4-mls-product-diff-done-state.md).
Autonomous execution loop: [runbooks/autonomous-implementation-loop.md](runbooks/autonomous-implementation-loop.md).
Continuity memory:
- [../.tmp/operations/agent-journal.md](../.tmp/operations/agent-journal.md)
- [../.tmp/operations/questions-for-human.md](../.tmp/operations/questions-for-human.md)
- [../.tmp/operations/checkpoint-ledger.md](../.tmp/operations/checkpoint-ledger.md)

## One-line reality

Famichat has a solid backend messaging foundation and now includes a real OpenMLS-backed Rust NIF vertical slice with fail-closed gates, encrypted MLS snapshot persistence, and adversarial tests, but it is not production-ready for real family usage yet.

## What works today

1. Real-time channel infrastructure is in place with authenticated joins and telemetry.
2. Core chat domain flows exist for direct/self/group messaging and conversation membership checks.
3. Story 7.4.2 is implemented:
   - Canonical secure endpoint: `POST /api/v1/conversations/:id/messages`
   - Canonical recovery endpoint: `POST /api/v1/conversations/:id/security/recover`
   - Compatibility alias: `POST /api/test/test_events` (deprecated path)
   - Auth + membership authorization enforced
   - Contract outcomes covered (`201/401/404/409/422`) with no-broadcast guarantees on non-success
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
   - Adversarial contract tests now also cover out-of-order merge/clear sequencing, tampered pending-commit metadata rejection, stage/merge epoch regression rejection, malformed epoch encoding rejection (including NIF-shaped string epochs), partial snapshot payload tampering rejection, and concurrent stage/merge race outcomes
   - Conversation lifecycle now enforces strict epoch progression under churn:
     - stage payload epoch must equal exactly `current_epoch + 1` (or defaults to that when omitted)
     - merge payload epoch must equal staged epoch when present
     - numeric string epochs are parsed; malformed epoch fields fail closed
   - Stage/merge lifecycle now rejects contradictory payload hints (group-id mismatch, wrong operation hint, invalid `staged`/`merged`/`pending_commit` flags) instead of accepting inconsistent commit metadata
   - Concurrency characterization now covers mixed stage-operation races and clear-vs-merge races, proving single-winner stage semantics, bounded merge winners, and post-race lifecycle usability
   - Messaging contract tests continue to cover malformed ciphertext, cross-group ciphertext rejection, and replay rejection
   - Durable client inventory policy is implemented via `ConversationSecurityClientInventoryStore` + `ConversationSecurityKeyPackagePolicy` (`create`, `consume`, `replenish threshold` behavior with optimistic locking; planned rename target remains `ConversationSecurityClientInventoryPolicy`)
   - Client inventory rotation policy is active with trigger-based stale rotation on canonical paths and scheduled batch rotation APIs (`rotate_stale_inventory/2`, `rotate_stale_inventories/1`)
   - Client-inventory lifecycle telemetry events are emitted for ensure/consume/rotation with aggregate counts only (no inventory payload leakage)
   - Rejoin/state-loss recovery durability is implemented via `ConversationSecurityRecoveryLifecycle` + `conversation_security_recoveries` (idempotent recovery refs, fail-closed `:recovery_required` semantics, deterministic recovery tests)
   - Recovery lifecycle now retries transient stale-lock persistence races (bounded retries) so contention does not prematurely hard-fail an otherwise valid recovery
6. Messaging QA is now productized behind first-class run commands:
   - Gates now execute a 10-scenario matrix (`S1..F2 + R1 + R2`) and emit artifacted outcomes.
   - Continuity/reconnect (`C1`) is enforced as a hard integration gate via `continuity_contract.txt` in `qa:messaging:*`.
   - Latest stable findings:
     - fast: `.tmp/_qa_messaging/20260227T061442Z_fast` -> PASS (`R1: PASS`, `continuity_contract: PASS`)
     - fast: `.tmp/_qa_messaging/20260227T060141Z_fast` -> PASS (`R1: PASS`, `continuity_contract: PASS`)
     - deep: `.tmp/_qa_messaging/20260227T060329Z_deep` -> PASS (`R1: PASS`, `continuity_contract: PASS`, `recovery_rejoin_contract: PASS`)
     - repeat fast: `.tmp/_qa_messaging/20260227T060555Z_fast` -> PASS (`R1: PASS`, `continuity_contract: PASS`)
     - repeat deep: `.tmp/_qa_messaging/20260227T060744Z_deep` -> PASS (`R1: PASS`, `continuity_contract: PASS`, `recovery_rejoin_contract: PASS`)
     - fast: `.tmp/_qa_messaging/20260226T143234Z_fast` -> PASS
     - deep: `.tmp/_qa_messaging/20260226T143234Z_deep` -> PASS (`canonical_flow_coverage: PASS`, `recovery_rejoin_contract: PASS`)
     - additional sequential verification: `.tmp/_qa_messaging/20260226T142958Z_fast` + `.tmp/_qa_messaging/20260226T143046Z_deep` (both PASS)
     - latest fast verification after lifecycle hardening changes: `.tmp/_qa_messaging/20260227T002838Z_fast` -> PASS
     - latest fast verification after recovery+revocation churn hardening: `.tmp/_qa_messaging/20260227T003310Z_fast` -> PASS
     - latest fast verification with first-class `R2`: `.tmp/_qa_messaging/20260227T004329Z_fast` -> PASS
     - latest deep verification with first-class `R2`: `.tmp/_qa_messaging/20260227T004411Z_deep` -> PASS (`canonical_flow_coverage: PASS`, `recovery_rejoin_contract: PASS`)
    - latest lock/isolation verification pair:
      - `.tmp/_qa_messaging/20260227T014815Z_fast` -> BLOCKED (`reason: qa_run_already_active`)
      - `.tmp/_qa_messaging/20260227T014811Z_fast` -> PASS
    - latest clean post-restart verification:
      - fast: `.tmp/_qa_messaging/20260227T015152Z_fast` -> PASS
      - deep: `.tmp/_qa_messaging/20260227T014954Z_deep` -> PASS (`canonical_flow_coverage: PASS`, `recovery_rejoin_contract: PASS`)
    - serialized repeatability burn-in (`3x fast + 2x deep`, no overlap):
      - fast: `.tmp/_qa_messaging/20260227T015741Z_fast` -> PASS
      - fast: `.tmp/_qa_messaging/20260227T015846Z_fast` -> PASS
      - deep: `.tmp/_qa_messaging/20260227T015950Z_deep` -> PASS
      - fast: `.tmp/_qa_messaging/20260227T020103Z_fast` -> PASS
      - deep: `.tmp/_qa_messaging/20260227T020218Z_deep` -> PASS
    - post-peer-review hardening verification:
      - fast: `.tmp/_qa_messaging/20260227T021537Z_fast` -> PASS
      - deep: `.tmp/_qa_messaging/20260227T021711Z_deep` -> PASS
	    - post-persistence-identity hardening verification:
	      - fast: `.tmp/_qa_messaging/20260227T022058Z_fast` -> PASS
	      - deep: `.tmp/_qa_messaging/20260227T022239Z_deep` -> PASS
	    - post-guard-observer hardening verification:
	      - fast: `.tmp/_qa_messaging/20260227T022941Z_fast` -> PASS
	      - deep: `.tmp/_qa_messaging/20260227T023121Z_deep` -> PASS
      - canonical `/api/v1` runner verification after migration:
        - fast: `.tmp/_qa_messaging/20260227T052825Z_fast` -> PASS
        - deep: `.tmp/_qa_messaging/20260227T053021Z_deep` -> PASS (`canonical_flow_coverage: PASS`, `recovery_rejoin_contract: PASS`)
	     - `R1` assertions in both runs: healthy receives `new_msg`, revoked receives no `new_msg`, revoked receives explicit `security_state`.
	     - `R2` assertions in both runs: `reset_status=200`, `recover_status=200`, replay `recover_status=200`, replay is idempotent, and post-recovery send is delivered/persisted.
	     - gate semantics now classify unrunnable required scenarios as `BLOCKED` (not ambiguous `FAIL`) and report `blocked_failures` in `gate_report.json`.
	     - seed matrix now uses UUID-backed device ids to reduce revocation/probe nondeterminism from device-id reuse.
    - QA harness now enforces a single active run lock (`reason: qa_run_already_active`) and releases lock only on main run exit (no subshell unlock drift).
    - lock acquisition now treats missing-pid lock dirs as in-flight unless stale (`QA_RUN_LOCK_STALE_SECONDS`) to reduce lock-steal races.
    - probe transport calls now enforce bounded curl timeouts (`QA_CURL_CONNECT_TIMEOUT_SECONDS`, `QA_CURL_MAX_TIME_SECONDS`) so failures emit scenario evidence instead of hanging runs.
	    - transport status normalization maps curl `000` to `-1` sentinel to avoid ambiguous JSON `0` statuses.
	    - persistence checks now validate message identity in `history_after` (not only count deltas) to reduce false confidence/false failures from background traffic.
	    - reject-path scenarios now enforce guard-observer WS parity (`guard_ws_parity`) to catch unauthorized fanout leaks explicitly.
      - matrix WS parity now matches on stable `message_id` only (no body fallback), so MLS ciphertext bodies do not cause false WS failures.
      - matrix seeding now uses run-scoped families/users and pre-seeded recovery for matrix conversations, preventing stale-state history drift across runs.
	    - preflight times out hung `docker compose ps` and falls back to `docker ps`.
   - Matrix seed and command path remain available via `runbook:seed:matrix`, `qa:messaging:fast`, and `qa:messaging:deep`.
   - GitHub Actions now executes `qa:messaging:fast` on PR/main and `qa:messaging:deep` nightly (`.github/workflows/messaging-qa.yml`), uploading gate artifacts.
7. Revoked connected channel clients are now fail-closed for new activity:
   - `new_msg` and `message_ack` return explicit `device_revoked` state.
   - Broadcast delivery path now emits `security_state` and stops the revoked channel before delivering `new_msg`.
   - Coverage includes channel contracts plus integration flow (`revoked_device_security_flow_test.exs`).
8. Revocation lifecycle now has explicit seal/fail APIs:
   - `Chat.complete_conversation_revocation/3` (requires committed epoch to transition pending -> completed)
   - `Chat.fail_conversation_revocation/3` (requires explicit error code to transition pending -> failed)
   - Idempotent completion/failure behavior is covered in `conversation_security_revocation_lifecycle_test.exs`.
9. MLS merge lifecycle now seals active revocation journal entries:
   - `ConversationSecurityLifecycle.merge_pending_commit/2` completes active revocations only for `mls_remove` merges, in the same persistence transaction as state persistence.
   - Coverage proves:
     - in-progress and pending revocations both seal on `mls_remove` merge
     - non-remove merges leave revocations active
     - a later remove merge seals previously-active revocations with the later epoch
     (`conversation_security_lifecycle_test.exs`).
   - Latest deep QA artifact after this wiring: `.tmp/_qa_messaging/20260226T102453Z` (PASS, `R1` PASS, no failed scenarios).
10. Recovery-required contract is now explicit and end-to-end characterized:
   - Channel sends now return explicit `recovery_required` + `recover_conversation_security_state` action when MLS state is missing.
   - Canonical HTTP send (`POST /api/v1/conversations/:id/messages`) now returns `409` with explicit `recovery_required` and recovery action instead of generic invalid request.
   - Pending-commit send now returns explicit `409` (`conversation_security_blocked`, `code: pending_proposals`, action `wait_for_pending_commit`) instead of generic invalid request.
   - Integration characterization covers: fail with `recovery_required` -> recover via `Chat.recover_conversation_security_state/3` -> idempotent replay -> send succeeds (`recovery_rejoin_security_flow_test.exs`).

## What is still not done

1. Key lifecycle and identity binding are still incomplete for production trust posture (revocation sealing/commit semantics remain open), while client-inventory durability/rotation/telemetry and rejoin recovery durability are now in place.
2. Commit/update/add/remove lifecycle handling needs deeper OpenMLS-backed semantics (pending-commit payload integrity and epoch transition assertions under churn).
3. Multi-node/state-distribution strategy is still undefined for strict cross-node consistency and restart behavior.
4. End-to-end confidence on backend gates is now supported by a serialized burn-in pass set (`3x fast + 2x deep`, all PASS); remaining closure is user-facing UX proof, not backend gate determinism.
5. Repo-wide lint/static-analysis gates still have baseline debt outside current MLS scope.
6. CI workflow is wired, but repository required-check enforcement and failure escalation ownership are still not formally locked.

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
3. Finalize required-check enforcement + escalation ownership for the QA workflow, and keep repeatability evidence fresh in artifacts.

## Deferred TODO (Do Not Lose)

1. Add "insanely long message" support via attachment/upload overflow flow (for example, auto-convert oversized inline text to `.txt` attachment) while keeping strict inline `content` size caps for broadcast safety.
