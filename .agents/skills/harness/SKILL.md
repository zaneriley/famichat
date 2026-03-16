---
name: harness
description: Read review findings, identify recurring mistake patterns, and implement automated enforcement (CI checks, lint rules, hooks) to prevent them. Skill prompt updates are a last resort.
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

### Output types (ordered by leverage, highest first)

The goal is enforcement that does not depend on the LLM having read instructions. Prompt updates are context bloat — they rely on agent compliance and grow the instruction surface indefinitely. Prefer solutions the LLM cannot ignore.

**1. CI workflow additions** — APPLY if grep is straightforward; otherwise PROPOSE
New steps in `.github/workflows/lint.yml`. These block merges unconditionally — no agent compliance required. A failing CI step is absolute. A prompt instruction is a suggestion.

- Use `rg` for pattern-based checks (missing registrations, banned strings, naming violations)
- Use `mix credo` custom rules for Elixir structural checks
- Always assess false-positive risk before applying

**2. Custom lint / Credo rules** — PROPOSE ONLY
When a pattern is too structural for a simple grep (e.g., "every `:string` field in a changeset must have `validate_length`"). These run at compile time and travel with the codebase. More work to write, zero ongoing maintenance cost.

**3. Claude Code hooks** — PROPOSE ONLY
Hooks in `.claude/hooks/` that run on tool events (e.g., pre-Write, post-Edit). These catch mistakes at the moment they happen, before commit. They add latency but are automatic. Propose with risk assessment.

**4. Skill-scoped prompt updates** — APPLY DIRECTLY, but only when no automated check is feasible
Add to `.agents/skills/*/SKILL.md` only. Use for checks that require human judgment, context-specific knowledge, or are inherently interactive (e.g., "test the admin panel as a non-admin"). Do NOT use for things a grep can catch.

A skill prompt update must include the exact command the agent should run. "Run `rg 'phx-hook' lib | …`" is acceptable. "Be careful with hooks" is not.

**5. AGENTS.md additions** — LAST RESORT ONLY
AGENTS.md is loaded into every agent's context window on every invocation, forever, regardless of whether the rule is relevant. Every line added is a permanent tax on all future work. Add to AGENTS.md only when: (1) no automated check is feasible, AND (2) the rule applies broadly enough that paying the global context cost is justified. If the rule is only relevant to one skill or task type, update that skill's SKILL.md instead.

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

Start at the lowest level where a check is feasible. If the mistake recurs despite a check at the current level, move up.

1. **CI check** — automated, blocks merge, zero agent compliance required
2. **Claude Code hook** — catches the mistake at the moment it happens, before commit
3. **Project-level instruction (AGENTS.md)** — all agents see it, but relies on compliance
4. **Skill prompt instruction** — narrowest reach, relies on agent compliance

For a new category, ask: "Can I write a grep that catches this?" If yes, start at level 1. If the pattern requires code understanding (not grep), start at level 2 or 3. Only fall back to a skill prompt if nothing automated is feasible.

Each `/harness` invocation targets one level per category. The user decides whether to apply.

## Prevention Hierarchy

When proposing harness improvements, prefer solutions higher on this list. Each level is strictly better than the one below it.

1. **Structural impossibility** — Change the architecture so the bug cannot exist. Example: constrain a route param type instead of validating downstream.
2. **Static analysis (Credo rules, boundary-check grep)** — Catch it at compile/lint time by analyzing real code structure. A custom Credo rule that checks "every `field :foo, :string` has a corresponding `validate_length`" is a compile-time guarantee that travels with the codebase.
3. **Integration test against real running system** — Catch it at test time with real behavior, real DB, real endpoint. Valuable when the bug is about runtime interaction (e.g., WebSocket reconnect losing state).
4. **Mocked smoke test** — **Avoid.** A test that mocks the DB, mocks the endpoint, and asserts against a fake response tests the test, not the system. It gives false confidence and breaks on refactors for the wrong reasons.

When evaluating proposals: a custom Credo rule is almost always better than a smoke test. A DB-level `CHECK` constraint is better than an application-level validation test. A route constraint is better than a plug that rejects bad values.

## Scope Limits

- Max **3 finding categories** per invocation. Pick the highest-leverage ones.
- Max **1 new CI step** applied per invocation (propose additional ones if needed).
- Max **1 new file** created per invocation.
- Always surface existing automated checks before creating new ones.
- Only write skill prompt or AGENTS.md updates when no automated check is feasible for the category.

## Rules

- Do NOT fix product code. /harness fixes the system that produces product code.
- Do NOT add findings to BACKLOG.md. Harness improvements are meta-work, not product work.
- Do NOT propose harnesses for one-off findings. The threshold is 2+ occurrences in a round.
- Do NOT propose harnesses for things the SPEC explicitly blesses (e.g., "throwaway views, keep coupled").
- When applying skill prompt updates, make minimal, targeted edits. Do not rewrite the skill.
