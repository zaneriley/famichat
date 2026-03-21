# Famichat NOW

**Last updated:** 2026-03-21

Non-evergreen context. For stable design guidance, see [SPEC.md](SPEC.md) and [ADR 012](decisions/012-spa-wasm-client-architecture.md). For completed work, see [BACKLOG-ARCHIVE.md](BACKLOG-ARCHIVE.md). For resolved decisions, see [DECISIONS.md](DECISIONS.md).

---

## One-line state

L1 dogfood is ready to deploy. All 6 original P0 blockers from the 2026-03-16 browser walkthrough are resolved (see [BACKLOG-ARCHIVE.md](BACKLOG-ARCHIVE.md)). Next step: homelab deploy + 2-week observation.

---

## Current blockers

**L1 LiveView dogfood: no blockers remaining.**

All 6 P0 issues from 2026-03-16 are archived:
- Admin role check (76776e4)
- Session-before-passkey auth bypass (76776e4)
- Token invalidation (90b0d5b)
- Admin controls visibility (76776e4)
- Username validate_length (76776e4)
- Invite gen crash from setup (76776e4)

**P1 context (not blocking L1):**

- `HomeLive.load_family_data/1` picks first membership — irrelevant for L1 (one family) but blocks multi-family
- Message plane substrate exists (message_seq, cursors, summaries) but unread count math, `Idempotency-Key`, and `pending_welcomes` not wired

**Note on BACKLOG.md P0 items:** The 14 P0-dogfood items currently in BACKLOG.md are all L2 SPA infrastructure (static_paths, CSP, SpaController, Docker context, etc.). They do not block L1 LiveView dogfood. "P0-dogfood" means "blocks SPA dogfood," not "blocks handing the LiveView URL to family."

---

## L1 dogfood gate status

L1 target: 2-person dogfood (operator + spouse), single family, text messaging only.

| Gate | Status | Notes |
|---|---|---|
| Operator bootstraps instance | PASS | Setup → passkey → auto-auth → invite gen all working (76776e4) |
| Operator invites spouse | PASS | Token invalidation fixed (90b0d5b); auth bypass fixed (76776e4) |
| Spouse completes onboarding | PASS | Session gated behind passkey completion (76776e4) |
| Both users can exchange messages | PASS | Channel join, send, receive, browser notifications |
| Japanese locale works end-to-end | PASS | Locale persisted to DB, translations complete |
| Instance deploys with env vars only | PASS | .env.production.example, runtime.exs guards |
| P1 confidence items resolved | PASS | Reapers, rate limits, passkey UX escalation (1b02ab3) |
| Deployment target chosen | PASS | Homelab + Docker Compose + Cloudflare Tunnel |

---

## Foundation sprint progress (2026-03-20 — ongoing)

Goal: increase velocity and minimize bugs before SPA implementation.

### Track A: CI — Make the Safety Net Real

| Item | Status | Notes |
|---|---|---|
| A0: `./run` native fallback + thin CI | Done | `459bd9c` — `_dc` auto-detects Docker vs native; `lint.yml` is one `./run ci:lint` call |
| A1: `mix compile --warnings-as-errors` | Not started | Pre-existing warning in `community_admin_live.ex:200` (ungrouped `handle_event/3`) blocks gate |
| A2: Fix test failures | Done | `2cc2f3b` tagged 43 known_failure, `99a401e` fixed 38 of those. Baseline: 660 tests, 0 failures, 5 known_failure remaining |
| A3: `ci-test.yml` workflow | Done | `459bd9c` — ExUnit + Rust tests + known_failure ceiling check |
| A4: Sobelow in `ci:lint` | Not started | ~30 min; `.sobelow-conf` exists, needs router path fix |

### Track B: SPA Plumbing

| Item | Status | Notes |
|---|---|---|
| Phase 1: Build infra (7 items) | Done | `51934c8` — Cargo workspace, static_paths, gzip, HelloController removal, 500 page, Dockerfile, .gitignore |
| Phase 1 follow-up | Done | `750b380` — Credo prod guard, CI cache paths, stale Cargo.lock removal, infra/.gitignore |
| Phase 2: SpaCSPHeader plug | Not started | |
| Phase 2: ApiAuth plug | Not started | Needs CSRF decision (recommendation: SameSite=Lax sufficient for L2) |
| Phase 2: `:spa` + `:spa_api` pipelines | Not started | Depends on SpaCSPHeader + ApiAuth |
| Phase 2: Session cookie `max_age` | Not started | 30 days matches refresh token TTL |
| Phase 2: `channel_token` rename | Not started | Touches `sessions.ex` + `tokens/policy.ex` |

### Track C: Quick Wins

| Item | Status | Notes |
|---|---|---|
| C1: Enable MixEnv Credo check | Done | `3555958` |
| C2: ErrorHTML catch-all investigation | Done | `3555958` — documented: `embed_templates` clauses match before catch-all; working correctly |
| C3: Delete schema_markup.ex | Already done | Pre-sprint (`2c307c8`) |
| C4: Fix NOW.md description | Done | `3555958` |

### Remaining work

1. **A1** — fix `community_admin_live.ex` handle_event grouping, then add `--warnings-as-errors` to CI
2. **A4** — add Sobelow to `ci:lint`
3. **Track B Phase 2** — 5 items (SpaCSPHeader, ApiAuth, pipelines, session max_age, channel_token rename)
4. **Verification** — stub `priv/static/app/index.html`, confirm `/app` serves authenticated HTML with correct CSP

---

## Immediate next steps

1. **Finish foundation sprint remaining items** — A1, A4, Track B Phase 2
2. **Deploy to homelab** — Docker Compose + Cloudflare Tunnel → `https://chat.<domain>`. Detailed steps in `docs/self-hosting/`. WebAuthn vars are runtime config (container restart, no rebuild).
3. **Post-deploy browser walkthrough** — full CUJ against deployed instance
4. **Capture operator friction** — every pain point becomes self-hosting documentation
5. **2-week dogfood observation** — daily use, track UX gaps, notification reliability, session stability
6. **Begin L2 SPA scaffold** — see BACKLOG.md P0 section for SPA infrastructure items (can overlap with observation)

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
- `SpaController` for authenticated boot page not built
- Docker build context is `backend/` — cannot access `frontend/` for SPA build

## Known gaps — pre-existing, not blocking L1

- 5 remaining `known_failure`-tagged tests (down from 67; 38 fixed in `99a401e`, 24 deleted as stale). Baseline: 660 tests, 0 failures, 5 known_failure + 3 pending excluded.
- `mix compile --warnings-as-errors` not yet gating CI (pre-existing warning in `community_admin_live.ex` blocks it).
- Passkey challenge options use `Base.encode64` instead of `Base.url_encode64`. May fail on strict browsers.
- `GET /api/v1/devices` endpoint not built.
- `HomeLive` server-side decryption — transitional, acceptable at L0/L1 only.
- Device pending-state enforcement not implemented.
