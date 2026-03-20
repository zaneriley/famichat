# Backlog Archive

Completed and cut items moved from BACKLOG.md. For duplicate checking only — do not read sequentially.

Search here before adding new items to BACKLOG.md.

---

## Blocks dogfooding (P0)

- [x] Revoke device on logout in SessionController.delete
- [x] Reduce name input minimum to 1 char for CJK scripts
- [x] Auto-authenticate after passkey registration
- [x] Add browser Notification API integration on incoming Channel messages
- [x] Add .env.production.example with all required env vars documented (dfd6091)
- [x] Make HomeLive open directly to 1:1 conversation for L1
- [x] Add warm empty-state copy when conversation has zero messages (dfd6091)
- [x] Show clear forward path for consumed-but-incomplete invites (dfd6091)
- [x] Persist user_locale to users table, resolve on mount (dfd6091)
- [x] Fix `conversation_type` hardcode to `"family"` in HomeLive
- [x] Remove `push_navigate` from HomeLive `member_joined` handler
- [x] Forward `sender_name` through hook pushEvent to LiveView
- [x] Move `UNIQUE_CONVERSATION_KEY_SALT` to runtime.exs for fail-fast
- [x] Complete ~30 missing Japanese gettext translations (dfd6091)
- [x] Fix @legacy_kind_map to match DB constraint (90b0d5b)
- [x] Wrap user+token creation in Ecto.Multi transaction (90b0d5b)
- [x] Add :not_found_html clause to FallbackController.call/2 (90b0d5b)
- [x] Fix PutRemoteIp to parse X-Forwarded-For (95eb458)
- [x] Fix setup_token lost on FamilyNewLive WebSocket reconnect
- [x] Add validate_length(:name, max: 100) to Family.changeset (76776e4)
- [x] Remove last_message_preview from API
- [x] Fix FamilySetupLive auth bounce (76776e4)
- [x] Fix LiveView locale redirect (76776e4)
- [x] Fix blank family name "already taken" error (76776e4)
- [x] Constrain :locale route param to known locales (76776e4)
- [x] Remove `pull_repository()` call and dead content-repo code from `docker-entrypoint-web`
- [x] Remove `config :famichat, :cache, disabled: true` from prod.exs
- [x] Fix CORS: remove CORSPlug for L1 or make origin configurable via env var
- [x] Fix Dockerfile `../run` (8fd6ead)
- [x] Fix LiveView crash on "Generate invite link" in setup post-passkey step
- [x] Add community-admin role check to CommunityAdminLive (`/en/admin`)
- [x] Add `validate_length` on username in `User.changeset` at all entry points (setup, invite, family-start)
- [x] Enforce compile-time domain boundary annotations — replace `exports: :all` with explicit exports on all major boundaries (2c307c8)
- [x] Delete `FamichatWeb.SchemaMarkup` — hardcoded PII, zero callers (2c307c8)

## Blocks confidence (P1)

- [x] Add OrphanFamilyReaper (1b02ab3)
- [x] Add TokenReaper for expired/consumed tokens (1b02ab3)
- [x] Normalize error tags (:retryable (76776e4)
- [x] Add rate limit to reissue_passkey_token/1 (1b02ab3)
- [x] Fix green CTA button contrast ratio (2.38:1
- [x] Add visible error feedback when passkey auth fails
- [x] Increase "Getting started?" text from 12.5px to ≥16px
- [x] Fix skip-to-content target
- [x] Rewrite 410 error page to match brand voice
- [x] Disable HEEx debug annotations in prod (76776e4)
- [x] Switch CSP from report-only to enforcing; remove unsafe-eval (76776e4)
- [x] Fix flash-group div intercepting pointer events on header nav (90b0d5b)
- [x] Add LiveView mount crash fallback (90b0d5b)
- [x] Prompt operator to leave welcome message after invite generation
- [x] Auto-navigate operator to conversation when invitee completes registration
- [x] Show one-time "no read receipts" contextual note on first message (1b02ab3)
- [x] Fix 2 Japanese brand voice violations (管理者 in community_admin_live.ex)
- [x] Escalate passkey error copy after 3+ repeated failures (1b02ab3)
- [x] Demote "Set up your own family space" button to text link on login page
- [x] Show social recovery guidance after 2-3 failed passkey attempts
- [x] Set browser tab title to partner name or family name
- [x] Fix `Mix.env()` in application.ex
- [x] Add prod guard for POSTGRES_PASSWORD in runtime.exs (dfd6091)
- [x] Fix 404/410 templates to content-only
- [x] Add rate limiting to discoverable passkey assert/challenge endpoint
- [x] Raise family creation rate limit from 3 to 10/IP/hour
- [x] Add `secure: true` to session cookie options for production
- [x] Remove LiveDashboard RequestLogger plug from production
- [x] Remove `localhost`/`0.0.0.0` from CSP hosts in production
- [x] Restrict CSP `connect-src` to specific WebSocket URL, not bare `ws:/wss:`
- [x] Add explicit `check_origin` for production WebSocket connections
- [x] Fix `release-please.yml` Docker build context to `backend/`
- [x] Add NIF load verification step to Dockerfile after `mix release`
- [x] Add web healthcheck to `docker-compose.production.yml`
- [x] Update stale WebAuthn compile-time warnings in `.env.production.example`
- [x] Change Docker Compose port default to `127.0.0.1`
- [x] Add build args and `POSTGRES_DB` to production compose
- [x] Add `restart: unless-stopped` to production compose services
- [x] Document WebAuthn/URL variable relationships with decision tree in `.env.production.example`
- [x] Fix env_file reference to `.env.production` in compose file
- [x] Replace misleading pg_dump comment with setup instructions in compose
- [x] Add POSTGRES_PASSWORD generation command to `.env.production.example`
- [x] Simplify compose healthcheck to CMD array form
- [x] Add Docker build validation step to CI (build without push)
- [x] Document FAMICHAT_MLS_ENFORCEMENT in `.env.production.example`
- [x] Add warm error messages to `runtime.exs` for all missing env vars
- [x] Add SECRET_KEY_BASE length guard (>= 64 chars) to runtime.exs
- [x] Add WEBAUTHN_ORIGIN https:// scheme warning to runtime.exs
- [x] Batch missing-required-var errors into single raise in runtime.exs
- [x] Fix empty POSTGRES_PASSWORD bypass in runtime.exs (`{:prod, ""}` guard)
- [x] Register `Clipboard` LiveView hook in `app.js`
- [x] Add clipboard write confirmation ("Copied!") to all copy buttons
- [x] Deduplicate invite token generation; show existing-token state on panel
- [x] Add success feedback to "Save message" welcome prompt button
- [x] Translate browser `<title>` on invite error page to current locale
- [x] Fix duplicate paragraph on invite error page
- [x] Fix unstyled bare-HTML 404 for `/en/families/start/<invalid-token>`
- [x] Add "Go back" to passkey step in `FamilySetupLive`
- [x] Translate "Invite a family member" button label in Japanese locale
- [x] Show specific error on duplicate family name in `/en/admin` add-family form
- [x] Fix `TypeError: Cannot read properties of undefined (reading 'size')` on `/admin/message` load
- [x] Add "Local Storage Privacy Stance" section to SPEC.md
- [x] Resolve SPEC:645 [CONFLICT] data preservation vs. data minimization
- [x] Add `use Boundary` annotation to `Famichat.Crypto.MLS` (2c307c8)
- [x] Add `Famichat.Crypto.MLS` to deps in `Mix.Tasks.Famichat.BackfillSnapshotMacs` (2c307c8)

## Known debt (P2)

- [x] Add HSTS header for production HTTPS deployments (76776e4)
- [x] Gate console.log output behind dev flag (76776e4)
- [x] Fix 410 page hardcoded lang="en" (90b0d5b)
- [x] Root / should respect Accept-Language header for locale redirect
- [x] Make 404 page locale-aware and fix hardcoded /en/ in RETURN TO HOME link (90b0d5b)
- [x] Move CSP plug env var reads to Application.get_env (dfd6091)
- [x] Remove Playwright from Docker assets stage
- [x] Remove dead `github_webhook` dep from mix.exs and config.exs (8fd6ead)
- [x] Remove dead content-repo env vars from `.env.production.example`
- [x] Remove unused COMPOSE_PROFILES from `.env.production.example`
- [x] Remove dead CSP_SCHEME/CSP_HOST/CSP_PORT from `.env.production.example`
- [x] Move or delete `backend/.github/workflows/ci.yml` (8fd6ead)
- [x] Remove `excoveralls` dep from mix.exs (8fd6ead)
- [x] Remove dead modules (TestBroadcastController, ThemeSwitcher, ast_renderer.ex, Authenticators shim) (8fd6ead)
- [x] Remove ThemeSwitcherHook import from app.js (8fd6ead)
- [x] Remove dead Content module config from config.exs, dev.exs, prod.exs, test.exs (8fd6ead)
- [x] Fix Type dropdown in `/admin/message` resetting to "self" when Encrypt Messages toggled
- [x] Fix `TypeError: null.getAttribute` crash in LiveView pushInput on `/admin/message` Type change
- [x] Replace `exports: :all` in `Famichat.Chat` boundary with explicit export list (2c307c8)
- [x] Remove phantom dep `Famichat.Auth.Identity` from `Famichat.Auth.Sessions` boundary (2c307c8)
- [x] Remove stale dep `Famichat.Auth.Households` from `Famichat.Auth.Recovery` boundary (2c307c8)
- [x] Delete `Famichat.Accounts.Errors`, `FamichatWeb.LiveError`, and `Famichat.Communities` — zero-caller dead code (2c307c8)
- [x] Fix stale `alias Famichat.Chat.User` in `GroupConversationPrivileges` to `Famichat.Accounts.User` (2c307c8)

## Someday/maybe (P3)

- [x] Create self-hosting docs folder (`docs/self-hosting/`) (a85c2bd)

## Investigated — not a bug / merged into other item

- [x] Build QR pairing UI
- [x] Auto-create 1:1 conversation when second family member joins
- [x] Gate session creation in `invites/complete` behind passkey completion
- [x] Remove or gate "Admin Controls" (Revoke/Reset Security State) in HomeLive for non-admin users
- [x] Add copy alignment: privacy line, empty-state forward path
- [x] Add ~30 missing Japanese gettext translations
- [x] Fix duplicate "Skip to main content" links on 404 error page
- [x] Reduce name input minimum to 1 char for CJK scripts
- [x] Preserve locale prefix on authenticated post-login redirects
- [x] Add CookieOrBearerAuth plug for dual-path API auth
- [x] Enhance `GET /api/v1/me` with device_id, locale, active_family_id
- [x] Decide wasm-pack #1490 workaround for Cargo workspace profiles
- [x] Fix duplicate LiveSocket initialization on 404 page
- [x] Make locale-aware placeholder examples consistent across all inputs
- [x] Make invite error copy available in all supported locales
- [x] Confirm `Plug.Debugger` / `debug_errors: true` absent in production config

