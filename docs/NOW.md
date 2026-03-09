# Famichat NOW

**Last updated:** 2026-03-09

Non-evergreen context. For stable design guidance, see [SPEC.md](SPEC.md) and [ADR 012](decisions/012-spa-wasm-client-architecture.md).

---

## One-line state

The browser front door is mostly walkable for first-family dogfood: setup, invite acceptance, passkey registration, and passkey login all exist in the browser. The message plane, data model, and client crypto layers are materially incomplete against the execution plan. Zero of five MLP dogfood gates can be cleared in the current build.

---

## What just happened (2026-03-09)

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
| `/en/setup` | PARTIAL | Bootstrapped instance redirects to login. Incomplete-bootstrap recovery works. Admin is NOT auto-authenticated after the passkey ceremony — "Go to your family space" silently redirects to login because HomeLive requires a session. |
| `/en/invites/:token` | ✓ 200 | Invalid/used tokens stay on the invite LiveView instead of falling through to 404 |
| `/en/families/start/:token` | ✓ 200 | Token-gated family setup; reconnect recovery via `peek_family_setup/1` |
| `/api/v1/health` | ✓ 200 | No longer shadowed by `:locale` catch-all |
| `/api/*` | ✓ | Route table assertions prevent locale scope from shadowing API routes |
| Front-door regression tests | ✓ pass | `front_door_live_test.exs` + `session_refresh_test.exs` + security baseline + route table tests pass |

---

## Current blockers

### P0 — Self-service family creation has two user-blocking bugs

The code for `/families/new` (self-service) and `/families/start/:token` (token-gated) exists in the working tree but is uncommitted. Two bugs block dogfooding:
1. **PutRemoteIp ignores X-Forwarded-For** — behind any reverse proxy, all visitors share one rate-limit bucket. Every production topology uses a proxy.
2. **setup_token lost on LiveView reconnect** — mobile users on cellular will hit this within the first session. Family name "taken" by your own orphan with no recovery path.

See `BACKLOG.md` P0 items and `.tmp/2026-03-08-new-accounts/07-robustness-error-paths.md` for detail.

### P0 — `last_message_preview` actively violates the E2EE spec

`GET /api/v1/me/conversations` returns a `last_message_preview` field built from plaintext `m.content`. The spec explicitly forbids this and calls it a "migration trap." The field is in the API contract today. File: `backend/lib/famichat_web/controllers/api/chat_read_controller.ex`, lines 17, 28, 106, 175–192.

### P1 — Signed-in app is still first-membership-wins

`HomeLive.load_family_data/1` still picks the first membership and collapses the user into one family context. Even if the DB model can represent multi-family membership, the signed-in browser surface cannot yet.

### P1 — Message plane is critically incomplete

The following are absent from the database and service layer, all required for Phase 1:
- `message_seq` — no column, no migration, no index. Cursor pagination and unread math have no substrate.
- `device_read_cursors` — no table. Acks are ephemeral (logged only, not persisted). Unread counts cannot be computed.
- `conversation_summaries` — no table. Inbox API runs live joins on every request.
- Unread count math — both prerequisite inputs are absent.
- `Idempotency-Key` header — not read by any mutation endpoint. Reconnect retries produce duplicate messages.

### P2 — Browser-walkable front door still needs a real browser pass

Route QA and LiveView tests now cover the root/login/setup recovery contract, but a fresh-browser manual walkthrough of bootstrap → passkey → signed-in home was not rerun in this update window.

---

## MLP dogfood gate status

From `.tmp/2026-03-07-mlp/05-mlp-rollout-and-success-signals.md`. All five gates are currently blocked.

| Gate | Status | What is needed |
|---|---|---|
| Operator bootstraps, then creates second family | PARTIAL | Code exists (uncommitted); PutRemoteIp and reconnect bugs block real use |
| Second-family first adult completes setup link | PARTIAL | `/families/start/:token` exists; `/families/new` has two bugs — see BACKLOG.md P0 |
| Household admin invites member into new family | PARTIAL | Invite flow works for first family; multi-family not tested |
| Multi-family context switch works cleanly | BLOCKED | `HomeLive.load_family_data/1` uses first-membership-wins |
| Abandoned family setup is recoverable | BLOCKED | No post-bootstrap family setup flow exists to recover from |

---

## MLP entry point status

| MLP-required route | Status |
|---|---|
| `/setup` for first-run only | EXISTS — one-shot; permanently closes after first user |
| `/login` for existing members | EXISTS — passkey discoverable flow only; no OTP/magic link fallback |
| `/invites/:token` for joining an existing family | EXISTS — functional |
| `/families/start/:token` for starting a newly created family | EXISTS — functional (in working tree, uncommitted) |
| `/families/new` for self-service family creation | EXISTS — has reconnect + rate-limit bugs (in working tree, uncommitted) |

---

## Immediate next steps (in order)

### 1. Remove `last_message_preview` from the conversation list API
Delete `@max_preview_length`, `latest_previews/1`, and the `"last_message_preview"` key from `present_conversation/3` in `chat_read_controller.ex`. This is an active E2EE spec violation that creates a migration trap.

### 2. Phase 2: add community-admin family creation
Introduce a real post-bootstrap flow to create a family and issue a first-admin setup link. Do not reuse `bootstrap_admin/2`. Wire the "Start a family on this server" public entry point.

### 3. Replace implicit family selection
Add explicit active-family selection/persistence before claiming multi-family support in the signed-in app.

### 4. Run a real browser walkthrough
Fresh instance bootstrap, invite acceptance, and returning sign-in should all be walked in a real browser after the current auth/onboarding fixes.

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

---

## What NOT to build now

- **OTP email delivery** — infra not configured; skip for L1. Note: the OTP and magic link routes (`/auth/otp/request`, `/auth/otp/verify`, `/auth/magic-link/*`) are declared in the router and reachable in production but deliver no email. They return HTTP 202 for both existing and nonexistent addresses (intentional enumeration prevention). The `x-test-token` header works only in `:test` env.
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
| NIF fate | Transitional gap — keep during L0/L1 only; scheduled for removal at L3 gate. Do not extend. |
| Mobile | Capacitor 7 at L3; `ASWebAuthenticationSession` for passkeys |
| Security stance | Server decrypts during L0/L1 — **this is a known gap, not target architecture**; Path C (client-side only) required before L3. Do not build on top of server-side decrypt. |
| No server-side previews | `last_message_preview` must be removed; SPA maintains local decrypted preview cache |

---

## Known gaps — blocking L3

- Key package table + distribution endpoints not built
- No Welcome message routing for offline devices
- `/app/*` SPA catch-all route not wired
- CSP not updated for WASM Web Worker (`worker-src 'self' blob:`)
- `device_id` → MLS leaf index mapping gap (blocks revoke → MLS removal)
- S7 + M3 WASM spike criteria pending physical iOS device

## Known gaps — blocking Phase 1 (message plane)

- `message_seq` absent from `messages` table — cursor pagination uses `(inserted_at, id)` instead of monotonic integer; unread math has no substrate
- `device_read_cursors` table does not exist — acks are ephemeral, unread counts impossible
- `conversation_summaries` table does not exist — inbox API runs live joins; `last_message_at` and `member_count` absent from conversation list response
- `pending_welcomes` table does not exist — offline device join is not durable
- `last_message_preview` actively returned by `GET /api/v1/me/conversations` — E2EE spec violation
- `unread_count` absent from conversation list response — inbox is not a usable inbox

## Known gaps — pre-existing, not blocking L1

- 66 pre-existing test failures in lifecycle, channel, MLS modules. Root causes: stale `household_id` field name in 41 test locations; hardcoded UUIDs in channel tests that conflict with `community_id` non-null constraint added in recent migration; snapshot payload shape drift after N4/N5 hardening.
- No CI workflow runs `mix test` or `rust:test` as a standalone step — tests only run through `./run qa:messaging:*`.
- `WEBAUTHN_ORIGIN`, `WEBAUTHN_RP_ID`, `WEBAUTHN_RP_NAME` not configured for production. Note: these values are baked at compile time in releases, not read at runtime — setting them as deploy-time env vars alone does not work.
- `GET /api/v1/devices` endpoint not built
- Logout (`GET /:locale/logout` → `SessionController.delete/2`) clears the session cookie but does not revoke the refresh token. A stolen refresh token remains usable for up to 30 days after logout.
- `excludeCredentials` and `allowCredentials` in passkey challenge options use standard `Base.encode64` instead of `Base.url_encode64` (base64url). This may silently fail credential matching on strictly conformant browsers.
- ~~301 Permanent Redirect in `LocaleRedirection`~~ — Fixed: now 302 (76776e4).
- Hardcoded GitHub webhook secret in `backend/lib/famichat_web/endpoint.ex` line 18, and `FamichatWeb.ContentWebhookController` referenced there does not exist — will crash on first webhook delivery.
- `HomeLive` currently performs server-side decryption for LiveView rendering (`resolve_display_body/2`, `fetch_decrypted_body/4`) — **transitional gap, not target architecture**. Acceptable at L0/L1 only. Must be removed before L3. Do not extend or optimize this path.
- Device pending-state enforcement (Path A) is not implemented — all authenticated sessions start as active regardless of role.
