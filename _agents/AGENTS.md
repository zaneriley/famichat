# IA coding styleguide
Our code must read like a description of the business domain, not just a series of technical operations. We optimize for the developer reading the code six months from now who needs to understand *why* something is happening, not just *what* is happening.

## 2. Naming Conventions
### 2.1. Semantic Precision
Names must accurately reflect the entity's role, state, or intent within the business domain.
*   **Avoid Mechanism-Coupled Names:** Do not name states after the mechanism used to resolve them.
    *   *Bad:* `passkey_due_at` (couples state to a specific solution).
    *   *Good:* `enrollment_required_since` (describes the account state).
*   **Subject-Verb Agreement:** Function names must accurately reflect their subject.
    *   *Bad:* `can_trust_device?(user)` (asks if a device can be trusted, takes a user).
    *   *Good:* `policy_allows_remembering?(user)` (asks if the user policy allows remembering).

### 2.2. Intent vs. Outcome
Distinguish between what a caller *wants* and what the system *decides*.
*   **Intent Parameters:** Use names indicating a request, not a command, when policy might intervene (e.g., `want_remember?`, `opts[:remember]`).
*   **Outcome Variables:** Use names reflecting the final decision (e.g., `should_remember?`, `is_trusted`).

## 3. Organization & Structure
### 3.1. The Context Boundary
*   **Public vs. Private:** Context modules (e.g., `Famichat.Accounts`) are the *only* public API for their domain.
*   **Cross-Context Communication:** Contexts must not directly query another context's schemas. They must use the other context's public API.
*   **Policy vs. Mechanism:**
    *   **Policy** (rules deciding *if* something can happen) belongs at the top level of the Context function.
    *   **Mechanism** (db writes, hashing) belongs in private helpers or dedicated internal modules.

### 3.2. Function Signatures & Composition
*   **"Mystery Meat" Arguments:** Avoid functions taking multiple bare boolean arguments. Use keyword lists or options maps.
    *   *Bad:* `start_session(user, device_id, ua, ip, true, false)`
    *   *Good:* `start_session(user, device_info, remember_device?: true, force: false)`
*   **Pipeline Clarity:** Use pipelines (`|>`) for data transformations. Use `with` blocks for sequences of operations that might fail. Do not mix them arbitrarily.

## 4. Error Handling & Data Flow
### 4.1. Context API Contracts
*   **Standard Returns:** Public context functions must return standard tagged tuples: `{:ok, result}` or `{:error, reason}`.
*   **Error Reasons:**
    *   Use **atoms** for expected business failures (e.g., `{:error, :insufficient_privileges}`).
    *   Use **Ecto.Changeset** for data validation failures.
*   **Exceptions:** Only raise exceptions for truly exceptional, unrecoverable system states (e.g., missing configuration, database connection loss).

### 4.2. Data Boundaries
*   **Structs In, Structs Out:** Prefer passing full structs to context functions rather than raw IDs when the entity is already known. This reduces redundant DB lookups and clarifies intent.
*   **Schema vs. Structs:** Use Ecto Schemas only when data is persisted to the DB. For complex ephemeral state, use `embedded_schema` or typed structs.

## 5. Explicit State Management
*   **State Transitions:** Significant state changes must be explicit, named operations, not inline side-effects.
    *   *Good:* `{:ok, user} <- enter_enrollment_required_state(user)`
*   **Auditable Side-Effects:** Major side-effects (revoking devices, wiping credentials) must be their own clearly named functions, called explicitly in the transaction.

## 6. Developer Experience (DX)
*   **Greppable Code:** Favor full names over abbreviations. Ensure unique domain concepts have unique names.
*   **Guardrails:** APIs should be hard to misuse. Enforce pre-conditions with guards or pattern matching.
*   **Telemetry:** Business-critical operations must emit telemetry. The event name and metadata are part of that function's public API.

## 7. Documentation
*   **Domain Intent:** `@doc` should explain *what* a function does in business terms first, then technical details.
    *   *Good:* "Starts a new session. Checks organizational policy before honoring the `:remember` option."
*   **Doctests for Pure Logic:** Use doctests for complex, pure functions (parsers, policy checkers) as live documentation.

## 8. LLM Operability and Path Discipline
We treat LLM-driven validation as a first-class engineering workflow. Agent-accessible paths must be clear, deterministic, fast, and aligned with production behavior.

### 8.1. Single Path Principle (Non-Negotiable)
*   **No LLM-Only Runtime Paths:** Do not introduce separate LLM execution paths, alternate logic branches, or agent-only code flows.
*   **Shared Product Surface:** Frontend, API, CLI, and agent workflows must exercise the same domain services and authorization boundaries.
*   **No Divergent Contracts:** Do not maintain parallel payload schemas or behavior for "test mode" vs. normal product mode unless explicitly required by environment safety.

### 8.2. Explicit Anti-Patterns (Prohibited)
*   **No LLM-Specific Mocks/Fixtures/Fallbacks:** Do not add agent-targeted mocks, fixtures, or silent fallback behavior that bypasses real system rules.
*   **No Error Swallowing:** Do not hide failures behind broad rescue/default paths. Fail loud with actionable errors.
*   **No Complexity Inflation:** Reject feature flags, branches, and helper layers whose primary effect is increasing error vectors or cyclomatic complexity without clear product value.

### 8.3. Testability Requirements
*   **Deterministic Playbooks:** Provide documented, repeatable runbooks for key flows (auth, subscribe, send, receive, authorization failures).
*   **Toolable Interfaces:** Prefer stable CLI/API entry points that agents can execute directly for combinatorial state exploration.
*   **Outcome-Focused Assertions:** Tests must validate externally observable outcomes and side effects, not implementation trivia.

### 8.4. Review Standard
Before merging, ask:
1. Does this change preserve one shared production path?
2. Can an agent execute and verify this through documented playbooks?
3. Did we reduce or increase hidden branches, silent behavior, and vector count?

## 9. Rust + LLM Toolchain Feedback Loop
Rust changes must be proposed and validated in a tight loop where compiler, lints, and tests are the source of truth.

### 9.1. Required Context for Rust Tasks
Every Rust task must include:
*   Target crate/workspace and relevant `Cargo.toml` section(s) (edition, features, dependencies).
*   Rust toolchain constraints (MSRV/edition if set by the repo).
*   Exact failing diagnostics or failing test output (not paraphrased).
*   Explicit constraints (for example: no new crates, no `unsafe`, no API breakage).

### 9.2. Oracle Loop (Default)
For Rust work, run this loop before claiming completion:
1. `./run rust:fmt`
2. `./run rust:clippy`
3. `./run rust:test`

Use small diffs and iterate on real tool feedback. Do not jump to large rewrites.
Equivalent fast path: `./run rust:check` (single container exec).
Use `./run rust:lint` when only formatting/lint validation is needed.

### 9.3. Read-Before-Write and Type Awareness
*   Find and reuse existing patterns before adding new abstractions.
*   Prefer type-aware navigation (rust-analyzer/LSP) when available over string matching.
*   Explain ownership/lifetime tradeoffs explicitly when changing borrow behavior.

### 9.4. Safety and Dependency Gates
*   **No new crates without explicit approval** and rationale.
*   **No `unsafe` without explicit approval**.
*   Any `unsafe` introduction must include:
    1. a written safety contract (invariants/assumptions),
    2. focused boundary tests,
    3. Miri validation (`./run rust:miri`) when supported.

### 9.5. Completion Standard for Rust PRs
Rust-related changes are not complete unless:
1. `fmt`, `clippy`, and `test` loop is green.
2. Failure modes are explicit (no silent fallback).
3. Docs/playbooks are updated if commands, contracts, or behavior changed.

## 10. Messaging Invariants and Bug-Bash Gates (Non-Negotiable)

### 10.1 Product Invariants
*   `self` routing is actor-owned only. Clients must not be able to target another user's `self`.
*   Message visibility must be keyed by `(conversation, user, device)` semantics where applicable.
*   Same-user different-tab/device behavior must be explicitly defined and tested.

### 10.2 Required Test Matrix for Messaging Changes
Any PR touching chat/channel/controller/live messaging logic must include or pass:
*   Same user, same device/tab echo behavior.
*   Same user, different tab/device delivery behavior.
*   Different user isolation behavior for `self`.
*   Unauthorized target/spoof attempts (topic-only and conversation-id paths).

### 10.3 No Throwaway-Surface Confidence
*   Manual test LiveViews are probes, not proof.
*   Acceptance requires domain-level characterization tests and channel/controller assertions.

### 10.4 Agent Bug-Bash Deliverables
For messaging PRs, agents must output:
*   Invariant checklist.
*   Scenario matrix executed.
*   Failing/expected visibility table.
*   Exact commands run and results.

### 10.5 Definition of Done for Messaging
A messaging change is not complete unless:
1. Invariants are asserted in tests.
2. Multi-actor/multi-device scenarios are covered.
3. No client-controlled field can violate ownership boundaries.

## 11. Ash Migration Playbook (How/Why/Examples)

### 11.1 Why this exists
We are introducing Ash to improve domain clarity and delivery speed, but this codebase has security-critical auth/chat flows and active MLS hardening work.
The failure mode is not "Ash is bad"; it is partial migration with unclear ownership, drifting contracts, and no fast rollback.
This playbook exists to prevent that.

### 11.2 Core strategy (non-discrete, but disciplined)
1. Keep external contracts stable first.
2. Move ownership behind existing seams second.
3. Cut over gradually with parity evidence.
4. Remove legacy path only after soak and explicit sign-off.

In this repo, the primary seams are:
- `Famichat.Auth` facade: `backend/lib/famichat/auth/auth.ex`
- `Famichat.Auth.Households`: `backend/lib/famichat/auth/households.ex`
- Legacy compatibility facade: `backend/lib/famichat/accounts.ex`

### 11.3 Decision heuristic before any Ash change
Score each proposed change on three axes (0-3 each):
1. Contract risk: chance of changing HTTP/channel/facade behavior.
2. State ownership risk: chance of two writers or split invariants.
3. Reversibility risk: time/complexity to rollback.

Interpretation:
- 0-3 total: normal PR.
- 4-5 total: require explicit rollback test and parity test.
- 6-9 total: require ADR/RFC and staged rollout plan before coding.

### 11.4 What good strangler looks like here
A good strangler change in Famichat does all of this:
1. Keeps facade signatures and tuple contracts stable (`{:ok, _}` / `{:error, _}`).
2. Introduces an internal adapter boundary and swaps implementation behind it.
3. Preserves one writer per invariant.
4. Ships with a feature flag and rollback switch.
5. Includes parity tests between old and new paths.

A bad strangler change:
1. Starts at router/controller/channel and leaks contract differences.
2. Dual-writes indefinitely.
3. Changes contract and ownership in one PR.
4. Has no remove-by date for legacy path.

### 11.5 Gray-zone rule (reality is not discrete)
Cross-boundary edits are allowed when needed, but must satisfy all conditions:
1. The boundary change is mechanical/plumbing, not behavior expansion.
2. External contract is unchanged and pinned by tests.
3. Rollback remains one-step (flag/config).
4. PR description explains why this cross-boundary touch was necessary.

If any one condition is false, stop and request design review.


### 11.7 Concrete example B (good): net-new Ash island
Goal: build Layer-2 logistics features in Ash without destabilizing auth/chat core.

Path:
1. Add a new capability domain only for net-new endpoints.
2. Add new authenticated routes in `backend/lib/famichat_web/router.ex` under `/api/v1/logistics/*`.
3. Reuse existing bearer auth and membership checks via public auth APIs, not internal chat/session rewrites.
4. Use additive-only DB tables/migrations for logistics.
5. Keep auth/chat/channel paths untouched.

Why this works:
- No contract churn in critical existing paths.
- Ash value is proven on isolated scope first.
