# Famichat NOW

**Last updated:** 2026-03-02

Non-evergreen context. For stable design guidance, see [SPEC.md](SPEC.md) and [ADR 012](decisions/012-spa-wasm-client-architecture.md).

---

## One-line state

The front door is built but not walkable end-to-end from a browser. Routing and auth-gating work. Registration is broken at the JS layer and there is no browser-accessible way to bootstrap a new instance. Critical path: fix the P0 passkey bug, build a dev setup page, onboard the spouse.

---

## What just happened (2026-03-02)

- **Front door LiveView built** — login page, invite accept flow, passkey registration step, auth-gated `HomeLive` all exist and mostly render. Not fully working yet (see bugs below).
- **API hardened** — `fetch_session` added to `:api` pipeline (was crashing all auth endpoints), `POST /api/v1/conversations` added, `/health`, `/me`, catch-all 404 all wired.
- **Routing fixed** — `/` → `/en` → `/en/login` for unauthenticated users. `locale_path/2` helper added to `LiveHelpers`; hardcoded `/#{locale}/...` strings eliminated from all LiveViews.
- **Bug bash** — 6 bugs found and fixed via curl-based QA: portfolio content in 404, `dynamic_home_url` compile crash, invalid invite fallthrough to 404, disconnected flash not translated, `ValidateInviteToken` plug swallowing invite errors before LiveView.
- **Critical regression introduced then fixed** — 404 agent deleted `dynamic_home_url/0` from `error_html.ex` without checking 410/500 templates, which still called it. Took app down. Fixed immediately but the lesson is: **commit nothing without curling the endpoint first**.

---

## Actual state of the CUJ (as verified by curl, 2026-03-02)

| URL | Status | Notes |
|-----|--------|-------|
| `/` | ✓ 302 → `/en` | Works |
| `/en` | ✓ 302 → `/en/login` | Works — unauthenticated redirect fixed |
| `/en/login` | ✓ 200 | Renders correctly |
| `/en/login/otp` | ✗ **404** | Route never built — "Sign in another way" link is dead |
| `/en/invites/:token` | ✓ 200 | Renders invite flow — but passkey step crashes (P0 below) |
| `/api/v1/health` | ✓ 200 | Works |
| Admin bootstrap | ✗ **browser-inaccessible** | Requires curl; no UI exists |

---

## Known bugs (blocking L1)

### P0 — Passkey registration crashes, no new user can register

`passkey_register_hook.js` passes the full challenge response object to `decodeCreationOptions` instead of `challengeData.public_key_options`. Accessing `.user.id` on the wrong object throws `TypeError` immediately. The login hook does this correctly; the register hook does not.

**Fix:** One-line change in `passkey_register_hook.js`. Curl and verify before committing.

### P1 — No browser path to bootstrap or register

To register, an admin must first be bootstrapped via `POST /api/v1/setup` (curl only), then issue an invite via `POST /api/v1/auth/invites` (curl, authenticated). There is no UI for either step.

**Fix needed:** A dev-mode setup page (e.g. `/admin/setup` behind basic auth) that bootstraps the instance and issues the first invite link.

### P1 — `/en/login/otp` is a dead link (404)

The OTP login LiveView and route do not exist. The link is rendered on every login page load.

**Fix needed:** Either build the OTP LiveView or remove the link until the route exists.

### P2 — Inviter name never shown on invite page

`invite_live.html.heex` renders `"%{name} invited you"` when `@payload[:inviter_username]` is set. It never is — `Onboarding.accept_invite/1` likely uses a string key or different atom. Always falls back to "You're invited."

### P2 — Three font files 404

`CardinalFruitWeb-Medium-Trial.woff2`, `GT-Flexa-Trial-VF.woff2`, `noto-sans-jp.ttf` all 404 on every page load. Console polluted with font errors, masking real errors.

### P2 — Bootstrap API field names not documented

`POST /api/v1/setup` expects `username` and `family_name`. Using `admin_handle`/`household_name` returns a non-descriptive 400.

---

## Immediate next steps (in order)

### 1. Fix P0 passkey register hook (one line)
`decodeCreationOptions(challengeData)` → `decodeCreationOptions(challengeData.public_key_options)` in `passkey_register_hook.js`. Curl the challenge endpoint and verify the shape before touching the file.

### 2. Build dev setup page (~1–2 hours)
LiveView at `/admin/setup` (behind existing basic auth) that bootstraps the instance and issues the first invite link. Without this, dogfooding requires curl to enter the app at all.

### 3. Fix or remove the OTP link (~30 min)
Remove "Sign in another way" from the login page until the route exists. Or stub it with a "coming soon" page.

### 4. Onboard the spouse
Real-world L1 test. Not a dev task. If anything causes friction, fix it first.

---

## What was completed (no longer in the build queue)

- ✓ Login page (LiveView) — passkey button, loading state, friendly errors
- ✓ Invite accept flow (LiveView) — token consumed, username form, passkey step, success state
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
