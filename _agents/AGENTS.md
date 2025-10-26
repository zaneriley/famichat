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
