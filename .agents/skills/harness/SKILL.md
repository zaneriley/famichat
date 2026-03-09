---
name: harness
description: Read review findings, identify recurring LLM mistakes, and propose or implement harness improvements (skill prompts, hooks, CI checks) to prevent them.
argument-hint: "[path to .tmp/<round>/ directory]"
---

# Harness: Sharpen the Saw

After a review round, read the findings, identify recurring mistake patterns, and improve the tooling that prevents those mistakes from happening again.

## When to Use

Run this after a review round when you notice agents making the same class of mistake repeatedly. It is user-invoked, not automatic.

## Invocation

```
/harness .tmp/2026-03-08-new-accounts/     # specific round
/harness                                    # most recent .tmp/ directory by date prefix
```

## Step 1: Read Inputs

**Primary input** (the review findings):
- All `*.md` files in the target `.tmp/` directory (and subdirectories)

**Reference input** (the standards being violated):
- `docs/ia-boundary-guardrails.md`
- `docs/ia-lexicon.md`
- `docs/SPEC.md`
- `docs/BACKLOG.md`
- All existing skill files: `.agents/skills/*/SKILL.md`
- CI config: `.github/workflows/lint.yml`
- Project instructions: `AGENTS.md` (if it exists)

## Step 2: Categorize Findings

Read every finding across all review files. Categorize each by mistake type:

| Category | Example |
|----------|---------|
| Boundary violation | Onboarding directly inserts Chat-owned schemas |
| Missing validation | Ecto changeset lacks validate_length on string field |
| State management | LiveView assign state lost on reconnect |
| Naming drift | `:recoverable` vs `:retryable` for same concept |
| Infrastructure assumption | PutRemoteIp ignores reverse proxy |
| Duplication | 75% code overlap between two LiveViews |

Count occurrences per category. A category qualifies for a harness if it has **2+ findings** in this round.

## Step 3: Check Existing Harnesses

For each qualifying category, check whether an automated check already exists:

- Does CI already catch this? (Check `lint.yml`)
- Does a skill already instruct agents to check for this? (Check SKILL.md files)
- Does a project-level instruction already cover this? (Check AGENTS.md)

**If a harness exists but agents didn't use it:** The fix is surfacing, not creating. Add the existing check to the relevant skill prompt.

**If no harness exists:** Propose a new one.

## Step 4: Propose or Apply

### Output types (ordered by leverage, lowest risk first)

**1. Skill prompt updates** — APPLY DIRECTLY
Add constraints to existing `.agents/skills/*/SKILL.md` files. Example: adding "run `./run docs:boundary-check` before declaring done" to `/implement`.

This is the highest-leverage, lowest-risk harness. The cost of a wrong skill prompt update is near zero (agents run an extra check that doesn't help). The cost of a missing one is repeated review findings.

**2. Project instruction updates** — APPLY DIRECTLY
Add instructions to `AGENTS.md` that all agents see regardless of which skill is running.

**3. agents hooks** — PROPOSE ONLY
Hooks in `.agents/hooks/` that run pre/post tool execution. These add latency and may break tool execution. Propose with risk assessment. Do not implement without user approval.

**4. CI workflow additions** — PROPOSE ONLY
New steps in `.github/workflows/lint.yml`. These block merges if they fail. Propose with false-positive assessment.

**5. Mix tasks / custom lints** — PROPOSE ONLY IF GREP IS INSUFFICIENT
Only when a pattern is too complex for a simple ripgrep rule.

**Never propose:** Git hooks (friction for human developer, agents may not trigger them).

## Step 5: Output

Structure the output as:

```markdown
## Applied

### 1. <What was done>
- **File:** <path to edited file>
- **Change:** <what was added/modified>
- **Prevents:** <which findings from which report>

## Proposed

### 2. <What is proposed>
- **File:** <path that would be created/edited>
- **Change:** <proposed addition>
- **Prevents:** <which findings>
- **Risk:** <what could go wrong>
- **To apply:** describe how to apply manually or say "approve and I'll implement"

## Not Addressed

### <Category>
- **Reason:** <already tracked in BACKLOG.md / SPEC explicitly blesses this / one-off finding>
```

## Escalation Ladder

If a mistake category persists across rounds despite a skill prompt update, escalate:

1. **Skill prompt instruction** — relies on agent compliance
2. **Project-level instruction (AGENTS.md)** — broader reach, same compliance model
3. **agents hook** — automated enforcement, does not rely on agent compliance
4. **CI check** — automated, blocks merge

Each `/harness` invocation proposes one escalation level per category. The user decides whether to apply.

## Prevention Hierarchy

When proposing harness improvements, prefer solutions higher on this list. Each level is strictly better than the one below it.

1. **Structural impossibility** — Change the architecture so the bug cannot exist. Example: constrain a route param type instead of validating downstream.
2. **Static analysis (Credo rules, boundary-check grep)** — Catch it at compile/lint time by analyzing real code structure. A custom Credo rule that checks "every `field :foo, :string` has a corresponding `validate_length`" is a compile-time guarantee that travels with the codebase.
3. **Integration test against real running system** — Catch it at test time with real behavior, real DB, real endpoint. Valuable when the bug is about runtime interaction (e.g., WebSocket reconnect losing state).
4. **Mocked smoke test** — **Avoid.** A test that mocks the DB, mocks the endpoint, and asserts against a fake response tests the test, not the system. It gives false confidence and breaks on refactors for the wrong reasons.

When evaluating proposals: a custom Credo rule is almost always better than a smoke test. A DB-level `CHECK` constraint is better than an application-level validation test. A route constraint is better than a plug that rejects bad values.

## Scope Limits

- Max **3 finding categories** per invocation. Pick the highest-leverage ones.
- Max **1 CI change** proposed per invocation.
- Max **1 new file** proposed per invocation.
- Always start with skill prompt updates before proposing anything heavier.
- Always surface existing checks before creating new ones.

## Rules

- Do NOT fix product code. /harness fixes the system that produces product code.
- Do NOT add findings to BACKLOG.md. Harness improvements are meta-work, not product work.
- Do NOT propose harnesses for one-off findings. The threshold is 2+ occurrences in a round.
- Do NOT propose harnesses for things the SPEC explicitly blesses (e.g., "throwaway views, keep coupled").
- When applying skill prompt updates, make minimal, targeted edits. Do not rewrite the skill.
