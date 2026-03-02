# Famichat NOW

**Last updated:** 2026-03-01

Non-evergreen context. For stable design guidance, see [SPEC.md](SPEC.md) and [ADR 012](decisions/012-spa-wasm-client-architecture.md).

---

## One-line state

Architecture is locked. WASM spike passed. No real user-facing UI exists yet. Critical path is: build the front door (LiveView auth + invite flow), onboard the spouse, then build the SPA while the app is in daily use.

---

## What just happened

- **Full SPA architecture decided and documented** — ADR 012 supersedes ADR 011 (archived). Svelte 5 + SvelteKit 2 SPA for message surfaces; LiveView for auth/onboarding/admin; Capacitor for mobile at L3.
- **WASM spike passed GO** (10/12 criteria, 2026-03-01):
  - S1–S6, S8, M1, M2, M4 all PASS in headless Chromium
  - Warm-path P95 = 1.90ms (gate 50ms — 26× under); bundle 481.8 kB gzip (gate 500 kB)
  - S7 + M3 pending physical iOS device — must confirm before L3
  - Spike artifacts: `spikes/openmls-wasm/`, results at `.tmp/2026-03-01-SPA/spike/spike-results-final.md`
- **Codebase audit completed** — the backend auth API exists and has tests, but almost nothing has been validated end-to-end with real infrastructure. No user-facing UI exists at all. See below.

---

## Actual state of the codebase

### What genuinely works
- Phoenix Channel messaging — <200ms latency, MLS crypto, PubSub, DB persistence all confirmed
- MLS NIF — fully hardened (Track A), 17/17 Rust tests pass
- Auth API — passkey register/assert (Wax), session refresh, device revocation — code exists and has unit tests

### What exists in code but is NOT validated end-to-end
- **Magic link / OTP auth** — no email client is configured; magic links cannot actually be sent. Backend logic exists, real delivery does not.
- **Invite flow** — three-step pipeline exists and has HTTP tests; no browser page consumes it; never been run with a real user
- **Passkey flows** — WebAuthn backend is correct; no browser JS calls `navigator.credentials.create()` or `.get()` anywhere

### What does not exist at all
- Any real user-facing UI (login page, registration, invite acceptance, messaging UI with real auth)
- `POST /api/v1/conversations` — conversations can only be created via seeds/test context
- `/app/*` catch-all route and static file serving for the SPA
- CSP updated for WASM Web Worker (`worker-src 'self' blob:`)
- Key package endpoints (deferred — post-spike, pre-L3)
- `GET /api/v1/devices` (own device list)

### The only end-to-end path that works
`HomeLive` spike harness → hardcoded test users ("zane" / "wife") → Phoenix Channel → MLS encrypt/decrypt → PostgreSQL. This bypasses all real auth. It is throwaway.

---

## Immediate next steps (in order)

### 1. Build the front door (LiveView — throwaway, ~3 days)

These are intentionally throwaway per SPEC — write them tightly coupled, no abstraction, no design investment. They exist to get a real second user into the app for L1 validation.

**a. Passkey login page**
- `navigator.credentials.get()` calling `/api/v1/auth/passkeys/assertion-challenge` → `/api/v1/auth/passkeys/assert`
- OTP fallback (note: magic link requires email infra — skip for now, OTP only)
- Store access token in memory, refresh token in `sessionStorage` for now (upgrade before L2)

**b. Passkey registration page**
- `navigator.credentials.create()` calling challenge → register endpoints
- Wire to invite token from URL

**c. Invite accept flow**
- Consume invite token from URL → username form → hand off to passkey registration
- Route: `/invites/:token`

**d. Auth-gated message view**
- Refactor `HomeLive` to require real session (not hardcoded users)
- Minimal: conversation list + message thread + send box
- No design investment — this will be deleted when the SPA ships

### 2. Add `POST /api/v1/conversations` (~half day)
Needed to create a new 1:1 conversation from the UI. Conversations currently only exist via seeds.

### 3. Onboard the spouse
This is the L1 gate. Not a dev task — a real-world test. If the invite + passkey registration flow causes friction, fix it before declaring L1.

### 4. Build the SPA scaffold (while app is in daily use)
After L1 is validated with the throwaway LiveView:
- Create `frontend/` directory per ADR 012 §12
- Wire `/app/*` catch-all route + `:spa` pipeline in router
- Update CSP plug for `worker-src 'self' blob:` + `'wasm-unsafe-eval'`
- Build Svelte conversation list + message view with real Phoenix Channel connection
- Swap LiveView message view for SPA; delete throwaway

---

## What NOT to build now

- Full WASM E2EE (Path C) — L3 work, not L1. Server-side decryption is acceptable while you are the only operator.
- Key package endpoints, Welcome routing, multi-device join — L3 gate items
- Magic link email infrastructure — OTP is sufficient for L1
- Photo sharing, message threads — explicitly deferrable per SPEC
- Design system, shared components, any LiveView abstraction — throwaway views, don't invest
- QR pairing UI — invite link is sufficient for 2-person use
- Push notifications — L3 scope

---

## Key decisions locked

| Decision | Details |
|---|---|
| E2EE path | Path C: Svelte SPA + OpenMLS WASM in Web Worker; spike passed GO |
| Frontend model | Full SPA (not LiveView hybrid) — ADR 012, supersedes old NOW.md |
| LiveView scope | Auth, onboarding, admin only — tightly coupled, explicitly deletable |
| NIF fate | Keep during L0/L1 dogfooding; remove at L3 gate (before other families trust the server) |
| Mobile | Capacitor 7 at L3; `ASWebAuthenticationSession` for passkeys (self-hosting constraint) |
| Security stance | "Impossible, not guarded" — don't hold data you don't need to hold |

---

## Known gaps

**Blocking L1 (no real users until fixed):**
- No login page, no registration page, no invite UI
- `POST /api/v1/conversations` missing
- Magic link delivery not configured (use OTP only for now)

**Blocking E2EE / L3 gate:**
- Key package table + distribution endpoints not built
- No Welcome message routing for offline devices
- `/app/*` SPA catch-all route not wired
- CSP not updated for WASM Web Worker
- `device_id` → MLS leaf index mapping gap (blocks revoke → MLS removal)
- S7 + M3 spike criteria pending physical iOS device

**Pre-existing, not blocking L1:**
- 66 pre-existing test failures in lifecycle, channel, MLS contract modules
- `WEBAUTHN_ORIGIN`, `WEBAUTHN_RP_ID`, `WEBAUTHN_RP_NAME` env vars not configured for production
