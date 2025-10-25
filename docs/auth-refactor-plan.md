# Famichat Auth Refactor Plan

## Overview

This document captures the multi-phase refactor approach for the authentication domain. It preserves the intent, sequencing, and guardrails so the work can be executed incrementally without losing context.

## Track A Status Snapshot

- ✅ Invites, pairing, sessions, passkeys, magic/OTP, and recovery all route through `Famichat.Auth.*`; controllers/plugs/tokens no longer call `Famichat.Accounts.*` directly.
- ✅ `Famichat.Accounts` is now a thin deprecated façade delegating to the Auth contexts; `Accounts.Legacy`, `Accounts.Token`, and `Accounts.RateLimiter` have been removed.
- ✅ `Famichat.Auth.Recovery` owns recovery issuance/redeem, disabling devices/passkeys, and telemetry.
- 🚧 Identity/recovery roadmaps (Phases 5–6) still require new flows/tests as described in the DDD doc.
- 🚧 mix_boundary configuration needs a follow-up pass to whitelist the cross-boundary schema usage.

## Phase 0 — Scaffolding, Boundaries, and Infrastructure (No Behavior Change)

**Status**  
✅ Completed – scaffolding merged with Boundary compiler, facade, and placeholder auth contexts.

**Goal**  
Prepare the codebase so future changes are safe and reversible.

**Scope**

- Create `lib/famichat/auth/{identity,households,onboarding,authenticators,sessions,recovery,infra}/` folders.  
- Introduce infra modules: `Tokens`, `RateLimit`, `Audit`, `Instrumentation`.  
- Add `Famichat.Accounts.Errors` with the unified error enum (typed tuples/atoms).  
- Wire `mix_boundary` to enforce compile-time boundaries; façade is the only friend.  
- Add façade module skeleton (`Famichat.Accounts`) with no behavior changes; just delegates to existing functions.

**Migrations**  
None.

**Feature Flags**

- `:auth_boundary_enforced` (compile-time; CI only) *(deferred – no runtime toggle yet)*.  
- `:auth_error_enums_enabled` (façade starts returning typed errors while old functions also return their current shapes; façade translates) *(deferred)*.

**Tests**

- Boundary tests (a couple of intentionally illegal cross-calls that must fail compilation in CI).  
- Façade conformance: old vs façade outputs equal for current flows (property test on payload passthrough).

**Observability**

- ✅ Canonical telemetry prefix `[:famichat, :auth, <context>, <action>]` adopted across new contexts.  
- ✅ Null-op `Instrumentation.span/3` macro in place (used by Sessions & Accounts) to keep call sites ready for real spans.

**Rollout**  
Ship scaffolding + façade in one PR; no runtime changes.

**Rollback**  
Delete new folders; façade delegates can be removed without touching business code.

---

## Phase 1 — Sessions Extraction and Refresh Rotation Policy (Fix ADR-004)

**Status**  
✅ Completed – `Auth.Sessions` context live with rotation policy, façade delegates, tests passing.

**Goal**  
Move device trust and refresh rotation into `Auth.Sessions`, enforce previous-hash reuse detection, and return typed errors.

**Scope**

- New `Auth.Sessions` context: `device.ex`, `rotation_policy.ex`, `sessions.ex`.  
- Extract `start_session/3`, `refresh_session/2`, `revoke_device/2`, `verify_access/1`, `require_reauth?/3`.  
- Implement `RotationPolicy.verify_and_rotate/2`:
  - Validates current hash.  
  - Rejects reuse of `previous_token_hash` with `:reuse_detected`.  
  - Revokes device on reuse.  
  - Emits `SessionRefreshed` or `RefreshReuseDetected` events.
- Façade provides `Accounts.start_session/3`, `Accounts.refresh_session/2`, etc., returning DTOs + typed errors.

**Migrations**  
None (uses existing `user_devices` columns). If `previous_token_hash` is missing in some rows, set it nullable and handle `nil`.

**Feature Flags**

- `:sessions_v2` (default on in staging; façade calls new API. Old `Accounts.refresh_session/2` remains as a shim behind the façade for safety).

**Tests**

- Property tests (`StreamData`): after _n_ rotations, only last and previous hashes are acceptable; any older token → `:reuse_detected` and device revoked.  
- Unit tests for trust window (`trusted_until`) expiry paths.
- Telemetry harness: verifies success/reuse/invalid events fire once per refresh attempt.

**Observability**

- ✅ Counters emitted via telemetry:  
  - `[:auth_sessions, :refresh, :success]`  
  - `[:auth_sessions, :refresh, :reuse_detected]`  
  - `[:auth_sessions, :refresh, :invalid]`  
- Follow-up: wire dashboards/alerts once metrics backend is configured.

**Rollout**  
Deploy with flag off, run shadow calls in façade (call new path, discard result, log diff). Turn on per pod; watch reuse and error rates.

**Rollback**  
Flip flag off; façade falls back to legacy path.

---

## Phase 2 — Token Ledger: Kinds, Classes, and Backfill (Zero Downtime)

**Goal**  
Normalize token issuance/consumption to typed kinds and remove TTL/config drift while keeping existing tokens valid.

**Scope**

- Implement `Auth.Tokens` with classes:
  - `:ledgered` (DB-backed hashed tokens).  
  - `:signed` (`Phoenix.Token`).  
  - `:device_secret` (refresh on `user_devices`).
- Introduce token kinds: `:invite`, `:pair_qr`, `:pair_admin_code`, `:invite_registration`, `:passkey_reg`, `:passkey_assert`, `:magic_link`, `:otp`, `:recovery`.
- Update issuing code to use `Tokens.issue/3` (dual-write context string + kind during cutover).

**Migrations (Two-Phase)**

- **Phase 2a (Additive):**
  - Add columns `kind`, `subject_id`, `audience`, `expires_at`, `used_at` to `auth_tokens` (concurrent indexes on `kind`, `subject_id`).
- **Phase 2b (Backfill + Enforce):**
  - Backfill `kind` from legacy context values.  
  - Update code to read `kind` or fallback to context.  
  - Once metrics are green, set `kind` NOT NULL and add `CHECK(kind IN (...))`.

**Feature Flags**

- `:token_kinds_read`, `:token_kinds_write` (enable reads first, then writes).

**Tests**

- Migration test that mixed legacy/new rows are readable.  
- Unit tests for `Tokens.issue/3` ensuring TTL, audience, and kind mapping are constant-time and consistent.

**Observability**

- Metric: tokens issued by kind (present) + telemetry for subject-id presence/missing.
- Migration job will log counts if ever needed; current greenfield instances have no legacy rows.

**Progress Notes**

- ✅ Columns `kind`, `audience`, `subject_id` added with indexes and populated on issuance.  
- ✅ Database now enforces `kind`/`audience` NOT NULL + `CHECK(kind IN …)` and unique index on `(kind, token_hash)`.  
- ✅ Ledger issuance emits telemetry when subject metadata is missing (captures regressions early).  
- ☐ (Future) Historical backfill only needed if pre-Phase‑2 tokens exist.

**Rollout**  
Enable reads → backfill → enable writes → enforce NOT NULL.

**Rollback**  
Reads still support context; disable writes to `kind`.

---

## Phase 3 — Passkeys V2: Single WebAuthn Challenge Builder with Opaque Handle

**Status**  
✅ Completed – `Famichat.Auth.Passkeys` now issues/consumes WebAuthn challenges and responses carry `public_key_options` plus an opaque `challenge_handle`.

**Goal**  
Eliminate legacy `{challenge, challenge_token}` shape and duplication; return WebAuthn-shaped options and a signed opaque handle.

**Scope**

- Create `Famichat.Auth.Passkeys` with:
  - `issue_registration_challenge/2` and `issue_assertion_challenge/2` → `%{"public_key_options" => options, challenge_handle, expires_at}`.  
  - `fetch_*` helpers plus `consume_challenge/1` backed by `Famichat.Auth.Passkeys.Challenge` and the `webauthn_challenges` table.
- Update passkey flows in `Accounts.Legacy` to require handles (legacy token fallback removed) and share finalization helpers.
- Extend controller coverage to assert the new handle + `publicKey` payload.

**Migrations**  
Create `webauthn_challenges` table (`id`, `type`, `user_id`, `challenge`, `expires_at`, `consumed_at`).

**Feature Flags**

- None

**Tests**

- Handle verification (invalid/malformed/expired) returns `:invalid_challenge` uniformly.  
- Attestation path checks `user_id` consistency and consumes the challenge.  
- Assertion path updates `sign_count` monotonicity and consumes the challenge.

**Observability**

- Metrics: `auth_passkeys.challenge.issued.{registration|assertion}`, `.consumed`, `.invalid`.  
- Alert on high invalid rate (possible replay or client desync).

**Rollout**

- Deploy alongside the `webauthn_challenges` migration; clients must echo `challenge_handle` when responding.

**Rollback**  
Re-introducing `{challenge, challenge_token}` would require reverting this phase.

---

## Phase 4 — Onboarding Extraction (Invites + Pairing) and Households Seam

**Goal**  
Move invitation lifecycle into `Auth.Onboarding` and ensure it composes with `Households` (admin role enforcement) and `Identity` without coupling.

**Scope**

- Onboarding context: `issue_invite/3`, `accept_invite/1`, `issue_pairing/1`, `redeem_pairing/1`, `complete_registration/2`.  
- Households context: expose `add_member/3`, `member_role/2`; no change to schema.  
- Façade flows: `Accounts.onboard_via_invite(invite_token, user_attrs)` returns `%{user_id, registration_challenge, …}` using Passkeys façade.

**Migrations**  
None (reuses `auth_tokens` and existing family/membership tables).

**Feature Flags**

- `:onboarding_v2` (façade calls new context).

**Tests**

- Admin-only invite issuance enforced at Households.  
- Pairing QR/admin code issuance/consumption idempotency.  
- Invite acceptance produces invite-registration claims that expire correctly.

**Observability**

- Metrics per step: `invite.issue|accept|complete`, `pairing.issue|redeem`.  
- Distributed trace across onboarding steps (transactional `Ecto.Multi` spans).

**Rollout**

- Cut over façade to Onboarding with dual instrumentation (old vs new metrics compared).  
- Delete direct invite functions from the monolith after burn-in.

**Rollback**  
Façade can fall back to legacy functions (kept for one release branch).

---

## Phase 5 — Recovery V2: Scoped Containment + Per-Admin Audit

**Goal**  
Stop “nuke all” by default, add scoped blast radius, and make actions auditable by (admin, target, family).

**Scope**

- Recovery context:
  - `issue_recovery(admin_id, user_id, scope \\ :target_user)`.  
  - `redeem_recovery(token)` orchestrates via contracts only:
    - `Sessions.revoke_device/2` | `revoke_all_for_user/1` | `revoke_all_for_household/3`.  
    - `Passkeys.disable_all_for_user/1`.  
  - `Identity.mark_enrollment_required/1` after containment.
- `Audit.record/…` called for both issue and redeem with scope and `family_id`.

**Migrations**  
`auth_audit_logs` table (`event`, `actor_id`, `subject_id`, `family_id`, `context`, `inserted_at`).

**Feature Flags**

- `:recovery_scopes_v1` (enforce scopes; default to `:target_user`).  
- `:recovery_global_allowed` (protects the `:global`/no-family path).

**Tests**

- Authorization: `:household_user` requires shared family admin; failing cases return `{:forbidden, :not_in_household}`.  
- Audit: one row per affected family; `family_id: nil` requires `:recovery_global_allowed`.

**Observability**

- Metrics: counts per scope; alert if `:global` events occur without the flag.  
- Weekly audit review: job that asserts no “global without flag”.

**Rollout**

- Defaults to `:target_user`.  
- Turn on household scope in environments with trusted admin membership data.

**Rollback**  
Disable scopes flag; façade falls back to previous behavior (not recommended but available).

---

## Phase 6 — Identity Hardening and Attribute Gating (Remove `atomize_keys/1`)

**Goal**  
Prevent silent data loss when new user attributes are added; move validation to the schema boundary.

**Scope**

- `Identity.User.changeset/2`:
  - Explicit `cast/4` with allowed keys including future ones (locale, badge, etc.).  
  - `validate_no_extra/2` helper that rejects unknown keys with a single error message.
- Remove `atomize_keys/1` and any permissive mappers; façade passes maps to Identity unchanged.

**Migrations**  
Add new columns if needed (locale, badge) with safe defaults.

**Feature Flags**

- `:identity_strict_attrs` (treat unknown keys as errors instead of dropping).

**Tests**

- Ensure extra keys fail with `{:validation_failed, changeset}` and the error message is developer-friendly.  
- Regression test: known attributes still pass.

**Observability**

- Metric: `auth_identity.attrs.rejected_unknown_key`.  
- Log the offending keys for the first _N_ occurrences to assist client teams.

**Rollout**  
Enable strict mode in staging first; fix clients; then enable in prod.

**Rollback**  
Disable the strict flag (temporarily), but keep schema changes.

---

## Phase 7 — Rates and Telemetry Unification

**Goal**  
Eliminate literal bucket names and mismatched telemetry; standardize across contexts.

**Scope**

- `RateLimit` exposes enum buckets and specs; replace all ad-hoc calls.  
- Ensure every public command emits a consistent telemetry span with `<context>, <action>` names.

**Migrations**  
None.

**Feature Flags**

- `:throttle_enums` (log a warning if a literal bucket is still used anywhere).

**Tests**

- Contract test that all exported functions call `RateLimit.check/2` at least once when appropriate (compile-time AST check or macro hook).

**Observability**

- One dashboard per context with success/error/ratelimited charts.

**Rollout**  
Low risk; commit and monitor dashboards.

**Rollback**  
Not needed.

---

## Phase 8 — Remove Legacy Shapes and Dead Paths (Consolidation)

**Goal**  
Finish the refactor: kill dual outputs, delete monolithic functions, and make boundaries required.

**Scope**

- Delete legacy `{challenge, challenge_token}` returns; require `publicKey + challenge_handle`.  
- Remove legacy invite/session/recovery functions from the old monolith.  
- Enforce `mix_boundary` in CI as required (no opt-out).  
- Update docs and the façade’s `@moduledoc` with final DTOs and error enums.

**Migrations**

- Optional: drop legacy `auth_tokens.context` if no longer used (or keep for historical rows).  
- Add constraints/unique indexes you postponed earlier.

**Feature Flags**  
Delete all flags introduced in prior phases after cutover.

**Tests**

- Contract tests pin final façade shapes.  
- Delete compatibility tests.

**Observability**  
Remove dual-path metrics; keep the standardized ones.

**Rollout**

- Announce cut date to client teams; deploy; verify no calls to legacy shapes appear in logs.  
- Purge dead code.

**Rollback**

- Re-introduce a lightweight compatibility shim in the façade if a late client needs it (keep the code in a git tag).

---

## Parallelizable Tracks

- Phase 0, 2a (additive token columns), and 7 can proceed in parallel.  
- Phase 1 (sessions) should land before Phase 3 (authenticators) and Phase 5 (recovery) because both depend on clean session contracts.  
- Phase 4 (onboarding) can start after Phase 0; it only needs Households wrapper and token kinds from Phase 2a (reads).  
- Phase 6 (identity strict) can start anytime but should flip the flag after onboarding forms are confirmed.

---

## Definition of Done Per Phase

- Code merged behind flags with compile-time boundaries enforced.  
- Migrations applied with backfill (when applicable) and validated counts.  
- Façade returns typed errors and documented DTOs; clients unaffected unless the phase is explicitly about a return shape.  
- Dashboards and alerts exist and are green for 48h after enablement.  
- Rollback plan validated (we actually flip the flag off once in staging to confirm reversibility).  
- Documentation updated (`/docs/auth/` with context APIs, events, and errors).

---

## Ownership and Review Model

- One context owner per bounded context; owners approve all changes touching that context.  
- A single façade owner for `Famichat.Accounts` to prevent re-introducing cross-talk.  
- Security reviews mandatory for Phases 1, 3, and 5.  
- Ops owns dashboards/alerts and signs off before flags go on in prod.
