# Famichat Backlog

**Last updated:** 2026-03-20

Open work only. Completed items → [BACKLOG-ARCHIVE.md](BACKLOG-ARCHIVE.md). Resolved decisions and cut items → [DECISIONS.md](DECISIONS.md).

---

## Format

`- [ ] Description — why it matters ≤15 words → path/to/detail.md | severity | source`

- **Severity**: `P0-dogfood` (blocks family handoff) · `P1-confidence` (erodes trust) · `P2-debt` (not blocking) · `P3-idea` (someday)
- **Pointer** (`→`): path to detail file. Omit if the one-liner IS the detail.
- **Source**: `agent:consensus`, `browser-walkthrough`, `spec-review`, etc.
- When done: move to BACKLOG-ARCHIVE.md with commit hash. When decided/cut: move to DECISIONS.md.
- Before adding: grep BACKLOG-ARCHIVE.md to check it wasn't already done.

---


## Blocks dogfooding (P0)
<!-- Cannot hand URL to family until fixed -->
- [ ] Add `"app"` to `static_paths/0` and enable `gzip: true` in Plug.Static — SPA assets return 404; nothing loads → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P0-dogfood | agent:consensus
- [ ] Add `wasm-unsafe-eval` to CSP `script-src` and add `worker-src 'self' blob:` — WASM and Workers fail silently in production → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P0-dogfood | agent:consensus
- [ ] Create SpaController with authenticated boot page and `/app/*` catch-all before `/:locale` scopes — all SPA deep links 404; auth handoff requires server-rendered boot page → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P0-dogfood | agent:consensus
- [ ] Change Docker build context from `backend/` to repo root — frontend build stage inaccessible from Docker → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P0-dogfood | agent:consensus
- [ ] Create Cargo workspace root at `backend/infra/Cargo.toml` — conflicting profiles produce wrong WASM optimization → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P0-dogfood | agent:consensus
- [ ] Implement cookie-based same-origin auth (ApiAuth plug + server-rendered boot page) — device revocation guaranteed under Bearer-only model on cross-surface navigation → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P0-dogfood | agent:consensus
- [ ] Fix `:spa` pipeline to include `:fetch_session` and `SessionRefresh` — SpaController cannot read session cookie without them → .tmp/2026-03-20-spa-scaffold/ia-proposals/02-auth-boot.md | P0-dogfood | agent:ia-consensus
- [ ] Implement `FamichatWeb.BootContext.for_conn/1` as Web-layer aggregator — SpaController must not read session keys directly → .tmp/2026-03-20-spa-scaffold/ia-proposals/02-auth-boot.md | P0-dogfood | agent:ia-consensus
- [ ] Implement dual-path boot context delivery (HTML embed + `GET /api/v1/boot`) — SPA needs session-scoped data at cold start without modifying `/me` → .tmp/2026-03-20-spa-scaffold/ia-proposals/02-auth-boot.md | P0-dogfood | agent:ia-consensus
- [ ] Standardize `channel_token` naming and implement `POST /api/v1/auth/channel_tokens` — SPA has no way to obtain a WebSocket auth token → .tmp/2026-03-20-spa-scaffold/ia-proposals/03-channel-api.md | P0-dogfood | agent:ia-consensus
- [ ] Implement `SystemChannel` on `system:user:{user_id}` with `session_terminated` event — revoked device has no proactive notification → .tmp/2026-03-20-spa-scaffold/ia-proposals/03-channel-api.md | P0-dogfood | agent:ia-consensus
- [ ] Lock boot page EN/JA copy in `boot.html.heex` — users see blank page without pre-Svelte loading/failure text → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P0-dogfood | agent:ia-consensus
- [ ] Lock worker recovery failure EN/JA copy — WASM crash with no user message leaves users stranded → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P0-dogfood | agent:ia-consensus
- [ ] Add `SpaCSPHeader` plug scoped to `:spa` pipeline only — `wasm-unsafe-eval` on LiveView paths is a security regression → .tmp/2026-03-20-spa-scaffold/ia-proposals/05-lexicon-invariants.md | P0-dogfood | agent:spa-readiness (elevated from P1)

## Blocks confidence (P1)
<!-- Can dogfood, but erodes trust -->
- [ ] Resolve `signer_bytes` raw base64 exposure: encrypt at rest with wrapping key before L3 — signing private key unencrypted in IndexedDB; XSS steals identity → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Add `famichat_messages` IndexedDB schema (messages, conversation_previews, sync_cursors stores) — conversation list blank on every app open without local preview cache → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Implement "local first, sync delta" pattern with `sync_cursors` tracking `last_local_seq` — full re-fetch takes 10-20s on mobile; unusable for grandparent persona → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Define key lifecycle for logout, revocation, and browser-clear in ADR 012 — undefined behavior leaks keys on shared devices or causes silent data loss → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Add `kdf_algo` versioning field to `keystore_metadata` IndexedDB schema — Argon2id upgrade without version field requires breaking migration → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Add HMAC integrity protection to KDF salt in `keystore_metadata` — salt tampering makes all local encrypted data permanently unreadable → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Build cursor-based pagination endpoint (`?after=<message_seq>`) on server — offset/limit pagination cannot support sync delta pattern → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Update ADR 012 for local-first decisions — 30-min idle timeout conflicts with instant-open; famichat_messages schema, Dexie.js, local-first framing undocumented → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Scaffold `frontend/` with SvelteKit + adapter-static + pnpm workspace — no SPA project exists; blocks all frontend work → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Run Vite 8 + WASM plugin smoke test before scaffold — vite-plugin-wasm undocumented on Vite 8/Rolldown; SvelteKit requires Vite 8 → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Pin Svelte/Vitest to avoid $effect flushSync blocker (sveltejs/svelte#16092) — $effect rune testing broken in current pinned versions → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Adopt Comlink for WASM worker RPC — manual request-ID/timeout boilerplate is fragile → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Move `famichat_mls_keystore` IndexedDB writes into worker — write-ordering invariant unenforceable from main thread → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Implement CryptoWorkerManager with restart, IndexedDB recovery, socket coordination — WASM panic kills worker permanently → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Add `decryptBatch` to worker protocol — progressive decrypt causes inconsistent UI on mid-batch failure → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Add WASM and frontend build stages to Dockerfile — CI/CD cannot build or deploy SPA → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Create `ci-wasm.yml` and `ci-frontend.yml` workflows — no CI for SPA build, test, or size gate → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Build Dexie `liveQuery` + Svelte 5 runes reactive bridge — liveQuery doesn't work with runes natively → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Add transparent SessionRefresh to API pipeline for cookie-auth — SPA gets free token rotation with no JS management → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Add `POST /api/v1/auth/channel_tokens` endpoint — SPA cannot get channel tokens via LiveView push_event → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Add `session_terminated` event via SystemChannel to clear local state on revocation — revoked device stays active indefinitely → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Set up Vitest browser mode + vitest-browser-svelte for SPA component tests — Svelte 5 runes produce false test results in jsdom → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Define ConversationCrypto TypeScript interface as worker/test boundary — WASM untestable in Node.js without mock boundary → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Add `spa:*` and `wasm:build:web` commands to run script — no developer workflow for SPA → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Create `wasm-rebuild-atomic.sh` for dev watch mode — Vite loads partially-written WASM during rebuilds → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Implement iOS filesystem backup tier for MLS keys via @capacitor/filesystem — iOS evicts IndexedDB under storage pressure; keys lost permanently → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Verify AASA file accessibility for passkey spike on staging — VPN-only staging silently fails passkey registration → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:consensus
- [ ] Write IndexedDB invariant contracts for `famichat_mls_keystore` and `famichat_messages` — stores hold security-critical state with no documented preconditions → .tmp/2026-03-20-spa-scaffold/ia-proposals/05-lexicon-invariants.md | P1-confidence | agent:ia-consensus
- [ ] Document device trust state to client behavior mapping — developer has no spec for "terminate the worker" → .tmp/2026-03-20-spa-scaffold/ia-proposals/01-client-context.md | P1-confidence | agent:ia-consensus
- [ ] Document `MlsWorkerApi` vs `ConversationCrypto` import hierarchy as boundary rule — without stated rule, developers bypass domain interface → .tmp/2026-03-20-spa-scaffold/ia-proposals/01-client-context.md | P1-confidence | agent:ia-consensus
- [ ] Lock `session_terminated` EN/JA copy in brand-positioning.md — brand-violating copy will be written by default → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P1-confidence | agent:ia-consensus
- [ ] Lock "Clear messages on this device" EN/JA copy — "Clear local data" is engineering language that will reach users → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P1-confidence | agent:ia-consensus
- [ ] Lock private browsing warning EN/JA copy — private mode silently breaks MLS persistence with no user explanation → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P1-confidence | agent:ia-consensus
- [ ] Lock iOS push limitation EN/JA copy for settings panel — users who miss messages have no non-technical explanation → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P1-confidence | agent:ia-consensus
- [ ] Retire "boot token" from ADR 012 and routing sub-doc — stale terminology misleads implementers → .tmp/2026-03-20-spa-scaffold/ia-proposals/05-lexicon-invariants.md | P1-confidence | agent:ia-consensus
- [ ] Rename `WorkerSupervisor`/`CryptoService` to canonical names in ADR 012 — stale names in active design doc cause confusion → .tmp/2026-03-20-spa-scaffold/ia-proposals/01-client-context.md | P1-confidence | agent:ia-consensus
- [ ] Rate-limit `GET /api/v1/boot` to 10 req/min per device — endpoint issues channel token on every call → .tmp/2026-03-20-spa-scaffold/ia-proposals/02-auth-boot.md | P1-confidence | agent:ia-consensus
- [ ] Confirm "clear messages" preserves session (does not sign user out) — confirmation body copy depends on behavior → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P1-confidence | agent:ia-consensus
- [ ] Document P0 SPA item dependency order (Phase 1: Cargo+Docker, Phase 2: router+plugs, Phase 3: BootContext+endpoints, Phase 4: copy+scaffold) — implementer starting Phase 3 without Phase 2 wastes effort → .tmp/2026-03-20-spa-readiness/round-1/01-technical.md | P1-confidence | agent:spa-readiness
- [ ] Add ADR 012 + brand-positioning.md + DECISIONS.md to `docs:boundary-check` scan list — naming drift in most-read SPA doc invisible to automated check → .tmp/2026-03-20-spa-readiness/round-1/04-ia-ddd.md | P1-confidence | agent:spa-readiness
- [ ] Rewrite 500 error page to brand voice and remove personal meta description — 500 during dogfood shows leaked PII and off-brand copy → .tmp/2026-03-20-spa-readiness/round-1/02-ux.md | P1-confidence | agent:spa-readiness
- [ ] Establish green CI baseline with `--exclude` tags for known-broken tests — red CI masks new regressions → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:spa-readiness (elevated from P2)
- [ ] Evaluate Paraglide-js 2.0 for SPA i18n — JA locale is a dogfood gate; no SPA copy can be written without i18n system → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P1-confidence | agent:spa-readiness (elevated from P2)
- [ ] Migrate `@channel_bootstrap_kind` atom to `@channel_token_kind :channel_token` — endpoint will be built against wrong internal atom if not renamed first → .tmp/2026-03-20-spa-scaffold/ia-proposals/03-channel-api.md | P1-confidence | agent:spa-readiness (elevated from P2)

## Known debt (P2)
<!-- Not blocking; matters at scale or public launch -->
- [ ] Pending-user-before-passkey architectural gap — :pending user exists between complete_invite and passkey_register; find_or_create_pending_user makes this idempotent so token reuse is blocked, but user record without credential is debt → .tmp/2026-03-16-browser-walkthrough/agent-2-invite-flow.md | P2-debt | browser-walkthrough-2026-03-16
- [ ] Create `./run config:generate` interactive wizard that generates `.env.production` — operator must manually configure 15+ vars with no guidance; deferred from P1: targets non-developer operator who doesn't exist at L1 → .tmp/2026-03-10-delivery-and-deployment/round-3/05-config-ux.md, .tmp/2026-03-11-config-ux/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Create `./run config:check` pre-flight validation script — overlaps 70% with warm errors; deferred from P1 → .tmp/2026-03-10-delivery-and-deployment/round-3/05-config-ux.md, .tmp/2026-03-11-config-ux/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Add secret rotation reference to `.env.production.example` — operator who changes vault key loses all data with zero warning → .tmp/2026-03-11-config-ux/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Add visible focus indicators on interactive elements — WCAG 2.4.7 violation; outline-style is none → .tmp/2026-03-09-bug-bash/03-grandparent-user.md A11Y-05 | P2-debt | bug-bash
- [ ] Remove or populate empty footer landmark — screen readers announce empty contentinfo region → .tmp/2026-03-09-bug-bash/01-community-admin.md BUG-05 | P2-debt | bug-bash
- [ ] Add aria-live region for passkey button state changes — loading/error invisible to screen readers | P2-debt | bug-bash
- [ ] Render time gaps as human-readable labels instead of date separators — cold separators make silence feel like neglect → .tmp/2026-03-09-mlp-ux/consensus.md | P2-debt | agent:consensus
- [ ] Replace technical session-expired copy with warm brand-aligned version — "re-authenticate" breaks the family-space feeling → .tmp/2026-03-09-mlp-ux/consensus.md | P2-debt | agent:consensus
- [ ] Add photo sharing for 1:1 conversations — half of couple communication is visual; punted to next cycle → .tmp/2026-03-09-mlp-ux/consensus.md | P2-debt | agent:consensus
- [ ] Strip unnecessary packages from prod Dockerfile stage — 100MB+ build tools in prod image → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Add Docker image smoke test to CI pipeline — broken Dockerfile only discovered after release → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Update README.md with "For Self-Hosters" link to deployment guide — no path from README to deploy → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P2-debt | agent:consensus
- [ ] Remove unused CONTENT_REPO_URL and GITHUB_WEBHOOK_SECRET from dev `.env` — cargo-culted from prior project → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P2-debt | agent:consensus
- [ ] Add Docker image name to compose file — orphaned images accumulate after rebuilds → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P2-debt | agent:consensus
- [ ] Add resource limits to docker-compose.production.yml — Erlang VM can consume all homelab RAM → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P2-debt | agent:consensus
- [ ] Add logging configuration to docker-compose.production.yml — no log rotation; logs fill disk → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P2-debt | agent:consensus
- [ ] Add CSP report-uri logging endpoint for operator-visible violation diagnostics — CSP violations invisible without DevTools; operators can't diagnose from docker logs → .tmp/2026-03-11-security-config/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Document optional env vars (URL_STATIC_HOST, DNS_CLUSTER_QUERY, POSTGRES_POOL) in .env.production.example — operators can't discover tuning options → .tmp/2026-03-14-deploy-scan/env-config.md | P2-debt | agent:deploy-scan
- [ ] Fix "Test Family family." redundant suffix in families/start heading — template appends "family." unconditionally; collides when name already contains "Family" → .tmp/2026-03-16-browser-walkthrough/agent-3-family-creation.md | P2-debt | browser-walkthrough-2026-03-16
- [ ] Fix "Resend setup link" button overflowing card boundary in `/en/admin` — button clipped outside viewport on long family names → .tmp/2026-03-16-browser-walkthrough/agent-3-family-creation.md | P2-debt | browser-walkthrough-2026-03-16
- [ ] Fix `/api/` and `/api` bare paths returning HTML 404 — falls through to browser catch-all; violates contract that `/api/*` never returns HTML → .tmp/2026-03-16-browser-walkthrough/agent-6-api-basher.md | P2-debt | browser-walkthrough-2026-03-16
- [ ] Fix "Famichat home" header link from `/en/admin` dropping authenticated session — click causes LiveView disconnect and redirects to login → .tmp/2026-03-16-browser-walkthrough/agent-5-link-basher.md | P2-debt | browser-walkthrough-2026-03-16
- [ ] Normalize 401 error codes across auth endpoints — plug-level returns `"unauthorized"`, controller-level returns `"invalid_token"`; inconsistent API contract → .tmp/2026-03-16-browser-walkthrough/agent-6-api-basher.md | P2-debt | browser-walkthrough-2026-03-16
- [ ] Harden maybe_put_locale in auth_controller.ex to not overwrite URL-derived session locale — DB locale written on passkey auth could race URL locale; corrected on next page load but inconsistent with locale system → backend/lib/famichat_web/controllers/auth_controller.ex | P2-debt | agent:locale-audit
- [ ] Replace manual "/#{locale}/login" string in live_helpers.ex:86 with locale_path — inconsistent with all other redirect sites; will drift if path structure changes → backend/lib/famichat_web/live/live_helpers.ex | P2-debt | agent:locale-audit
- [ ] Design user-scoped IndexedDB partitioning for shared devices (partition by user_id) — teen on shared tablet can read parent's messages without isolation → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Design user-facing storage transparency (recovery phrase explanation, storage status in settings) — users have no mental model for where messages live or how to recover → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Define storage budget and eviction strategy for local message cache — unbounded growth fills mobile storage; 32GB iPad runs out first → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Detect and warn about private browsing mode in SPA — MLS state lost on window close with no warning; group membership breaks → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Add "Clear messages on this device" button to SPA settings (clears messages, preserves MLS keys) — shared-device users need data removal without losing session → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Design platform-divergent key storage backends (WebCryptoKeyStore, NativeKeyStore) — mobile Keychain strictly superior to PBKDF2; wastes hardware security → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Ensure Capacitor filesystem backup includes `keystore_metadata` PBKDF2 salt — salt loss after iOS eviction makes recovery phrase useless → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Implement optional passkey/biometric unlock at app open — wishlist UX layer for users who want extra security on shared devices → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Design social key recovery (1-2 family members help recover lost member's access) — grandparent who loses phrase loses all history permanently without this → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Implement server-side ciphertext TTL (30 days or all-device ACK) — indefinite retention stores data nobody can read; wastes operator storage → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Add SPA cache headers plug for immutable assets — hashed assets re-downloaded without proper headers → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Add `<link rel="prefetch" href="/app">` to LiveView layouts — adds ~100ms to LiveView→SPA transition → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Create test data factories for SPA IndexedDB seeding — no factory pattern for frontend tests → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Fix dangling vitest.e2e.config.js reference in backend/assets workspace — test:browser script fails on missing file → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Add iOS encryption export declaration (ITSAppUsesNonExemptEncryption) — App Store submission blocked without it → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Plan service worker for `/app/*` (L2/L3) — deep links require network; no offline shell → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Add Capacitor platform detection to SPA scaffold — storage, push, passkey all branch on platform → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Accept and document iOS silent push notification limitations — force-quit kills notification delivery; cannot be worked around → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Extend `docs:boundary-check` to cover TypeScript imports in `frontend/src/` — client-side import hierarchy has no automated enforcement → .tmp/2026-03-20-spa-scaffold/ia-proposals/01-client-context.md | P2-debt | agent:ia-consensus
- [ ] Add `eslint-plugin-import` `no-restricted-imports` rule for `MlsWorkerApi` and `CryptoWorkerManager` — PR review is only enforcement for import hierarchy → .tmp/2026-03-20-spa-scaffold/ia-proposals/01-client-context.md | P2-debt | agent:ia-consensus
- [ ] Update LiveView PO entry "This device has been removed" to match SPA copy — copy divergence between LiveView and SPA creates inconsistent UX → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P2-debt | agent:ia-consensus
- [ ] Add grep-based SPA copy discipline lint rule to `./run lint:all` — brand rules have no carry-forward into Paraglide catalogs → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P2-debt | agent:ia-consensus
- [ ] Add JA locale file header comment template for product noun discipline — contributors need the rule visible → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P2-debt | agent:ia-consensus
- [ ] Add telemetry event `[:famichat, :system_channel, :session_terminated]` — revocation delivery has no monitoring → .tmp/2026-03-20-spa-scaffold/ia-proposals/03-channel-api.md | P2-debt | agent:ia-consensus
- [ ] Add PR template checklist item for copy review on translation-touching PRs — lint can't catch tonally wrong strings → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P2-debt | agent:ia-consensus
- [ ] Document platform detection constraint: no user-visible string may reference platform names — platform names will leak into copy without explicit constraint → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | P2-debt | agent:ia-consensus
- [ ] Create SPA copy inventory: enumerate ~40 new EN/JA strings against brand-positioning.md — lint rules enforce nothing without content → .tmp/2026-03-20-spa-readiness/round-1/02-ux.md | P2-debt | agent:spa-readiness
- [ ] Design degraded-state UX patterns (WASM failure, IndexedDB loss, worker crash, private browsing) — ADR 012 behavioral specs have no interaction designs → .tmp/2026-03-20-spa-readiness/round-1/02-ux.md | P2-debt | agent:spa-readiness
- [ ] Design "syncing messages" first-open intermediate state for SPA conversation list — first-open shows empty list during delta sync with no feedback → .tmp/2026-03-20-spa-readiness/round-1/02-ux.md | P2-debt | agent:spa-readiness
- [ ] Narrow `Famichat.Crypto.MLS` from `exports: :all` to explicit export list — only major boundary not tightened during enforcement work → .tmp/2026-03-20-spa-readiness/round-1/04-ia-ddd.md | P2-debt | agent:spa-readiness
- [ ] Write L1-to-L3 hybrid migration security contract — no doc specifies what happens to NIF-held MLS state during WASM transition → .tmp/2026-03-20-spa-readiness/round-1/03-security.md | P2-debt | agent:spa-readiness

## Someday/maybe (P3)
<!-- Documentation/guidance; infra will change -->
- [ ] Create backup/restore procedures document — encryption key loss is unrecoverable → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P3-idea | agent:consensus
- [ ] Create Cloudflare Tunnel operational walkthrough — instructions end at "point to localhost:8001" → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P3-idea | agent:consensus
- [ ] Create troubleshooting guide for common deployment failures — WebAuthn RP mismatch has no diagnostic docs → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P3-idea | agent:consensus
- [ ] Create update/upgrade runbook with rollback procedures — no version update documentation exists → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P3-idea | agent:consensus
- [ ] Add encryption key management section to operator docs — 4 keys undocumented; loss = permanent data loss → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P3-idea | agent:consensus
- [ ] Document CSP_ADDITIONAL_HOSTS in `.env.production.example` — undocumented env var for CDN config → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P3-idea | agent:consensus
- [ ] Add Watchtower setup instructions for homelab auto-deploy — manual docker pull after every release → .tmp/2026-03-10-delivery-and-deployment/round-3/04-delivery-pipeline.md | P3-idea | agent:consensus
- [ ] Document semver release policy and tag conventions — no release process exists → .tmp/2026-03-10-delivery-and-deployment/round-3/04-delivery-pipeline.md | P3-idea | agent:consensus
- [ ] Document migration backward-compatibility strategy — no rollback guidance for operators → .tmp/2026-03-10-delivery-and-deployment/round-3/04-delivery-pipeline.md | P3-idea | agent:consensus

## Decisions needed
<!-- Need human judgment, not implementation -->
- [ ] Decide: clean error path for browsers without WebAuthn support — no fallback for browsers that can't do passkeys → .tmp/2026-03-08-new-accounts/acceptance/consensus.md §5.4 | agent:consensus
- [ ] Decide: which reverse proxy to recommend for non-Cloudflare self-hosters? (Caddy, Nginx, Traefik) — operators without Cloudflare need TLS termination guidance → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | agent:consensus
- [ ] Decide: release cadence — ad-hoc for dogfood, sprint-aligned for L2+? — determines Watchtower polling and operator expectations → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | agent:consensus
- [ ] Decide: is `POST /api/v1/auth/otp/request` complete or a dead route? — endpoint rejects all parameter shapes; may be incomplete implementation or future-flow placeholder → .tmp/2026-03-16-browser-walkthrough/agent-6-api-basher.md | agent:consensus
- [ ] Decide: does WebAuthn ceremony hang reproduce in a real browser? — CDP virtual authenticator artifact in Playwright; if confirmed in Firefox/Chrome, elevates to P0-dogfood → .tmp/2026-03-16-browser-walkthrough/triage.md | agent:consensus
- [ ] Decide: history backfill depth on first device setup — determines first-open wait time; 10,000 messages = 8.6s decrypt on desktop → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | agent:consensus
- [ ] Decide: same wrapping key for MLS state + messages, or separate HKDF-derived keys? — single key means compromised message cache also exposes signing keys → .tmp/2026-03-19-local-first-storage/round-1/consensus.md | agent:consensus
- [ ] Decide: SPA i18n approach (Paraglide-js 2.0 vs alternative) — no translation system for SPA → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | agent:consensus
- [ ] Decide: SPA CSS strategy (Tailwind 3 vs 4 vs other) — LiveView uses 3.4; SPA may diverge → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | agent:consensus
- [ ] Decide: dev workflow (Vite proxy to Docker Phoenix vs single container) — DX during development → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | agent:consensus
- [ ] Decide: exclude priv/static/app/ from phx.digest or accept double-hashing — Vite already hashes filenames → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | agent:consensus
- [ ] Decide boot endpoint path: `/api/v1/boot` vs `/api/v1/session` vs `/api/v1/context` — path should be chosen before first PR → .tmp/2026-03-20-spa-scaffold/ia-proposals/02-auth-boot.md | agent:ia-consensus
- [ ] Decide session expiry vs device revocation copy distinction — both lead to sign-in page but carry different user expectations → .tmp/2026-03-20-spa-scaffold/ia-proposals/04-copy-brand.md | agent:ia-consensus
- [ ] Decide: session cookie max_age alignment with refresh token TTL (30 days) — browser close kills session but refresh token survives → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | agent:consensus
- [ ] Decide: CSRF protection for SPA API mutations (SameSite=Lax may be sufficient) — security review needed before L2 → .tmp/2026-03-20-spa-scaffold/round-1/consensus.md | agent:consensus
