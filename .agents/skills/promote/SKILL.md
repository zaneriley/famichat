---
name: promote
description: Promote findings from a research consensus into canonical docs (BACKLOG.md, NOW.md, SPEC.md, etc). Dry run by default.
argument-hint: "[path to consensus.md] [--apply] [--to backlog,now,spec,...]"
---

# Promote

Read a consensus document from a research round and update the canonical project docs. Routes findings to the right docs, formats BACKLOG.md items, checks for contradictions.

This skill runs in the main thread with zero sub-agents. All canonical docs fit in one context window.

## Invocation

```
/promote                                    # auto-find most recent consensus.md
/promote .tmp/2026-03-08-foo/consensus.md   # explicit path
/promote --apply                            # skip confirmation, edit immediately
/promote --to backlog,now                   # only update these docs
```

## Step 1: Identify Source

- If a path is provided, use it.
- Otherwise, find the most recent consensus: glob `.tmp/*/final-consensus.md` or `.tmp/*/round-*/consensus.md`, sort by date, use most recent.
- If ambiguous, ask the user.

## Step 2: Read All Inputs

Read the consensus document fully. Then read ALL canonical docs fully:

1. `docs/ia-lexicon.md`
2. `docs/ia-boundary-guardrails.md`
3. `docs/SPEC.md`
4. `docs/E2EE_INTEGRATION.md`
5. `docs/NOW.md`
6. `docs/BACKLOG.md`
7. `docs/brand-positioning.md`

This is ~1500-2000 lines total. Read them all before making any decisions.

## Step 3: Triage (Routing)

For each canonical doc, determine: does the consensus contain findings that belong here and are NOT already present?

If `--to` is specified, only consider the listed docs.

Output a routing table:

```
Routing:
  ia-lexicon.md        → no changes
  ia-boundary-guardrails.md → no changes (already updated)
  SPEC.md              → add /families/new as entry point
  E2EE_INTEGRATION.md  → no changes
  NOW.md               → update dogfood blocker table
  BACKLOG.md           → add 5 items (3 P0, 2 P1), 2 cuts
  brand-positioning.md → no changes
```

## Step 4: Draft Changes

For each doc that needs changes, draft the specific edits.

### BACKLOG.md Format Contract

Items MUST follow this exact format:

```
- [ ] Short imperative description — why it matters in ≤15 words → path/to/detail.md | severity | source
```

The why-clause (after `—`) is **required**. It explains the user-facing or system consequence if the item is not done. This is what a human reads when triaging the backlog as priorities shift.

**Reject rule:** If a consensus action item has no `because:` field or the rationale is purely technical with no articulable consequence ("add field X to table Y"), do NOT promote it. Instead, list it in the dry-run output under "Items needing rationale" and ask the user to supply a why-clause before promotion.

Severity mapping from consensus:
- Consensus "Blocks Dogfooding" / P0 → `P0-dogfood`
- Consensus "Blocks Confidence" / P1 → `P1-confidence`
- Consensus "Known Debt" / P2 → `P2-debt`
- Consensus "Cut" → `[-] Description (reason) → path | agent:consensus`
- Consensus "Decisions Needed" → goes in the "Decisions needed" section

Source tag for all promoted items: `agent:consensus`

**Dedup rule:** Before adding any item, grep BACKLOG.md for the key noun (e.g., "PutRemoteIp", "reconnect"). If a matching item exists, skip it and note "already tracked." If it exists at a different severity, flag for human review — do not silently change severity.

### Example Translation

```
Consensus says:
  "Issue 1: PutRemoteIp ignores X-Forwarded-For"
  because: all visitors share one rate-limit bucket behind any proxy
  Severity: Blocks Dogfooding

BACKLOG.md item:
  - [ ] Fix PutRemoteIp to parse X-Forwarded-For — all visitors share one rate-limit bucket behind any proxy → .tmp/2026-03-08-new-accounts/acceptance/consensus.md | P0-dogfood | agent:consensus
```

## Step 5: Present (Dry Run — This Is the Default)

Show the user:
1. The routing table
2. Each planned edit (what will be added/changed in each doc)
3. Items skipped due to dedup ("already tracked")
4. Open questions that need human judgment (severity disputes, ADR suggestions)

Wait for user confirmation before proceeding. If `--apply` was passed, skip confirmation.

## Step 6: Apply

Edit docs in this order (dependencies flow downward):
1. `docs/ia-lexicon.md` — new terms must be canonical first
2. `docs/ia-boundary-guardrails.md` — governance for new terms
3. `docs/SPEC.md` — design-level changes
4. `docs/E2EE_INTEGRATION.md` — security posture (rarely changed)
5. `docs/NOW.md` — current state, references SPEC and BACKLOG
6. `docs/BACKLOG.md` — implementation items, references everything above
7. `docs/brand-positioning.md` — copy/voice (rarely changed)

## Step 7: Verify

After all edits, re-read the edited docs and check:
- Every P0 BACKLOG item has a corresponding mention in NOW.md's blockers
- Every entry point in NOW.md has a matching SPEC.md description
- No BACKLOG.md pointer references a nonexistent file
- No new term in lexicon is missing from guardrails (if it is a boundary term)

Report any contradictions found.

## Rules

- Do NOT create new files. /promote only edits existing canonical docs.
- Do NOT create ADRs. If the consensus contains an architectural decision, add a BACKLOG.md item: `- [ ] Write ADR for <decision> | P1-confidence | agent:consensus`
- Do NOT archive .tmp/ source files. BACKLOG.md pointers reference them.
- Do NOT change severity of existing BACKLOG.md items without flagging for human review.
- When unsure about severity (P0 vs P1), default to P1 and flag it.
- Running /promote twice on the same consensus should produce zero duplicates.
- Note in output: "Source files in .tmp/ are still referenced by BACKLOG.md pointers. Do not delete them until pointed-to items are resolved."
