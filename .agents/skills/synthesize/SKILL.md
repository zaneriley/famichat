---
name: synthesize
description: Read a research round's agent reports and produce a single consensus document with agreements, tensions, and promotable backlog items.
argument-hint: "<slug> [round-N] [--final]"
---

# Synthesize

Read all agent reports from a research round and produce a single consensus document. Identifies where agents agree, where they disagree, and extracts actionable items formatted for BACKLOG.md.

## Invocation

```
/synthesize <slug>                  # latest round in the most recent date-slug directory
/synthesize <slug> round-2          # specific round
/synthesize <slug> --final          # cross-round synthesis of all rounds
/synthesize .tmp/2026-03-08-foo/round-1/  # explicit path
```

If the argument contains `/`, treat it as a path. Otherwise treat it as a slug and find the most recent `.tmp/*-<slug>/` directory.

## Input Discovery

1. Find the target directory:
   - Slug mode: glob `.tmp/*-<slug>/`, sort by date prefix, use most recent.
   - Path mode: use the path directly.
2. If a round is specified, use that round directory. Otherwise use the highest-numbered `round-*` directory.
3. Read `manifest.md` for context (angles, agent count, topic).
4. Read all `NN-*.md` agent report files in the round directory.
5. If `--final`: read ALL `round-*/consensus.md` files in the slug directory.

Error if no agent reports are found. Warn (but proceed) if fewer reports exist than the manifest claims.

## Consensus Document Structure

Write `consensus.md` to the round directory (or `final-consensus.md` at the slug root for `--final`).

```markdown
# Consensus: <Topic> (Round N)

**Date:** <ISO 8601>
**Agents:** N of M completed
**Angles:** <list>

## Executive Summary
<!-- 3-5 sentences. What did the research find? What is the recommendation? -->

## Agreements
<!-- Findings where 2+ angles converged on the same conclusion -->

### <Agreement title>
- **Supporting angles:** <which angles agree>
- **Confidence:** high | medium | low
- **Detail:** <what they agree on>

## Tensions
<!-- Findings where angles disagreed or identified genuine tradeoffs -->

### <Tension title>
- **Angle A says:** ...
- **Angle B says:** ...
- **Resolution:** <proposed resolution> | UNRESOLVED — needs human input

## Action Items

Every action item MUST include a `because:` field that traces back to a user-visible consequence or a system/security property. The `because:` is what a human reads when deciding whether the item still matters as priorities shift.

If an agent finding is a bare task ("add X to Y") with no articulable consequence, it belongs in **Open Questions** ("Do we need X? What breaks without it?") — not Action Items.

### Blocks Dogfooding (P0)
- <imperative task> — because: <user-facing consequence in ≤15 words> | source: <angle(s)>

### Blocks Confidence (P1)
- <imperative task> — because: <user-facing consequence in ≤15 words> | source: <angle(s)>

### Known Debt (P2)
- <imperative task> — because: <user-facing consequence in ≤15 words> | source: <angle(s)>

### Decisions Needed
- <question> — because: <what is at stake in ≤15 words> | source: <angle(s)>

## Items to Promote to BACKLOG.md
<!-- Pre-formatted for direct copy-paste into BACKLOG.md -->
<!-- Use the exact BACKLOG.md format: checkbox + description + why-clause + pointer + severity + source -->
<!-- The why-clause (after —) is REQUIRED. /promote will reject items without it. -->

- [ ] <imperative description> — <why it matters in ≤15 words> → <path to this consensus.md> | P0-dogfood | agent:consensus
- [ ] <imperative description> — <why it matters in ≤15 words> → <path to this consensus.md> | P1-confidence | agent:consensus
- [-] <cut item with reason> → <path> | agent:consensus

## Open Questions
<!-- Unresolved across all angles. These need human judgment. -->
1. ...
```

## Multi-Round Synthesis (`--final`)

When synthesizing across rounds:

1. Read all `round-*/consensus.md` files in chronological order.
2. **Later rounds win on conflicts.** If round 2 explicitly addresses something from round 1, round 2's position is authoritative.
3. Agreements that persist across rounds are **high confidence**.
4. Findings that appear only in an early round and are not contradicted carry forward.
5. Note which round each finding originates from.

Write `final-consensus.md` to the slug root directory (not inside any round).

## Rules

- Do NOT edit any canonical docs or BACKLOG.md. That is `/promote`'s job.
- Do NOT produce an execution plan or DAG. The consensus answers "what should we do?" not "how should we do it?"
- The `## Items to Promote` section is mandatory. This is the bridge to the project tracking system.
- **Every action item and promotable item MUST have a why-clause** (≤15 words) explaining the user-facing or system consequence. A bare task with no articulable "because" goes to Open Questions, not Action Items. This is the single most important rule for backlog quality — tasks without rationale cannot be triaged when priorities shift.
- When severity is ambiguous (P0 vs P1), default to P1 and note the uncertainty.
- When agents disagree and no clear resolution exists, mark the tension as UNRESOLVED. Do not force consensus.
- Attribute every finding to its source angle(s). No orphan claims.
- If a finding is already tracked in BACKLOG.md or completed in BACKLOG-ARCHIVE.md, note "already tracked" or "already done" instead of re-listing it for promotion.
