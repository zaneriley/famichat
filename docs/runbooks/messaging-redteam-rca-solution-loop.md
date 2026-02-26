# Messaging Red-Team + RCA + Solution Triage Runbook

**Status**: Active  
**Purpose**: Standardize how we discover messaging bugs, triage root causes with agents, and converge on robust solutions with auditable artifacts.

## Why this runbook exists

This captures the working loop we have been using so it is repeatable and not person-dependent:
1. Blindly break messaging behavior with black-box probes.
2. Confirm and log user-visible bugs.
3. Run multi-agent RCA for each confirmed bug.
4. Run multi-agent solution triage and choose one architecture.
5. Re-test blindly after implementation.

## Scope

Use this for messaging areas including:
1. `self`
2. `direct`
3. `group`
4. `family`
5. Channel join/send behavior and visibility boundaries

## Non-Negotiable Rules

1. Discovery phase is black-box only: no source/test inspection to decide whether something is a bug.
2. Do not rely on admin-only surfaces for discovery.
3. Start each red-team round with a fresh bug file to avoid bias.
4. Every bug added to the list must have repro evidence and at least one independent confirmation pass.
5. RCA and solution phases may inspect code and logs after discovery confirms user-visible behavior.

## Prerequisites

1. Runtime is stable (`docker compose ps` healthy, compile state stable).
2. Product context loaded by all agents:
   - `docs/VISION.md`
   - `docs/JTBD.md`
   - `docs/ARCHITECTURE.md`
   - `_agents/AGENTS.md` section 10 (messaging invariants)
3. Fresh probe context exists (users, tokens, conversation IDs/topics for `self/direct/group/family`).

## Workflow

### 0) Initialize a New Cycle

1. Create a cycle folder with date prefix:
   - `.tmp/<YYYY-MM-DD>-<slug>/`
2. Create a fresh blind bug list:
   - `.tmp/_bugs/list_blind_redteam_<YYYY-MM-DD>.md`
3. Save fresh probe context JSON:
   - `.tmp/_bugs/probe_context_blind_<YYYY-MM-DD>.json`

### 1) Blind Red-Team Swarm

1. Spawn 3-5 agents with independent attack charters:
   - access/isolation oracle probing
   - multi-actor visibility matrix
   - protocol fuzzing
   - concurrency/stress behavior
2. Require each agent to output its own artifact (JSON or markdown) under a per-round folder:
   - `.tmp/_redteam_blind_<YYYY-MM-DD>/`
3. Aggregate only confirmed user-visible bugs into the fresh blind list.

### 2) RCA Triage Swarm

1. For each confirmed bug, spawn 3-5 RCA agents with distinct lenses:
   - runtime timeline and triggering chain
   - compile/reload/build mechanics
   - architecture/dependency boundary analysis
   - test and observability gap analysis
   - operational/SRE blast-radius analysis
2. Save bug-scoped RCA outputs:
   - `.tmp/_rca_bug<id>_<YYYY-MM-DD>/`
3. Produce one synthesis doc with:
   - immediate cause
   - trigger cause
   - systemic cause
   - recurrence guards

### 3) Solution Triage Swarm

1. Spawn at least 3 solution agents with explicit goals:
   - most robust architecture
   - highest performance approach
   - most upstream/maintainable IA/DDD shape
2. Save individual proposals under:
   - `.tmp/_proposals/bug<id>_*.md`
3. Save the chosen consolidated proposal in a date-prefixed cycle folder:
   - `.tmp/<YYYY-MM-DD>-<slug>/`
4. Ensure selection criteria are explicit:
   - robustness first
   - performance second
   - maintainability/clarity third

### 4) Implement + Peer Review

1. Implement only the selected proposal.
2. Spawn peer-review agents for:
   - security/isolation correctness
   - IA/DDD naming and boundaries
   - performance and operational impact
3. Resolve review findings before declaring fix complete.

### 5) Verify + Re-Red-Team

1. Replay targeted reproducer for the fixed bug.
2. Run a fresh blind red-team round where agents are not told prior bug specifics.
3. Update bug list states explicitly:
   - `candidate`
   - `confirmed`
   - `fixed`
   - `regression-tested`
   - `not reproducible now`

## Artifact Convention (Required)

1. `Discovery log`:
   - `.tmp/_bugs/list_blind_redteam_<YYYY-MM-DD>.md`
2. `Probe context`:
   - `.tmp/_bugs/probe_context_blind_<YYYY-MM-DD>.json`
3. `Red-team raw outputs`:
   - `.tmp/_redteam_blind_<YYYY-MM-DD>/`
4. `RCA packets by bug`:
   - `.tmp/_rca_bug<id>_<YYYY-MM-DD>/`
5. `Solution proposals`:
   - `.tmp/_proposals/bug<id>_*.md`
6. `Canonical cycle packet` (final triage outputs):
   - `.tmp/<YYYY-MM-DD>-<slug>/`
   - Include: final RCA synthesis, chosen proposal, implementation notes, verification summary.

## Reference Execution (2026-02-25)

This process was used in practice with:
1. Fresh blind bug list and probe context.
2. Multi-agent blind red-team run.
3. Bug-specific 5-agent RCA run for bug #1.
4. 3-agent solution triage (robust/perf/upstream).
5. Consolidated proposal saved in `.tmp/_proposals`.

## Definition of Done for a Messaging Bug Cycle

1. Blind discovery artifacts exist and are reproducible.
2. RCA synthesis exists per confirmed bug.
3. Chosen solution proposal is documented and saved in `.tmp/<YYYY-MM-DD>-<slug>/`.
4. Fix is implemented and peer-reviewed.
5. A post-fix blind run has been executed and bug states updated.
