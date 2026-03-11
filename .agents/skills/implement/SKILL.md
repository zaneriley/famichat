---
name: implement
description: Orchestrate multi-phase implementation with code review and test review gates. Use when the user says to spawn agents, implement in background, or build with review.
argument-hint: "[optional phase filter, e.g. 'phase 2 only']"
---

# Implement with Review Gates

You are orchestrating a multi-phase implementation workflow. The plan is already in the conversation context — the user has discussed and approved it before invoking this skill.

## Protocol

For each phase of work:

1. **Implement** — spawn agents to do the work
2. **Code review gate** — spawn 3 review agents on the touched files
3. **Fix** — address review findings
4. **Test review gate** — spawn 3 review agents on the test files
5. **Fix** — address test review findings
6. **Advance** — move to the next phase

If `$ARGUMENTS` specifies a phase filter (e.g., "phase 2 only"), skip to that phase.

---

## Step 1: Understand the work

Before spawning anything:
- Re-read the plan from conversation context. Identify the phases and their dependencies.
- Use `TaskCreate` to create a task for each phase. Set dependencies with `addBlockedBy` where phases depend on each other.
- Identify which files each phase will touch. This determines how to split implementation agents.

## Step 2: Implement (per phase)

Split the phase into independent work units. Spawn one Task agent per unit, running in parallel where there are no file conflicts.

Each implementation agent prompt MUST include:
- The specific files to create or modify
- The acceptance criteria (what "done" looks like)
- The canonical docs to read before writing code: `docs/ia-lexicon.md` and `docs/ia-boundary-guardrails.md`
- Instruction to report: files touched, what changed, any open questions

### Before declaring a phase done

Each implementation agent MUST run these checks and fix any issues:

1. `cd backend && mix compile --warnings-as-errors` — zero warnings
2. `cd backend && ./run docs:boundary-check` — zero boundary violations
3. If the phase touches auth or onboarding, verify naming against `docs/ia-lexicon.md`
4. If the phase creates or modifies a LiveView, verify that all assign state survives WebSocket reconnect. State stored only in assigns is lost on reconnect — use session storage, URL params, or database-backed state for anything that must survive disconnection.
5. Run relevant tests: `cd backend && mix test <paths to touched test files>`
6. If the phase adds, removes, or renames any `System.get_env` / `System.fetch_env!` call in `runtime.exs`, verify the variable is documented in `.env.production.example` with its generation command, default value, and whether it's required or optional. Run `cd backend && ./run config:env-sync` if it exists.
7. If the phase changes any branding-visible value (app name, display name, PWA manifest), verify consistency across: `config/config.exs` (`:app_name`), `assets/static/site.webmanifest`, `.env.production.example` (`WEBAUTHN_RP_NAME`), and `lib/famichat_web/app_name.ex`.

**Agent type:** `general-purpose`

After all implementation agents complete, run `mix compile --warnings-as-errors` and the relevant test suite in the main thread to confirm the work integrates cleanly.

## Step 3: Code review gate

Identify all files touched in this phase (via `git diff --name-only` against the pre-phase state, or from the implementation agents' reports).

Spawn **3 review agents in parallel**, each with a distinct lens. Each agent receives the list of touched files and reads them directly.

### Reviewer 1: Performance
```
Review these files for performance issues:
[file list]

Look for:
- Unnecessary re-renders, missing memoization, unstable references
- O(n^2) or worse algorithms, repeated expensive operations
- Large objects copied when a reference would suffice
- Unbounded caches or listeners that leak

Do NOT flag:
- Micro-optimizations that don't matter at realistic scale
- Pre-existing issues in untouched code

Write findings to: .tmp/[phase-name]/CODE-REVIEW-PERFORMANCE.md
Rate each finding: must-fix | should-fix | optional
```

### Reviewer 2: Complexity and readability
```
Review these files for cyclomatic complexity and readability:
[file list]

Look for:
- Functions longer than ~40 lines or deeply nested
- Dead code, unused exports, vestigial types
- Confusing naming, missing JSDoc on non-obvious APIs
- Duplicated logic that should be extracted

Do NOT flag:
- Style preferences (the formatter handles that)
- Pre-existing complexity in untouched code

Write findings to: .tmp/[phase-name]/CODE-REVIEW-COMPLEXITY.md
Rate each finding: must-fix | should-fix | optional
```

### Reviewer 3: Codebase consistency
```
Review these files for consistency with the rest of the codebase:
[file list]

Read CLAUDE.md and the memory files for project conventions. Then check:
- Does this follow existing patterns (naming, file structure, imports)?
- Are new abstractions consistent with neighboring code?
- Does error handling match the project's style?
- Are there convention violations (e.g., inline styles, wrong token names)?

Do NOT flag:
- Suggestions to improve conventions project-wide (out of scope)
- Pre-existing inconsistencies in untouched code

Write findings to: .tmp/[phase-name]/CODE-REVIEW-CONSISTENCY.md
Rate each finding: must-fix | should-fix | optional
```

**Agent type for all reviewers:** `claude_critic`

### Synthesize and fix

After all 3 reviewers complete:
1. Read all 3 review files
2. Collect all `must-fix` findings — these block advancement
3. Collect `should-fix` findings — fix these unless ambiguous
4. For ambiguous findings (could be pre-existing, debatable tradeoff), ask the user
5. Spawn agents to fix the must-fix and should-fix items
6. Re-run type check and tests to confirm fixes don't regress

## Step 4: Test review gate

Identify all test files touched or created in this phase.

If no test files were touched, skip this gate.

Spawn **3 review agents in parallel:**

### Reviewer 1: Brittleness
```
Review these test files for brittleness:
[test file list]

Look for:
- Tests coupled to implementation details (private methods, internal state)
- Snapshot tests that break on any formatting change
- Tests that depend on execution order or timing
- Assertions on exact error messages or log output
- Tests that will break if the component is refactored without changing behavior

Write findings to: .tmp/[phase-name]/TEST-REVIEW-BRITTLENESS.md
Rate each finding: must-fix | should-fix | optional
```

### Reviewer 2: Mock minimization
```
Review these test files for excessive mocking:
[test file list]

Look for:
- Mocks that could be replaced with real implementations (e.g., in-memory stores)
- Mocked modules where the real module is lightweight and deterministic
- Mock setups that duplicate the implementation they're testing
- Tests where the mock IS the test (asserting mock was called, not behavior)

Do NOT flag:
- Network/API mocks (these are appropriate)
- Mocks for expensive resources (workers, databases)

Write findings to: .tmp/[phase-name]/TEST-REVIEW-MOCKS.md
Rate each finding: must-fix | should-fix | optional
```

### Reviewer 3: Clarity
```
Review these test files for clarity:
[test file list]

Look for:
- Test names that don't describe the expected behavior
- Arrange/Act/Assert sections that are hard to distinguish
- Helper functions that obscure what's being tested
- Missing edge cases that the test name implies are covered
- Tests that test multiple behaviors in one case

Write findings to: .tmp/[phase-name]/TEST-REVIEW-CLARITY.md
Rate each finding: must-fix | should-fix | optional
```

**Agent type for all reviewers:** `claude_critic`

### Synthesize and fix

Same process as code review: read findings, fix must-fix and should-fix, ask on ambiguity, confirm tests still pass.

## Step 5: Advance

After both gates pass:
1. Mark the phase task as `completed`
2. Report a summary to the user: what was implemented, what the reviewers found, what was fixed
3. Check `TaskList` for the next unblocked phase
4. If there's a next phase, go back to Step 2
5. If all phases are done, report the final summary

---

## Rules

- **Parallelism:** Always spawn independent agents in the same message (parallel tool calls). Never serialize work that can run concurrently.
- **File conflicts:** If two implementation agents would touch the same file, run them sequentially, not in parallel.
- **Review scope:** Reviewers only examine files touched in the current phase, not the entire codebase.
- **Pre-existing issues:** Reviewers must not flag problems in code that wasn't modified. If a reviewer flags something that predates this phase, discard the finding.
- **Test runner:** Use `mix test [relevant paths]` for tests, `mix compile --warnings-as-errors` for type checking.
- **Report files:** Write review reports to `.tmp/[phase-name]/` where `[phase-name]` is a slug of the current phase (e.g., `.tmp/phase-2-store-perf/`).
- **No gold-plating:** Fix what reviewers flag. Do not refactor, improve, or extend beyond what the plan and reviews call for.
