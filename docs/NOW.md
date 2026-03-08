# Famichat NOW

**Last updated:** 2026-03-08

Non-evergreen context. For stable design guidance, see [SPEC.md](SPEC.md) and [ADR 012](decisions/012-spa-wasm-client-architecture.md).

---

## One-line state

The browser front door is now mostly walkable for first-family dogfood: setup, invite acceptance, passkey registration, and passkey login all exist in the browser. The next product blocker is no longer the passkey hook or missing setup page. It is that, after first bootstrap, there is still no supported browser flow to create another family on the same deployment.

---

## What just happened (2026-03-08)

- **Passkey registration bug fixed** — `passkey_register_hook.js` now decodes `challengeData.public_key_options`, so invite registration no longer crashes before WebAuthn starts.
- **Browser setup path exists** — `/:locale/setup` is the first-run path. It collects the initial admin name + family name, runs passkey registration, and can issue the first invite link from the browser.
- **Dead OTP affordance removed** — the login page no longer links to `/login/otp`, which still does not exist.
- **Invite UX tightened** — invalid/expired/used invite links stay in LiveView and show friendly guidance instead of falling through to generic route errors. Completed invite reuse now has an explicit sign-in fallback path in the LiveView state machine.
- **Incomplete bootstrap recovery fixed** — `SetupLive` no longer redirects away before its recovery branch can run, and the public front door now routes users back to `/:locale/setup` while the instance is still in the single-user, no-passkey bootstrap limbo (`/` first canonicalizes to `/:locale/`, then `LocaleRedirection` sends that path to setup).
- **Public redirect chain tightened** — `/` now redirects to the canonical `/:locale/` path, and a bootstrapped `/:locale/setup` request now goes straight to `/:locale/login` instead of bouncing through home first.
- **Invite token gate hardened** — `ValidateInviteToken` now rejects structurally invalid tokens before they hit the onboarding lookup.
- **Malformed invite 404 fixed** — structurally invalid invite tokens now render a standalone 404 page instead of nesting a full-document error template inside the app root layout.
- **Front-door coverage expanded** — focused LiveView tests now cover the login passkey button, empty-instance setup form, setup submit → passkey step, valid invite username form, and invite username validation.

---

## Actual state of the CUJ (verified 2026-03-08)

| URL | Status | Notes |
|-----|--------|-------|
| `/` | ✓ 302 → `/en/` | Canonical root redirect |
| `/en` | ✓ 302 → `/en/login` | Works for unauthenticated users |
| `/en/login` | ✓ 200 | Renders passkey sign-in page with no dead OTP link |
| `/en/setup` | ✓ 302 → `/en/login` on a bootstrapped instance | Incomplete-bootstrap recovery is covered by tests; fully bootstrapped flow no longer bounces through home |
| `/en/invites/:token` | ✓ 200 | Invalid/used tokens stay on the invite LiveView instead of falling through to 404 |
| `/api/v1/health` | ✓ 200 | Works |
| Front-door regression tests | ✓ pass | `front_door_live_test.exs` + `session_refresh_test.exs` pass for the touched slice |

---

## Current blockers

### P0 — No post-bootstrap family creation flow

Once any user exists, `Onboarding.bootstrap_admin/2` is closed permanently. The only remaining onboarding path is "join an existing household by invite." That means the first successful bootstrap also closes the only product path that can create a family.

### P0 — Public UX still assumes a single household per deployment

The browser entry points are `/:locale/setup`, `/:locale/login`, and `/:locale/invites/:token`. After bootstrap, the new-person copy still resolves to "sign in" or "ask for an invite." There is no product surface for "start a family on this server."

### P1 — Signed-in app is still first-membership-wins

`HomeLive.load_family_data/1` still picks the first membership and collapses the user into one family context. Even if the DB model can represent multi-family membership, the signed-in browser surface cannot yet.

### P2 — Browser-walkable front door still needs a real browser pass

Route QA and LiveView tests now cover the root/login/setup recovery contract, but a fresh-browser manual walkthrough of bootstrap → passkey → signed-in home was not rerun in this update window.

---

## Immediate next steps (in order)

### 1. Phase 2: add community-admin family creation
Introduce a real post-bootstrap flow to create a family and issue a first-admin setup link. Do not reuse `bootstrap_admin/2`.

### 2. Replace implicit family selection
Add explicit active-family selection/persistence before claiming multi-family support in the signed-in app.

### 3. Run a real browser walkthrough
Fresh instance bootstrap, invite acceptance, and returning sign-in should all be walked in a real browser after the current auth/onboarding fixes.

---

## What was completed (no longer in the build queue)

- ✓ Login page (LiveView) — passkey button, loading state, friendly errors, no dead OTP link
- ✓ Invite accept flow (LiveView) — token consumed, username form, passkey step, success state, friendly invalid/used states
- ✓ `/:locale/setup` browser bootstrap path — initial admin bootstrap, passkey step, first invite issuance
- ✓ Incomplete bootstrap recovery — `/setup` can resume the passkey step when the instance is in single-user, no-passkey limbo
- ✓ Root/setup route cleanup — `/` is canonicalized to `/:locale/`, and bootstrapped `/setup` now goes straight to login
- ✓ Structural invite token validation — malformed tokens are rejected in the plug before lookup
- ✓ `HomeLive` requires real auth (hardcoded test users removed)
- ✓ `POST /api/v1/conversations` — idempotent, auto-called on registration
- ✓ `locale_path/2` — DRY locale-prefixed navigation throughout LiveViews
- ✓ Unauthenticated `/en` redirects to `/en/login`
- ✓ Invalid invite tokens show `:invalid` step (not generic 404)

---

## What NOT to build now

- **OTP email delivery** — infra not configured; skip for L1
- **Full WASM E2EE (Path C)** — L3 work
- **Key package endpoints, Welcome routing, multi-device join** — L3 gate items
- **Photo sharing, message threads, reactions** — deferrable per SPEC
- **Design system, LiveView abstractions** — throwaway views, don't invest
- **QR pairing UI** — invite link is sufficient for 2-person L1
- **Push notifications** — L3 scope

---

## Key decisions locked

| Decision | Details |
|---|---|
| E2EE path | Path C: Svelte SPA + OpenMLS WASM in Web Worker; spike passed GO |
| Frontend model | Full SPA — ADR 012 |
| LiveView scope | Auth, onboarding, admin only — tightly coupled, explicitly deletable |
| NIF fate | Keep during L0/L1; remove at L3 gate |
| Mobile | Capacitor 7 at L3; `ASWebAuthenticationSession` for passkeys |
| Security stance | Server decrypts during L0/L1; Path C before L3 |

---

## Known gaps — blocking L3

- Key package table + distribution endpoints not built
- No Welcome message routing for offline devices
- `/app/*` SPA catch-all route not wired
- CSP not updated for WASM Web Worker (`worker-src 'self' blob:`)
- `device_id` → MLS leaf index mapping gap (blocks revoke → MLS removal)
- S7 + M3 WASM spike criteria pending physical iOS device

## Known gaps — pre-existing, not blocking L1

- 66 pre-existing test failures in lifecycle, channel, MLS modules
- `WEBAUTHN_ORIGIN`, `WEBAUTHN_RP_ID`, `WEBAUTHN_RP_NAME` not configured for production
- `GET /api/v1/devices` endpoint not built
