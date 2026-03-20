# Famichat NOW

**Last updated:** 2026-03-20

Non-evergreen context. For stable design guidance, see [SPEC.md](SPEC.md) and [ADR 012](decisions/012-spa-wasm-client-architecture.md). For completed work, see [BACKLOG-ARCHIVE.md](BACKLOG-ARCHIVE.md). For resolved decisions, see [DECISIONS.md](DECISIONS.md).

---

## One-line state

L1 dogfood (2-person, single family, text only) is blocked by 6 P0 security/UX issues found in 2026-03-16 browser walkthrough. Message exchange works. Japanese locale works. Deployment infra is ready.

---

## Current blockers

**6 P0 blockers — must fix before handing URL to family:**

- `/en/admin` has no role check — any authenticated user reaches the full community admin panel
- `invites/complete` sets session cookie before passkey completes — auth bypass; abandoned ceremony = silent login with no passkey
- Invite/setup token not invalidated after `:pending` user creation — token reusable with different username
- "Admin Controls" (Revoke Device, Reset Security State) shown to all users on home page
- Username `validate_length` missing at all entry points — 206-char names accepted and persisted
- LiveView crash on "Generate invite link" in setup post-passkey step — first-run admin cannot issue invite from setup

**P1 context (not blocking L1):**

- `HomeLive.load_family_data/1` picks first membership — irrelevant for L1 (one family) but blocks multi-family
- Message plane substrate exists (message_seq, cursors, summaries) but unread count math, `Idempotency-Key`, and `pending_welcomes` not wired

---

## L1 dogfood gate status

L1 target: 2-person dogfood (operator + spouse), single family, text messaging only.

| Gate | Status | Notes |
|---|---|---|
| Operator bootstraps instance | PARTIAL | Setup → passkey → auto-auth → home works. Invite gen from setup crashes (P0). |
| Operator invites spouse | PARTIAL | Invite gen from home works. Token not invalidated post-user-creation (P0). Auth bypass (P0). |
| Spouse completes onboarding | PARTIAL | Auth bypass: session set before passkey (P0). |
| Both users can exchange messages | PASS | Channel join, send, receive, browser notifications |
| Japanese locale works end-to-end | PASS | Locale persisted to DB, translations complete |
| Instance deploys with env vars only | PASS | .env.production.example, runtime.exs guards |
| P1 confidence items resolved | PASS | Reapers, rate limits, passkey UX escalation (1b02ab3) |
| Deployment target chosen | PASS | Homelab + Docker Compose + Cloudflare Tunnel |

---

## Immediate next steps

1. **Fix 6 P0 blockers** — see BACKLOG.md P0 section
2. **Deploy to homelab** — Docker Compose + Cloudflare Tunnel → `https://chat.<domain>`. Detailed steps in `docs/self-hosting/`. WebAuthn vars are runtime config (container restart, no rebuild).
3. **Post-deploy browser walkthrough** — full CUJ against deployed instance
4. **Capture operator friction** — every pain point becomes self-hosting documentation
5. **2-week dogfood observation** — daily use, track UX gaps, notification reliability, session stability

---

## What NOT to build now

- **OTP email delivery** — infra not configured; skip for L1
- **Full WASM E2EE (Path C)** — L3 work; architecture decided (ADR 012)
- **Key package endpoints, Welcome routing, multi-device join** — L3 gate items
- **Photo sharing, message threads, reactions** — punted; L2+
- **Design system, LiveView abstractions** — throwaway views, don't invest
- **QR pairing UI** — invite link sufficient for 2-person L1
- **Letters** — deferred; validate daily text use first
- **Multi-family context switching** — code exists (FamilyContext); irrelevant for L1
- **Unread counts** — substrate exists; math not wired; L2
- **Browser notifications beyond basic** — current: permission on join, Notification when tab hidden. Sufficient for L1.

---

## Key decisions locked

| Decision | Details |
|---|---|
| E2EE path | Path C: Svelte SPA + OpenMLS WASM in Web Worker; spike passed GO |
| Frontend model | Full SPA — ADR 012 |
| LiveView scope | Auth, onboarding, admin only — tightly coupled, explicitly deletable |
| NIF fate | Transitional gap — keep during L0/L1 only; removal at L3. Do not extend. |
| Mobile | Capacitor 7 at L3; `ASWebAuthenticationSession` for passkeys |
| Security stance | Server decrypts during L0/L1 — **known gap, not target architecture**; Path C required before L3 |
| No server-side previews | SPA maintains local decrypted preview cache |
| Invite TTL | 72 hours per SPEC |
| Deployment | Homelab + Docker Compose + Cloudflare Tunnel |
| Local-first storage | Persistent IndexedDB + AES-256-GCM; instant open; 30d server retention; Dexie.js |
| Recovery model | 12-word BIP-39 phrase at L3; social recovery wishlist for L4+ |
| SPA auth | Cookie-based same-origin; `ApiAuth` plug for Capacitor Bearer fallback |
| SPA toolchain | Svelte 5 + SvelteKit 2 + adapter-static + Vite 8 + pnpm; Comlink; Dexie.js |

---

## Known gaps — blocking L3

- Key package table + distribution endpoints not built
- No Welcome message routing for offline devices
- `/app/*` SPA catch-all route not wired
- CSP not updated for WASM Web Worker (`worker-src 'self' blob:`)
- `device_id` → MLS leaf index mapping gap (blocks revoke → MLS removal)
- S7 + M3 WASM spike criteria pending physical iOS device
- ADR 012 "30-minute idle wrapping-key timeout" conflicts with instant-open decision
- `famichat_messages` IndexedDB schema not built
- Local-first data layer (Dexie.js + Svelte stores) not scaffolded
- `static_paths/0` missing `"app"` entry — SPA assets return 404
- `SpaController` for authenticated boot page not built
- Docker build context is `backend/` — cannot access `frontend/` for SPA build
- Cargo workspace root not created — NIF and WASM profile conflict
- Committed WASM binaries in `backend/infra/mls_wasm/pkg/` — 2.2 MB per clone

## Known gaps — pre-existing, not blocking L1

- 66 pre-existing test failures (stale `household_id` field, hardcoded UUIDs, snapshot shape drift). Separate workstream.
- No CI `mix test` step.
- Passkey challenge options use `Base.encode64` instead of `Base.url_encode64`. May fail on strict browsers.
- `GET /api/v1/devices` endpoint not built.
- `HomeLive` server-side decryption — transitional, acceptable at L0/L1 only.
- Device pending-state enforcement not implemented.
