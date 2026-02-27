# Autonomous Implementation Loop

**Last Updated**: 2026-02-26  
**Default Mode**: Keep shipping while user is away.

## Goal

Execute high-quality work that fulfills the spirit of Famichat's goals (`VISION.md`, `JTBD.md`, `ENCRYPTION.md`) through a repeatable orchestration loop:

`spawn -> IA review -> implement -> spawn review -> spawn fixes -> red team -> docs sync -> commit`

Primary stop condition reference: `docs/sprints/9.4-mls-product-diff-done-state.md` (user-minimum ship gate).

## Non-goals

- Waiting for perfect infra before delivering robust behavior.
- Producing checklist artifacts without runtime evidence.
- Creating separate "LLM-only" execution paths.

## Loop Contract

1. Pick one thin slice with clear user outcome and clear boundaries.
2. Spawn IA/DDD reviews first and reconcile naming, ownership, and API shape.
3. Write/expand failing tests that prove intended outcomes and invariants.
4. Implement minimal production code to pass those tests.
5. Spawn peer review on:
   - security/fail-closed posture
   - performance + latency risk
   - readability/maintainability/idiomatic Elixir
6. Apply all high-confidence fixes.
7. Spawn red-team review to actively break the touched behavior.
8. Add/adjust adversarial tests until break attempts are covered.
9. Run verification:
   - focused tests for touched files
   - adversarial suites for boundary behavior
   - broader regression slice
10. Update continuity docs:
    - `.tmp/operations/agent-journal.md`
    - `.tmp/operations/questions-for-human.md`
    - `.tmp/operations/checkpoint-ledger.md`
    - `docs/sprints/STATUS.md` and `docs/NOW.md` when status shifts
11. Commit with conventional commit message and evidence summary.

## Decision Rules (No Hard Stops)

- Prefer robust synchronous behavior now when usage is tiny; add explicit TODO hooks for async infra (for example, Oban) instead of blocking progress.
- Use additive schema changes by default; avoid destructive migrations unless absolutely required.
- Choose fail-closed behavior for security ambiguity.
- Keep canonical paths shared across CLI/API/frontend/tests.
- If uncertain between "faster" and "clearer/safer", choose clearer/safer and document the tradeoff.

## Long-Run Autonomy

1. Work can continue for extended windows without human check-in when changes remain aligned to vision/JTBD/encryption docs.
2. Report back at checkpoint-level deltas (product behavior changed, gate set changed, or risk posture changed), not at every micro-slice.
3. Keep `.tmp/operations/*` updated so context resets do not lose intent, tradeoffs, or pending questions.

## Key Checkpoint (Current)

**Checkpoint ID**: `C1-mls-durability-baseline`

Done when all are true:

1. Recovery/revocation flows are idempotent and deterministic under retries/concurrency.
2. Lifecycle transitions fail closed on invalid state, stale epochs, or tampered payloads.
3. Tests include adversarial coverage, not only happy paths.
4. Documentation reflects reality and next work, with no major drift.

## Evidence Standard

For each checkpoint, record:

- exact commands run
- pass/fail results
- unresolved risks
- next narrow slice

Record this in `.tmp/operations/checkpoint-ledger.md`.
