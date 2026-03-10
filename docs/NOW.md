# Famichat NOW

**Last updated:** 2026-03-10

Non-evergreen context. For stable design guidance, see [SPEC.md](SPEC.md) and [ADR 012](decisions/012-spa-wasm-client-architecture.md).

---

## One-line state

All P0 dogfood blockers closed. P1 confidence items resolved (1b02ab3). Deploying to homelab via Docker Compose + Cloudflare Tunnel. Dogfooding the operator experience — every friction point we hit becomes documentation for future self-hosters.

---

## What just happened (2026-03-10)

- **7 P1 confidence items resolved** (1b02ab3) — TokenReaper (expired token cleanup every 30min), OrphanFamilyReaper (memberless family cleanup every 30min, 1hr buffer, guards for missing conversations FK), rate limit on `reissue_passkey_token/1` (5/5min per user_id, closes last unprotected token-issuing function), passkey error count escalation in LoginLive (3+ failures shows device hint + social recovery guidance), "no read receipts" contextual note in empty conversation state, browser tab title set to family name in no-conversation branch. Japanese translations for all new strings. P1-4 (passkey error feedback) confirmed already working — full hook→LiveView→template error chain wired in auth security fixes. Refresh token TTL decision deferred to L2 (30 days correct for dogfood).
- **Deployment strategy decided** — homelab + Cloudflare Tunnel. Dogfoods the self-hosted operator experience. Captures friction for future operator documentation.
- **All P0 dogfood blockers closed** (dfd6091) — Final 5 P0s implemented + 3-reviewer code review gate: warm empty-state copy (role-differentiated admin vs invitee), consumed-invite recovery (clear copy, conditional sign-in link hidden), locale persistence (on_mount DB load, SessionRefresh restore, RootRedirectController DB check), .env.production.example (ungitignored, WebAuthn moved to runtime.exs with prod raise guards), Japanese translations (22 errors.po entries, 7 fuzzy flags removed, orphaned 404.po deleted). Invite TTL aligned to SPEC: code changed from 7 days to 72 hours, all EN+JA copy updated. P1/P2 hardening: POSTGRES_PASSWORD prod guard, GitHub webhook plug removed (dead code), dead content_* config removed, CSP reads from Application.get_env, CSP port consistency fix, locale CHECK constraint migration, abandoned invite telemetry. Code subtraction: 3 unused functions deleted from live_helpers.ex, unreachable branch deleted from invite_live.ex, rescue added to root redirect locale resolution.
- **P0 next-four implemented + review-gated** — Auto-auth after passkey, browser notifications, HomeLive opens to conversation, conversation_type fix, push_navigate removal, sender_name forwarding, UNIQUE_CONVERSATION_KEY_SALT config. 6 review findings fixed.
- **L1 dogfood ideation implemented** — 12 fixes from 10-agent ideation round. Security: logout revokes device, rate limits tuned. Validation: name minimum 1 char (CJK). Templates: 404/410 content-only. A11y: contrast, text size, skip-to-content. UX: welcome prompt, auto-navigate, self-service demoted. I18n: brand voice fixes, 11 JA translations.

## What just happened (2026-03-09)

- **Onboarding infrastructure committed** (95eb458) — PutRemoteIp (X-Forwarded-For with compile-time CIDR + IPv4-mapped IPv6 normalization), FamilyNewLive (self-service family creation), CommunityAdminLive (admin panel), FamilyContext (multi-family resolution + switching), PendingUserReaper, ValidateFamilySetupToken, SessionController (logout). 8 migrations: message_seq, conversation_summaries, user_read_cursors, backfill, family_setup token kind, invite token audience fix, last_active_family_id. All 3 remaining P0-dogfood items closed.
- **Bug bash completed** — 5-persona automated bug bash (community admin, non-tech family member, grandparent, security tester, Japanese-speaking user) found 19 issues across 4 categories. 11 closed in this round.
- **Router/locale hardened** — `/:locale` no longer swallows API routes; `SetLocale` plug returns early 404 for unsupported locale segments; locale catch-all controller deleted. HSTS wired into `:browser` pipeline. LocaleRedirection now uses 302 (was 301).
- **Security config baseline** — HEEx debug annotations explicitly disabled in prod. CSP `unsafe-eval` removed from prod `script-src` (dev retains it for hot-reload). Server header strip plug added to endpoint. Console.log gated behind `isDev` flag in app.js.
- **String validation convention** — `Famichat.Schema.Validations.validate_string_field/3` shared across all user-facing string fields (family name, username, passkey label, user agent, message content). DB CHECK constraints migration added.
- **Token-gated LiveView reconnect** — `FamilySetupLive` added with `peek_family_setup/1` recovery on WebSocket reconnect (mirrors InviteLive pattern). Blank family name no longer collides with default — "My Family" removed as server-side default. `:retryable` → `:recoverable` across all auth LiveViews.
- **Harness tests added** — Route table ordering assertions, security baseline integration tests (CSP, HSTS, HEEx annotations, server header), token reconnect recovery tests (tagged `:skip` pending full implementation).
- **Code quality pass** — Review agents found 27 issues; 7 implemented: log bug fix in LocaleRedirection, double `route_info` call eliminated, endpoint logging downgraded to `:debug`, runtime `Application.get_env` replaced with compile-time module attributes, `then/1` anti-pattern replaced, media type validation consolidated, app.js null-safety added.

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
- **`community_id` wired into schema** — users, families, conversations, and audit logs now carry a `community_id` FK. The data model is in place; no multi-family product UX exists yet.

---

## Actual state of the CUJ (verified 2026-03-09)

| URL | Status | Notes |
|-----|--------|-------|
| `/` | ✓ 302 → `/en/` | Canonical root redirect; respects Accept-Language partially via locale infrastructure |
| `/en` | ✓ 302 → `/en/login` | Works for unauthenticated users |
| `/en/login` | ✓ 200 | Renders passkey sign-in page with no dead OTP link |
| `/en/setup` | ✓ 200 | Bootstrap → passkey → invite step all verified (90b0d5b). Bootstrapped instance redirects to login. Incomplete-bootstrap recovery works. Admin IS now auto-authenticated after passkey ceremony via `enrich_session/2`. Invite generation from setup_live crashes (pre-existing; home page invite works). |
| `/en/invites/:token` | ✓ 200 | Invalid/used tokens stay on the invite LiveView instead of falling through to 404 |
| `/en/families/start/:token` | ✓ 200 | Token-gated family setup; reconnect recovery via `peek_family_setup/1` |
| `/api/v1/health` | ✓ 200 | No longer shadowed by `:locale` catch-all |
| `/api/*` | ✓ | Route table assertions prevent locale scope from shadowing API routes |
| Front-door regression tests | ✓ pass | `front_door_live_test.exs` + `session_refresh_test.exs` + security baseline + route table tests pass |

---

## Current blockers

No P0 blockers remain. The following P1 items are tracked in BACKLOG.md but do not block L1 2-person dogfood:

### P1 — Signed-in app is still first-membership-wins

`HomeLive.load_family_data/1` picks the first membership. Irrelevant for L1 (one family) but blocks multi-family use.

### P1 — Message plane gaps

Substrate exists (message_seq, user_read_cursors, conversation_summaries committed). Still missing: unread count math, `Idempotency-Key` header, `pending_welcomes` table. Not blocking L1 text messaging.

---

## L1 dogfood gate status

L1 target: 2-person dogfood (operator + spouse), single family, text messaging only.

| Gate | Status | Notes |
|---|---|---|
| Operator bootstraps instance | PASS | `/setup` → passkey → auto-auth → home (verified in browser) |
| Operator invites spouse | PASS | Invite generation from home, 72h TTL, warm copy |
| Spouse completes onboarding | PASS | Invite → username → passkey → auto-auth → conversation |
| Both users can exchange messages | PASS | Channel join, send, receive, browser notifications |
| Japanese locale works end-to-end | PASS | Locale persisted to DB, 22 errors.po translated, 0 fuzzy flags |
| Instance deploys with env vars only | PASS | .env.production.example, runtime.exs guards raise on missing secrets |
| P1 confidence items resolved | PASS | Reapers, rate limits, passkey UX escalation, receipts note, tab title (1b02ab3) |
| Deployment target chosen | PASS | Homelab + Docker Compose + Cloudflare Tunnel |

Multi-family gates (MLP scope, not L1):

| Gate | Status | Notes |
|---|---|---|
| Multi-family context switch | NOT STARTED | `HomeLive` is first-membership-wins; not needed for L1 |
| Abandoned family setup recovery | NOT STARTED | Edge case; not the primary CUJ |

---

## MLP entry point status

| MLP-required route | Status |
|---|---|
| `/setup` for first-run only | EXISTS — one-shot; permanently closes after first user |
| `/login` for existing members | EXISTS — passkey discoverable flow only; no OTP/magic link fallback |
| `/invites/:token` for joining an existing family | EXISTS — functional |
| `/families/start/:token` for starting a newly created family | EXISTS — committed (95eb458) |
| `/families/new` for self-service family creation | EXISTS — committed (95eb458); rate-limited via PutRemoteIp |

---

## Immediate next steps

### 1. Homelab deployment
Deploy to homelab via Docker Compose + Cloudflare Tunnel. This IS the product experience — we're the first operator.

**Infrastructure**: Homelab machine + Cloudflare Tunnel → `https://chat.<domain>` → `localhost:8001`. TLS terminated at Cloudflare (satisfies WebAuthn secure-context requirement). PostgreSQL in Docker with persistent named volume.

**Steps**:
1. Clone repo to homelab machine
2. Copy `.env.production.example` → `.env`, generate all secrets (`openssl rand -base64 64` for SECRET_KEY_BASE, `openssl rand -base64 32` for the others)
3. Set `WEBAUTHN_ORIGIN`, `WEBAUTHN_RP_ID`, `URL_HOST` to the Cloudflare Tunnel domain
4. `docker compose -f docker-compose.production.yml up -d`
5. Verify health: `curl localhost:8001/up` and `curl localhost:8001/up/databases`
6. Configure Cloudflare Tunnel to point to `localhost:8001`
7. Hit the public URL, complete `/setup` bootstrap

**Critical gotcha**: WebAuthn vars are compile-time in `config.exs`. They must be set in the environment BEFORE `docker compose build` (the Dockerfile runs `mix release` during build). If the image was built with localhost defaults, passkeys will silently fail with origin mismatch.

### 2. Post-deploy browser walkthrough
Run the full CUJ against the deployed instance: operator bootstrap → invite generation → spouse onboarding → message exchange. Catch deploy-specific issues: env var misconfiguration, WebSocket upgrade behind Cloudflare, passkey RP ID matching, CORS.

### 3. Capture operator experience for documentation
Every friction point we hit during deployment becomes documentation for future self-hosters. Track:

**What to capture (write it down as you go)**:
- **Setup friction log** — every moment of confusion, missing documentation, unclear error, or "I had to look at the code to figure this out." This becomes the self-hosting guide.
- **Env var pain points** — which vars were confusing? Which defaults were wrong? Which error messages helped vs. which were cryptic?
- **Cloudflare Tunnel specifics** — any WebSocket issues? Header forwarding? IP resolution behind tunnel?
- **Update workflow** — when we push a code change, what does `git pull && docker compose build && docker compose up -d` actually feel like? How long? Any downtime?
- **Backup/restore** — does `pg_dump` work from inside the container? What's the actual command sequence?
- **What broke** — anything that works in dev but fails in prod (compile-time vs runtime config, missing assets, NIF loading, etc.)

**What this produces**:
- A `docs/self-hosting.md` guide written from real experience, not hypothetical
- Fixes to `.env.production.example` for anything that was unclear
- Fixes to `runtime.exs` error messages for anything that was unhelpful
- Confidence that the Docker Compose path actually works end-to-end

### 4. Dogfood observation period
Use the app daily for real couple messaging. Track:
- Does the app feel like "our space" or like "a product"?
- What's the first thing you wish it did differently?
- Does your spouse ask any questions that reveal missing UX?
- Do browser notifications work reliably? Do they feel intrusive or insufficient?
- Any WebSocket disconnects or session expiry surprises?

---

## What was completed (no longer in the build queue)

- ✓ Login page (LiveView) — passkey button, loading state, friendly errors, no dead OTP link
- ✓ Invite accept flow (LiveView) — token consumed, username form, passkey step, success state, friendly invalid/used states
- ✓ `/:locale/setup` browser bootstrap path — initial admin bootstrap, passkey step, first invite issuance (admin must sign in separately after setup; no auto-session)
- ✓ Incomplete bootstrap recovery — `/setup` can resume the passkey step when the instance is in single-user, no-passkey limbo
- ✓ Root/setup route cleanup — `/` is canonicalized to `/:locale/`, and bootstrapped `/setup` now goes straight to login
- ✓ Structural invite token validation — malformed tokens are rejected in the plug before lookup
- ✓ `HomeLive` requires real auth (hardcoded test users removed)
- ✓ `POST /api/v1/conversations` — idempotent, auto-called on registration
- ✓ `locale_path/2` — DRY locale-prefixed navigation throughout LiveViews
- ✓ Unauthenticated `/en` redirects to `/en/login`
- ✓ Invalid invite tokens show `:invalid` step (not generic 404)
- ✓ `community_id` column wired into users, families, conversations, and audit logs via migration
- ✓ Router locale constraint — `SetLocale` plug rejects unsupported locales; API routes no longer shadowed
- ✓ Security baseline — HSTS, enforcing CSP (no `unsafe-eval` in prod), HEEx annotations disabled, server header stripped, console.log dev-gated
- ✓ String validation convention — `validate_string_field/3` shared helper + DB CHECK constraints for all user-facing string fields
- ✓ Token-gated reconnect recovery — `FamilySetupLive` with `peek_family_setup/1`; blank family name default removed
- ✓ Error tag normalization — `:retryable` → `:recoverable` across SetupLive, FamilySetupLive
- ✓ Harness tests — route table ordering, security config baseline, token reconnect recovery
- ✓ PutRemoteIp — X-Forwarded-For parsing with compile-time CIDR caching + IPv4-mapped IPv6 normalization; 11 tests
- ✓ FamilyNewLive + FamilySetupLive — self-service family creation; architecture split for reconnect safety (token in URL)
- ✓ CommunityAdminLive — admin panel for family management + setup link issuance/reissuance
- ✓ FamilyContext — multi-family resolution (`resolve/2`) + family switching controller + `last_active_family_id`
- ✓ PendingUserReaper — GenServer sweeping pending users every 15 min
- ✓ Cursor pagination substrate — `message_seq` column, `conversation_summaries` table with trigger, `user_read_cursors` table
- ✓ `last_message_preview` removed from conversation list API (E2EE spec compliance)
- ✓ Logout device revocation — `SessionController.delete/2` calls `Sessions.revoke_device/2`
- ✓ Name minimum reduced to 1 char — CJK single-kanji names unblocked across 5 validation sites
- ✓ 404/410 templates stripped to content-only — no duplicate LiveSocket, skip links, or HTML shell
- ✓ 410 error page rewritten to brand voice — warm relational copy, no ALL-CAPS terminal aesthetic
- ✓ Green CTA button contrast fixed — `--color-mint-500` #45bd7f→#2d8f5f (4.5:1 ratio)
- ✓ Skip-to-content target — `id="main-content"` added to `<main>` in app.html.heex
- ✓ "Getting started?" text size bumped 2xs→1xs
- ✓ Welcome message prompt after invite generation — operator can leave a greeting before invitee arrives
- ✓ PubSub auto-navigate on member_joined — operator sees conversation when invitee completes registration
- ✓ Self-service button demoted to text link on login page
- ✓ Discoverable passkey assert rate-limited (20/IP/min)
- ✓ Family creation rate limit raised 3→10/IP/hr (NAT-friendly)
- ✓ 2 Japanese brand voice violations fixed (権限がありません→許可されていません, 管理者→セットアップが必要)
- ✓ 11 new Japanese gettext translations added
- ✓ Auto-authenticate after passkey registration — `enrich_session/2` extracted, wired into register+assert+OTP; `remember_device?: true`
- ✓ Browser Notification API on incoming Channel messages — permission on join, Notification on `new_msg` when tab hidden
- ✓ HomeLive opens directly to 1:1 conversation — `conversation_type` derived from actual conversation, not hardcoded `"family"`
- ✓ `push_navigate` removed from `member_joined` handler — replaced with in-place assigns + `send(self(), :auto_connect)`
- ✓ `sender_name` forwarded through JS hook pushEvent to LiveView
- ✓ `UNIQUE_CONVERSATION_KEY_SALT` moved to runtime.exs with prod raise guard + dev/test default
- ✓ `Mix.env()` replaced with `Application.get_env(:famichat, :environment)` in application.ex
- ✓ `seenMessageIds` cleared on conversation switch in JS hook (review fix: dedup cache leak)
- ✓ `verify_otp` wired with `enrich_session/2` (review fix: OTP session parity)
- ✓ `FamilyContext.resolve` catch-all with Logger.warning (review fix: silent 500 prevention)
- ✓ Device revoke error messages wrapped in `gettext()` (review fix: i18n compliance)
- ✓ Warm empty-state copy — role-differentiated (admin anticipatory, invitee action-prompting with partner name)
- ✓ Consumed-invite recovery — clear copy ("ask for a new one"), conditional sign-in link hidden for `:used`
- ✓ Locale persistence — on_mount DB load, SessionRefresh restore, RootRedirectController DB fallback, locale CHECK constraint
- ✓ .env.production.example — ungitignored, WebAuthn moved to runtime.exs with prod raise guards
- ✓ Japanese translations completed — 22 errors.po, 7 fuzzy flags removed, orphaned 404.po deleted
- ✓ Invite TTL aligned to SPEC — code 7d→72h, all EN+JA copy updated
- ✓ POSTGRES_PASSWORD prod guard — raises on missing or default "password" value
- ✓ GitHub webhook plug removed — dead code (controller doesn't exist, hardcoded secret)
- ✓ Dead content_* config removed from runtime.exs
- ✓ CSP plug reads from Application.get_env, port consistency fixed
- ✓ Abandoned invite telemetry — `[:famichat, :invite, :abandoned]` event + Logger.warning
- ✓ TokenReaper — GenServer sweeping expired tokens every 30 min
- ✓ OrphanFamilyReaper — GenServer sweeping memberless families every 30 min (1hr buffer, guards for missing conversations FK)
- ✓ Rate limit on `reissue_passkey_token/1` — 5 attempts / 5 minutes per user_id; closes last unprotected token-issuing function
- ✓ Passkey error escalation — `error_count` in LoginLive; 3+ failures shows device hint + social recovery guidance; JA translated
- ✓ "No read receipts" note — shown in empty conversation state before first message; JA translated
- ✓ Browser tab title — already working for conversations; added `assign_page_metadata(family.name)` for empty-state branch

---

## What NOT to build now

- **OTP email delivery** — infra not configured; skip for L1. Routes exist but deliver no email.
- **Full WASM E2EE (Path C)** — L3 work. WASM spike passed GO; architecture decided (ADR 012).
- **Key package endpoints, Welcome routing, multi-device join** — L3 gate items
- **Photo sharing, message threads, reactions** — photo sharing punted to next cycle; rest is L2+
- **Design system, LiveView abstractions** — throwaway views, don't invest
- **QR pairing UI** — invite link sufficient for 2-person L1
- **Letters** — deferred entirely for L1; validate daily text use first
- **Multi-family context switching** — code exists (FamilyContext), not wired into HomeLive; irrelevant for L1
- **Unread counts** — substrate exists (message_seq, user_read_cursors, conversation_summaries); math not wired; L2 work
- **Browser notifications beyond basic** — current implementation: permission on join, Notification on new_msg when tab hidden. No push notifications, no service worker. Sufficient for L1.

---

## Key decisions locked

| Decision | Details |
|---|---|
| E2EE path | Path C: Svelte SPA + OpenMLS WASM in Web Worker; spike passed GO |
| Frontend model | Full SPA — ADR 012 |
| LiveView scope | Auth, onboarding, admin only — tightly coupled, explicitly deletable |
| NIF fate | Transitional gap — keep during L0/L1 only; scheduled for removal at L3 gate. Do not extend. |
| Mobile | Capacitor 7 at L3; `ASWebAuthenticationSession` for passkeys |
| Security stance | Server decrypts during L0/L1 — **this is a known gap, not target architecture**; Path C (client-side only) required before L3. Do not build on top of server-side decrypt. |
| No server-side previews | `last_message_preview` must be removed; SPA maintains local decrypted preview cache |
| Invite TTL | 72 hours per SPEC; code, EN copy, JA copy all aligned |
| Photo sharing | Punted to next cycle; not required for L1 dogfood |
| Deployment | Homelab + Docker Compose + Cloudflare Tunnel; dogfoods operator self-hosting experience |
| Refresh token TTL | 30 days (deferred to L2; 7-day TTL adds friction, no security gain at L1) |

---

## Known gaps — blocking L3

- Key package table + distribution endpoints not built
- No Welcome message routing for offline devices
- `/app/*` SPA catch-all route not wired
- CSP not updated for WASM Web Worker (`worker-src 'self' blob:`)
- `device_id` → MLS leaf index mapping gap (blocks revoke → MLS removal)
- S7 + M3 WASM spike criteria pending physical iOS device

## Known gaps — blocking Phase 1 (message plane)

- ~~`message_seq` absent from `messages` table~~ Committed (95eb458): column, migration, backfill, and old pagination index dropped
- ~~`user_read_cursors` table does not exist~~ Committed (95eb458): `user_read_cursors` table with `(user_id, conversation_id)` composite key, per SPEC's per-user watermark model
- ~~`conversation_summaries` table does not exist~~ Committed (95eb458): table + PostgreSQL trigger on message insert
- `pending_welcomes` table does not exist — offline device join is not durable
- ~~`last_message_preview` actively returned by `GET /api/v1/me/conversations`~~ Removed
- `unread_count` absent from conversation list response — inbox is not a usable inbox (substrate now exists via `user_read_cursors` + `conversation_summaries`; math not wired)
- `Idempotency-Key` header — not read by any mutation endpoint; reconnect retries produce duplicate messages

## Known gaps — pre-existing, not blocking L1

- 66 pre-existing test failures in lifecycle, channel, MLS modules. Root causes: stale `household_id` field name in 41 test locations; hardcoded UUIDs in channel tests; snapshot payload shape drift. Separate workstream per decision.
- No CI workflow runs `mix test` as a standalone step.
- `excludeCredentials` and `allowCredentials` in passkey challenge options use `Base.encode64` instead of `Base.url_encode64` (base64url). May silently fail on strictly conformant browsers.
- `GET /api/v1/devices` endpoint not built.
- `HomeLive` performs server-side decryption for LiveView rendering — **transitional gap, not target architecture**. Acceptable at L0/L1 only. Must be removed before L3.
- Device pending-state enforcement not implemented — all authenticated sessions start as active regardless of role.
