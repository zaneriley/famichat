# Famichat Backlog

**Last updated:** 2026-03-16

Single prioritized index of every known issue, gap, debt item, and planned work. If it is not in this file, it is not tracked. Agent research, `.tmp/` files, handoff docs — those are source material. Findings get promoted to a one-liner here or they rot.

---

## How items work

Each item is a single line in a checkbox list:

```
- [ ] Short imperative description — why it matters in ≤15 words → path/to/detail.md | severity | source
```

### Fields

- **Checkbox**: `[ ]` = open, `[x]` = done, `[-]` = cut/won't-do (with brief reason inline)
- **Description**: Imperative voice ("Fix X", "Add Y", "Decide Z"). Max ~80 chars for the task itself.
- **Why-clause** (`—`): A dash-separated clause (≤15 words) explaining the user-facing or system consequence if this item is not done. This is what a human reads when deciding whether the item still matters as priorities shift. Required for all new items. If you cannot articulate why it matters, it belongs in "Open Questions" not the backlog.
- **Pointer** (`→`): Relative path from repo root to the file with full detail. Can be a `.tmp/` research file, an ADR, a test file, a source file with a line number. This is how we avoid losing context while keeping the backlog scannable. Omit if the one-liner IS the detail.
- **Severity tag**: One of the following, explained below under "How sections work."
  - `P0-dogfood` — blocks handing the URL to family
  - `P1-confidence` — blocks feeling good about shipping
  - `P2-debt` — known debt, not blocking
  - `P3-idea` — someday/maybe
- **Source tag**: Where the item was identified. Examples: `review:robustness`, `review:ia-ddd`, `audit:auth`, `user-report`, `agent:consensus`, `manual-qa`, `spec-review`

### Pointer conventions

- Relative paths from repo root: `→ .tmp/2026-03-08-new-accounts/07-robustness-error-paths.md`
- Multiple pointers: `→ report-a.md, report-b.md`
- ADRs: `→ docs/decisions/012-spa-wasm-client-architecture.md`
- Source code: `→ backend/lib/famichat/auth/onboarding.ex:198`
- No detail file? Omit the pointer entirely. The one-liner is the detail.
- An LLM needing context reads the pointer. A human clicks it in their IDE.

### Examples

```
- [ ] Remove last_message_preview from API — server can't produce previews under E2EE; migration trap → backend/lib/famichat_web/controllers/api/chat_read_controller.ex:175 | P0-dogfood | spec-review
- [ ] Add message_seq column and migration — cursor pagination and unread counts have no substrate | P0-dogfood | review:robustness
- [x] Wire community_id into existing schemas — multi-family data model has no FK without it → docs/decisions/012-spa-wasm-client-architecture.md | P1-confidence | review:ia-ddd (cd31226)
- [-] Build QR pairing UI — invite link sufficient for L1 | P3-idea | spec-review
```

---

## How sections work

Items are grouped by what they block, not by technical category.

- **Blocks dogfooding (P0)** — Cannot hand the URL to family until these are fixed.
- **Blocks confidence (P1)** — Can dogfood, but these erode trust in the system.
- **Known debt (P2)** — Tracked, not blocking. Will matter at scale or for public launch.
- **Someday/maybe (P3)** — Documentation, guidance, and ideas. Infra will change; don't invest until it stabilizes.
- **Decisions needed** — Items that need human judgment, not implementation. May carry any severity.
- **Cut / Won't do** — Explicitly rejected with a reason. Tracks what we decided NOT to do and why. These stay in the doc permanently.

Items move DOWN in severity (P0 → P1 → P2) as blockers are resolved. Items never move UP without explicit discussion.

---

## How agents use this

- **Triage agent**: After any research round, reads findings and promotes actionable items here as one-liners with pointers back to the source.
- **Implementation agent**: Reads this file to understand what is in scope and what is not.
- **Review agent**: Checks findings against this file to see if an issue is already tracked before flagging it as new.
- **Completion**: When an item is done, check the box. Optionally add a commit hash or PR link inline: `(cd31226)` or `(#42)`.

---

## Relationship to other docs

| Doc | Role | Relationship |
|-----|------|-------------|
| `docs/NOW.md` | What we are working on THIS WEEK | Points to BACKLOG.md items by description |
| `docs/decisions/` | Irreversible architectural choices (ADRs) | BACKLOG.md may point to these as detail files |
| `MEMORY.md` | Claude persistent memory; summarizes completed work | NOT a backlog; does not drive prioritization |
| `.tmp/` | Research artifacts, handoff docs, spike results | BACKLOG.md indexes into these; they are not the source of truth |
| `docs/SPEC.md` | Consolidated design spec | Defines what "done" looks like; BACKLOG.md tracks gaps against it |

---

## Rules

1. One item per line. No multi-line descriptions.
2. If you need more than one sentence, the detail belongs in a pointed-to file.
3. Items move DOWN (P0 → P1 → P2) as blockers resolve. Never up without discussion.
4. "Cut" items stay in the doc permanently with a reason. We track what we decided NOT to do.
5. No orphan pointers: if you delete a `.tmp/` file, update or remove the pointer here.
6. Do not duplicate items. Search before adding. If two items merge, keep one and cut the other with "merged into [description]."

---

## Blocks dogfooding (P0)
<!-- Items here prevent handing the URL to family members -->
- [x] Revoke device on logout in SessionController.delete — stolen refresh token valid for 30 days post-logout → .tmp/2026-03-10-ideation/09-rate-limiting-nat.md | P0-dogfood | agent:consensus
- [x] Reduce name input minimum to 1 char for CJK scripts — ゆき (2 chars) rejected by 3-char minimum; blocks Japanese onboarding → .tmp/2026-03-10-ideation/04-i18n-cjk.md | P0-dogfood | agent:consensus
- [x] Auto-authenticate after passkey registration — double biometric makes new users think registration failed → .tmp/2026-03-09-mlp-ux/consensus.md, .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P0-dogfood | agent:consensus
- [x] Add browser Notification API integration on incoming Channel messages — recipient never knows a message arrived without tab open → .tmp/2026-03-09-mlp-ux/consensus.md, .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P0-dogfood | agent:consensus
- [x] Add .env.production.example with all required env vars documented — server crashes on first passkey without WebAuthn vars → .tmp/2026-03-09-mlp-ux/consensus.md, .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P0-dogfood | agent:consensus (dfd6091)
- [x] Make HomeLive open directly to 1:1 conversation for L1 — conversation list of one item signals "product," not "our space" → .tmp/2026-03-09-mlp-ux/consensus.md, .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P0-dogfood | agent:consensus
- [x] Add warm empty-state copy when conversation has zero messages — blank void causes both users to hesitate on first message → .tmp/2026-03-09-mlp-ux/consensus.md | P0-dogfood | agent:consensus (dfd6091)
- [x] Show clear forward path for consumed-but-incomplete invites — spouse who cancelled passkey mid-flow hits dead end → .tmp/2026-03-09-mlp-ux/consensus.md | P0-dogfood | agent:consensus (dfd6091)
- [x] Persist user_locale to users table, resolve on mount — bilingual spouse loses language setting on every reconnect → .tmp/2026-03-09-mlp-ux/consensus.md | P0-dogfood | agent:consensus (dfd6091)
- [x] Fix `conversation_type` hardcode to `"family"` in HomeLive — all L1 messaging broken; channel join fails for `:direct` conversations → .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P0-dogfood | agent:consensus
- [x] Remove `push_navigate` from HomeLive `member_joined` handler — member join causes full page flash and discards socket state → .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P0-dogfood | agent:consensus
- [x] Forward `sender_name` through hook pushEvent to LiveView — chat bubbles show "Family Member" instead of partner's name → .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P0-dogfood | agent:consensus
- [x] Move `UNIQUE_CONVERSATION_KEY_SALT` to runtime.exs for fail-fast — server starts but crashes on first conversation creation → .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P0-dogfood | agent:consensus
- [x] Complete ~30 missing Japanese gettext translations — half-translated screens block Japanese-speaking spouse adoption → .tmp/2026-03-09-mlp-ux/consensus.md, .tmp/2026-03-09-bug-bash/05-japanese-user.md | P0-dogfood | agent:consensus (dfd6091)
- [x] Fix @legacy_kind_map to match DB constraint — `"passkey_reg"` rejected by `user_tokens_kind_check`; ALL auth flows crash → backend/lib/famichat/auth/tokens/policy.ex:192 | P0-dogfood | browser-walkthrough (90b0d5b)
- [x] Wrap user+token creation in Ecto.Multi transaction — partial user creation leaves app unrecoverable without DB intervention → backend/lib/famichat/auth/onboarding.ex | P0-dogfood | browser-walkthrough (90b0d5b)
- [x] Add :not_found_html clause to FallbackController.call/2 — valid-locale 404s return 500 with stacktrace in dev, bare 500 in prod → backend/lib/famichat_web/controllers/fallback_controller.ex | P0-dogfood | browser-walkthrough (90b0d5b)
- [x] Fix PutRemoteIp to parse X-Forwarded-For — all visitors share one rate-limit bucket behind any proxy → .tmp/2026-03-08-new-accounts/07-robustness-error-paths.md | P0-dogfood | agent:consensus (95eb458)
- [x] Fix setup_token lost on FamilyNewLive WebSocket reconnect — mobile users lose family setup mid-flow → .tmp/2026-03-08-new-accounts/07-robustness-error-paths.md | P0-dogfood | agent:consensus (95eb458 — architecture split: FamilyNewLive → redirect → FamilySetupLive with token in URL)
- [x] Add validate_length(:name, max: 100) to Family.changeset — unbounded input reaches DB without constraint → backend/lib/famichat/chat/family.ex:33 | P0-dogfood | agent:consensus (76776e4)
- [x] Remove last_message_preview from API — server can't produce previews under E2EE; active spec violation → backend/lib/famichat_web/controllers/api/chat_read_controller.ex | P0-dogfood | spec-review (verified removed: grep returns 0 matches for last_message_preview in chat_read_controller.ex)
- [x] Fix FamilySetupLive auth bounce — /families/start/:token requires session but creates the first user; flow is broken → .tmp/2026-03-09-bug-bash/00-triage-by-cuj.md §CUJ4 | P0-dogfood | bug-bash (76776e4)
- [x] Fix LiveView locale redirect — setup_common_assigns falls back to default locale, making /ja/* unusable → backend/lib/famichat_web/live/live_helpers.ex | P0-dogfood | bug-bash (76776e4)
- [x] Fix blank family name "already taken" error — empty submit collides with default "My Family"; misleading → .tmp/2026-03-09-bug-bash/02-non-tech-family-member.md BUG-02 | P0-dogfood | bug-bash (76776e4)
- [x] Constrain :locale route param to known locales — /:locale catch-all swallows API routes, returns 200 HTML → backend/lib/famichat_web/router.ex:241 | P0-dogfood | bug-bash (76776e4)
- [x] Remove `pull_repository()` call and dead content-repo code from `docker-entrypoint-web` — container crashes on every production startup → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P0-dogfood | agent:consensus
- [x] Remove `config :famichat, :cache, disabled: true` from prod.exs — all rate limits silently unenforced in production → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P0-dogfood | agent:consensus
- [x] Fix CORS: remove CORSPlug for L1 or make origin configurable via env var — hardcoded localhost blocks browser requests from production domain → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P0-dogfood | agent:consensus
- [x] Fix Dockerfile `../run` → `/app/run` on line 36 — Docker build fails on asset compilation; operator cannot deploy → .tmp/2026-03-14-deploy-scan/ci-github.md | P0-dogfood | agent:deploy-scan (8fd6ead)
- [-] Auto-create 1:1 conversation when second family member joins — false positive: `schedule_direct_conversation_creation` already exists in onboarding.ex:1293 and is called from `complete_registration` at line 541 → backend/lib/famichat/auth/onboarding.ex:1293 | agent:deploy-scan
- [x] Fix LiveView crash on "Generate invite link" in setup post-passkey step — first-run admin cannot issue invite from setup; must navigate away → .tmp/2026-03-16-browser-walkthrough/agent-1-bootstrap.md | P0-dogfood | browser-walkthrough-2026-03-16 (root: mount_connected redirected to /login on WS reconnect after passkey; fixed with fetch_admin_awaiting_first_invite/0 + locale_path render fix; 10 new tests)
- [-] Gate session creation in `invites/complete` behind passkey completion — Playwright artifact: complete_invite never issues a session cookie; session is only created in passkey_register after WebAuthn completes; verified in auth_controller.ex | P0-dogfood | browser-walkthrough-2026-03-16
- [ ] Pending-user-before-passkey architectural gap — :pending user exists between complete_invite and passkey_register; find_or_create_pending_user makes this idempotent so token reuse is blocked, but user record without credential is debt → .tmp/2026-03-16-browser-walkthrough/agent-2-invite-flow.md | P2-debt | browser-walkthrough-2026-03-16
- [x] Add community-admin role check to CommunityAdminLive (`/en/admin`) — any authenticated user can view all families and generate setup links → .tmp/2026-03-16-browser-walkthrough/agent-3-family-creation.md | P0-dogfood | browser-walkthrough-2026-03-16 (added community_admin boolean to users; migration 20260316120000; assert_community_admin checks community_admin==true AND status==:active)
- [-] Remove or gate "Admin Controls" (Revoke/Reset Security State) in HomeLive for non-admin users — HomeLive gates this accordion on @dev_mode (not @is_admin); hidden in production by design; verified in home_live.html.heex | P0-dogfood | browser-walkthrough-2026-03-16
- [x] Add `validate_length` on username in `User.changeset` at all entry points (setup, invite, family-start) — 206-char username accepted and persisted throughout session → .tmp/2026-03-16-browser-walkthrough/agent-1-bootstrap.md | P0-dogfood | browser-walkthrough-2026-03-16 (validate_bootstrap_username now rejects >50 chars; SetupLive handles :username_too_long with clear error message)

## Blocks confidence (P1)
<!-- Can dogfood, but these make us nervous -->
- [x] Add OrphanFamilyReaper — memberless families accumulate after abandoned setup attempts → .tmp/2026-03-08-new-accounts/07-robustness-error-paths.md | P1-confidence | agent:consensus (1b02ab3)
- [x] Add TokenReaper for expired/consumed tokens — token table grows unbounded → .tmp/2026-03-08-new-accounts/07-robustness-error-paths.md | P1-confidence | agent:consensus (1b02ab3)
- [x] Normalize error tags (:retryable → :recoverable) — inconsistent atoms across auth LiveViews → .tmp/2026-03-08-new-accounts/acceptance/consensus.md | P1-confidence | agent:consensus (76776e4)
- [x] Add rate limit to reissue_passkey_token/1 — unlimited token reissue is a brute-force vector → backend/lib/famichat/auth/onboarding.ex:586 | P1-confidence | agent:consensus (1b02ab3)
- [-] Add copy alignment: privacy line, empty-state forward path — privacy line already exists in both templates (peer-reviewed); empty-state tracked at P0 → .tmp/2026-03-10-ideation/consensus.md | agent:consensus
- [x] Fix green CTA button contrast ratio (2.38:1 → 4.5:1) — primary buttons unreadable for vision-impaired users → .tmp/2026-03-09-bug-bash/03-grandparent-user.md A11Y-01 | P1-confidence | bug-bash
- [x] Add visible error feedback when passkey auth fails — button silently reverts with no message → .tmp/2026-03-09-bug-bash/01-community-admin.md BUG-04 | P1-confidence | bug-bash (1b02ab3 — confirmed already working: full hook→LiveView→template error chain wired in auth security fixes)
- [x] Increase "Getting started?" text from 12.5px to ≥16px — critical guidance invisible to older users → .tmp/2026-03-09-bug-bash/03-grandparent-user.md A11Y-02 | P1-confidence | bug-bash
- [x] Fix skip-to-content target — #main-content ID missing from main tag → backend/lib/famichat_web/components/layouts/app.html.heex | P1-confidence | bug-bash
- [x] Rewrite 410 error page to match brand voice — ALL-CAPS terminal aesthetic terrifies non-tech users → backend/lib/famichat_web/controllers/error_html/410.html.heex | P1-confidence | bug-bash
- [x] Disable HEEx debug annotations in prod — 85 HTML comments leak internal file paths → backend/config/prod.exs | P1-confidence | bug-bash (76776e4)
- [x] Switch CSP from report-only to enforcing; remove unsafe-eval — zero XSS protection currently → .tmp/2026-03-09-bug-bash/04-security-tester.md SEC-02 | P1-confidence | bug-bash (76776e4)
- [-] Add ~30 missing Japanese gettext translations — merged into P0 item (user decision: P0-dogfood) → .tmp/2026-03-09-bug-bash/05-japanese-user.md | P1-confidence | bug-bash
- [x] Fix flash-group div intercepting pointer events on header nav — error banner makes home link and language switcher unclickable | P1-confidence | browser-walkthrough (90b0d5b)
- [x] Add LiveView mount crash fallback — perpetual "Getting things ready..." with no timeout or actionable error | P1-confidence | browser-walkthrough (90b0d5b)
- [-] Fix duplicate "Skip to main content" links on 404 error page — merged into "Fix 404/410 templates to content-only" | P1-confidence | browser-walkthrough
- [x] Prompt operator to leave welcome message after invite generation — invitee lands in empty room instead of warm handoff → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus
- [x] Auto-navigate operator to conversation when invitee completes registration — operator has no feedback loop after sending invite → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus
- [x] Show one-time "no read receipts" contextual note on first message — Japanese users interpret missing kidoku as bug, not feature → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus (1b02ab3)
- [-] Reduce name input minimum to 1 char for CJK scripts — UPGRADED to P0-dogfood; done in P0 section → .tmp/2026-03-10-ideation/04-i18n-cjk.md | agent:consensus
- [x] Fix 2 Japanese brand voice violations (管理者 in community_admin_live.ex) — role labels alienate the non-technical Japanese spouse → .tmp/2026-03-10-ideation/04-i18n-cjk.md | P1-confidence | agent:consensus
- [x] Escalate passkey error copy after 3+ repeated failures — repeated "try again" trains users to give up → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus (1b02ab3)
- [x] Demote "Set up your own family space" button to text link on login page — non-technical users tap wrong button and enter orphan flow → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus
- [x] Show social recovery guidance after 2-3 failed passkey attempts — user with lost credential has no forward path → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus (1b02ab3 — shows after 3+ failures via error_count in LoginLive)
- [x] Set browser tab title to partner name or family name — brand name in tab misses chance to reinforce "our space" → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus (1b02ab3 — already working for conversations; added family.name for empty-state branch)
- [x] Fix `Mix.env()` in application.ex — release builds crash on boot → .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P1-confidence | agent:consensus
- [x] Add prod guard for POSTGRES_PASSWORD in runtime.exs — default "password" gives no error if forgotten in prod → .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P1-confidence | agent:consensus (dfd6091)
- [x] Fix 404/410 templates to content-only — 3-for-1: resolves duplicate LiveSocket, duplicate skip links, and locale-awareness → .tmp/2026-03-10-ideation/07-routing-locale.md | P1-confidence | agent:consensus
- [x] Add rate limiting to discoverable passkey assert/challenge endpoint — unauthenticated endpoint has no DoS protection → .tmp/2026-03-10-ideation/08-test-infrastructure.md | P1-confidence | agent:consensus
- [x] Raise family creation rate limit from 3 to 10/IP/hour — same-household devices collide at 3/hr behind NAT → .tmp/2026-03-10-ideation/09-rate-limiting-nat.md | P1-confidence | agent:consensus
- [x] Add `secure: true` to session cookie options for production — session cookie leaks over HTTP without Secure flag → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Remove LiveDashboard RequestLogger plug from production — debug plug processes query param in every prod request → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Remove `localhost`/`0.0.0.0` from CSP hosts in production — CSP allows script loading from localhost → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Restrict CSP `connect-src` to specific WebSocket URL, not bare `ws:/wss:` — XSS payload could exfiltrate via WebSocket to any host → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Add explicit `check_origin` for production WebSocket connections — cross-origin hijacking possible; tunnel may cause failures → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Fix `release-please.yml` Docker build context to `backend/` — CI release builds fail with repo-root context → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Add NIF load verification step to Dockerfile after `mix release` — silent NIF failure crashes release on first MLS operation → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Add web healthcheck to `docker-compose.production.yml` — no restart if app crashes after postgres healthy → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Update stale WebAuthn compile-time warnings in `.env.production.example` — operator wastes time on non-issue during deploy → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Change Docker Compose port default to `127.0.0.1` — forgotten env var exposes service on all interfaces → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Add build args and `POSTGRES_DB` to production compose — fragile defaults cause silent failures → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Add `restart: unless-stopped` to production compose services — services don't recover after homelab reboot → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Document WebAuthn/URL variable relationships with decision tree in `.env.production.example` — passkeys silently fail if RP_ID doesn't match domain → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P1-confidence | agent:consensus
- [x] Fix env_file reference to `.env.production` in compose file — first `docker compose up` fails with missing-file error → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P1-confidence | agent:consensus
- [x] Replace misleading pg_dump comment with setup instructions in compose — operators think they must dump nonexistent database → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P1-confidence | agent:consensus
- [x] Add POSTGRES_PASSWORD generation command to `.env.production.example` — no guidance; operator may use weak password → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P1-confidence | agent:consensus
- [x] Simplify compose healthcheck to CMD array form — nested variable interpolation fails silently if PORT misconfigured → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P1-confidence | agent:consensus
- [x] Add Docker build validation step to CI (build without push) — broken Dockerfile merges undetected → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P1-confidence | agent:consensus
- [x] Document FAMICHAT_MLS_ENFORCEMENT in `.env.production.example` — operator cannot discover MLS enforcement toggle → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P1-confidence | agent:consensus
- [x] Add warm error messages to `runtime.exs` for all missing env vars — raw RuntimeError gives no diagnostic path → .tmp/2026-03-10-delivery-and-deployment/round-3/05-config-ux.md, .tmp/2026-03-11-config-ux/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Add SECRET_KEY_BASE length guard (>= 64 chars) to runtime.exs — short key silently weakens session cookie signatures → .tmp/2026-03-11-config-ux/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Add WEBAUTHN_ORIGIN https:// scheme warning to runtime.exs — http:// origin causes opaque passkey failure with no server-side diagnostic → .tmp/2026-03-11-config-ux/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Batch missing-required-var errors into single raise in runtime.exs — operator restarts container 12 times fixing one var at a time → .tmp/2026-03-11-config-ux/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Fix empty POSTGRES_PASSWORD bypass in runtime.exs (`{:prod, ""}` guard) — operator with unset password gets running system with empty DB password → .tmp/2026-03-11-compose-and-env/round-1/consensus.md | P1-confidence | agent:consensus
- [x] Register `Clipboard` LiveView hook in `app.js` — all "Copy link" buttons broken sitewide; console error: unknown hook "Clipboard" → .tmp/2026-03-16-browser-walkthrough/agent-3-family-creation.md | P1-confidence | browser-walkthrough-2026-03-16 (root: community_admin_live used phx-hook="Clipboard" instead of "CopyToClipboard"; fixed hook name + data attr; c32ff93)
- [x] Add clipboard write confirmation ("Copied!") to all copy buttons — no visual feedback; user cannot tell if copy succeeded → .tmp/2026-03-16-browser-walkthrough/agent-1-bootstrap.md | P1-confidence | browser-walkthrough-2026-03-16 (setup_live + home_live already had it; added to community_admin_live; c32ff93)
- [x] Deduplicate invite token generation; show existing-token state on panel — each click mints a new 72-hr token with no warning about prior valid tokens → .tmp/2026-03-16-browser-walkthrough/agent-2-invite-flow.md | P1-confidence | browser-walkthrough-2026-03-16 (revoke prior tokens via update_all before minting in issue_family_setup_link_for_existing_family/2; 1ffb97e)
- [x] Add success feedback to "Save message" welcome prompt button — dismisses silently; operator cannot confirm message was saved → .tmp/2026-03-16-browser-walkthrough/agent-2-invite-flow.md | P1-confidence | browser-walkthrough-2026-03-16 (welcome_saved assign + 2s auto-reset + aria-live region; 1ffb97e)
- [x] Translate browser `<title>` on invite error page to current locale — tab title shows English "Invite not valid" when page body is Japanese → .tmp/2026-03-16-browser-walkthrough/agent-4-locale-errors.md | P1-confidence | browser-walkthrough-2026-03-16 (wrapped assign_page_metadata in gettext(); added JA translation; 1ffb97e)
- [-] Preserve locale prefix on authenticated post-login redirects — Playwright tab artifact: all 14 redirect sites verified to use locale_path correctly; agent was reading URL of pre-existing /en/admin tab → .tmp/2026-03-16-browser-walkthrough/agent-4-locale-errors.md | P1-confidence | browser-walkthrough-2026-03-16
- [x] Fix duplicate paragraph on invite error page — h1 text repeated verbatim as `<p>`; raw fallback message leaking into template → .tmp/2026-03-16-browser-walkthrough/agent-4-locale-errors.md | P1-confidence | browser-walkthrough-2026-03-16 (removed redundant error_message(<p>) from :invalid step; 1ffb97e)
- [x] Fix unstyled bare-HTML 404 for `/en/families/start/<invalid-token>` — no CSS or app chrome; completely different treatment from all other error pages → .tmp/2026-03-16-browser-walkthrough/agent-4-locale-errors.md | P1-confidence | browser-walkthrough-2026-03-16 (root: put_root_layout(false) in validate_family_setup_token.ex + validate_invite_token.ex; removed from both halt_with/2)
- [x] Add "Go back" to passkey step in `FamilySetupLive` — user trapped with no escape if ceremony hangs; `InviteLive` has this, `FamilySetupLive` does not → .tmp/2026-03-16-browser-walkthrough/agent-5-link-basher.md | P1-confidence | browser-walkthrough-2026-03-16 (go-back handler returns to :register step; button in both happy-path and fatal-error branches; 1ffb97e)
- [x] Translate "Invite a family member" button label in Japanese locale — sole untranslated string on home page when `/ja/` active → .tmp/2026-03-16-browser-walkthrough/agent-1-bootstrap.md | P1-confidence | browser-walkthrough-2026-03-16 (家族を招待する; 1ffb97e)
- [x] Show specific error on duplicate family name in `/en/admin` add-family form — generic "Something went wrong" gives operator no actionable guidance → .tmp/2026-03-16-browser-walkthrough/agent-5-link-basher.md | P1-confidence | browser-walkthrough-2026-03-16 ("A family with that name already exists." via :family_name_taken atom + Changeset error check; 1ffb97e)
- [x] Fix `TypeError: Cannot read properties of undefined (reading 'size')` on `/admin/message` load — fires on mount before user interaction; breaks all JS on the page → .tmp/2026-03-16-browser-walkthrough/agent-5-link-basher.md | P1-confidence | browser-walkthrough-2026-03-16 (deleted debug <script> block accessing window.liveSocket.connectors.size; c32ff93)

## Known debt (P2)
<!-- Tracked, not blocking, will matter at scale or for public launch -->
- [ ] Create `./run config:generate` interactive wizard that generates `.env.production` — operator must manually configure 15+ vars with no guidance; deferred from P1: targets non-developer operator who doesn't exist at L1 → .tmp/2026-03-10-delivery-and-deployment/round-3/05-config-ux.md, .tmp/2026-03-11-config-ux/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Create `./run config:check` pre-flight validation script — overlaps 70% with warm errors; deferred from P1 → .tmp/2026-03-10-delivery-and-deployment/round-3/05-config-ux.md, .tmp/2026-03-11-config-ux/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Add secret rotation reference to `.env.production.example` — operator who changes vault key loses all data with zero warning → .tmp/2026-03-11-config-ux/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Add visible focus indicators on interactive elements — WCAG 2.4.7 violation; outline-style is none → .tmp/2026-03-09-bug-bash/03-grandparent-user.md A11Y-05 | P2-debt | bug-bash
- [ ] Remove or populate empty footer landmark — screen readers announce empty contentinfo region → .tmp/2026-03-09-bug-bash/01-community-admin.md BUG-05 | P2-debt | bug-bash
- [ ] Add aria-live region for passkey button state changes — loading/error invisible to screen readers | P2-debt | bug-bash
- [x] Add HSTS header for production HTTPS deployments | P2-debt | bug-bash (76776e4)
- [x] Gate console.log output behind dev flag — LiveSocket config leaks to browser console | P2-debt | bug-bash (76776e4)
- [x] Fix 410 page hardcoded lang="en" — CJK font overrides won't apply → backend/lib/famichat_web/controllers/error_html/410.html.heex | P2-debt | bug-bash (90b0d5b)
- [x] Root / should respect Accept-Language header for locale redirect | P2-debt | bug-bash (dfd6091 — RootRedirectController now checks session locale → DB locale → Accept-Language)
- [x] Make 404 page locale-aware and fix hardcoded /en/ in RETURN TO HOME link — Japanese users see English-only 404 | P2-debt | browser-walkthrough (90b0d5b)
- [-] Fix duplicate LiveSocket initialization on 404 page — merged into "Fix 404/410 templates to content-only" | P2-debt | browser-walkthrough
- [ ] Render time gaps as human-readable labels instead of date separators — cold separators make silence feel like neglect → .tmp/2026-03-09-mlp-ux/consensus.md | P2-debt | agent:consensus
- [ ] Replace technical session-expired copy with warm brand-aligned version — "re-authenticate" breaks the family-space feeling → .tmp/2026-03-09-mlp-ux/consensus.md | P2-debt | agent:consensus
- [-] Make locale-aware placeholder examples consistent across all inputs — already localized correctly (鈴木家, お母さん); verified by ideation agent 04 → .tmp/2026-03-10-ideation/04-i18n-cjk.md | agent:consensus
- [-] Make invite error copy available in all supported locales — all error_message/1 strings already have Japanese translations; verified by ideation agent 04 → .tmp/2026-03-10-ideation/04-i18n-cjk.md | agent:consensus
- [x] Move CSP plug env var reads to Application.get_env — per-request System.get_env diverges from runtime.exs values → .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P2-debt | agent:consensus (dfd6091)
- [ ] Add photo sharing for 1:1 conversations — half of couple communication is visual; punted to next cycle → .tmp/2026-03-09-mlp-ux/consensus.md | P2-debt | agent:consensus
- [x] Remove Playwright from Docker assets stage — 300MB+ browser binaries add 5-10 min to build → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Strip unnecessary packages from prod Dockerfile stage — 100MB+ build tools in prod image → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P2-debt | agent:consensus
- [x] Remove dead `github_webhook` dep from mix.exs and config.exs — dead dependency inflates compile surface → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P2-debt | agent:consensus (8fd6ead)
- [x] Remove dead content-repo env vars from `.env.production.example` — operators confused by irrelevant config → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Remove `/api/v1/hello` route and HelloController — dev artifact in production API → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Establish green CI baseline with `--exclude` tags for known-broken tests — red CI masks new regressions → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Add Docker image smoke test to CI pipeline — broken Dockerfile only discovered after release → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | P2-debt | agent:consensus
- [ ] Update README.md with "For Self-Hosters" link to deployment guide — no path from README to deploy → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P2-debt | agent:consensus
- [x] Remove unused COMPOSE_PROFILES from `.env.production.example` — set but unused; confuses operators → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P2-debt | agent:consensus
- [ ] Remove unused CONTENT_REPO_URL and GITHUB_WEBHOOK_SECRET from dev `.env` — cargo-culted from prior project → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P2-debt | agent:consensus
- [ ] Add Docker image name to compose file — orphaned images accumulate after rebuilds → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P2-debt | agent:consensus
- [ ] Add resource limits to docker-compose.production.yml — Erlang VM can consume all homelab RAM → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P2-debt | agent:consensus
- [ ] Add logging configuration to docker-compose.production.yml — no log rotation; logs fill disk → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | P2-debt | agent:consensus
- [ ] Add CSP report-uri logging endpoint for operator-visible violation diagnostics — CSP violations invisible without DevTools; operators can't diagnose from docker logs → .tmp/2026-03-11-security-config/round-1/consensus.md | P2-debt | agent:consensus
- [x] Remove dead CSP_SCHEME/CSP_HOST/CSP_PORT from `.env.production.example` — unused since CSP derives from endpoint config; creates false confidence → .tmp/2026-03-11-compose-and-env/round-1/consensus.md | P2-debt | agent:consensus
- [x] Move or delete `backend/.github/workflows/ci.yml` — dead workflow never executed by GitHub Actions; full test suite not running in CI → .tmp/2026-03-14-deploy-scan/ci-github.md | P2-debt | agent:deploy-scan (8fd6ead)
- [x] Remove `excoveralls` dep from mix.exs — no Coveralls integration exists; dead dependency inflates compile → .tmp/2026-03-14-deploy-scan/ci-github.md | P2-debt | agent:deploy-scan (8fd6ead)
- [x] Remove dead modules (TestBroadcastController, ThemeSwitcher, ast_renderer.ex, Authenticators shim) — orphaned code with zero references | P2-debt | agent:deploy-scan (8fd6ead)
- [x] Remove ThemeSwitcherHook import from app.js — references nonexistent JS file | P2-debt | agent:deploy-scan (8fd6ead)
- [x] Remove dead Content module config from config.exs, dev.exs, prod.exs, test.exs — ghost config for deleted modules | P2-debt | agent:deploy-scan (8fd6ead)
- [ ] Document optional env vars (URL_STATIC_HOST, DNS_CLUSTER_QUERY, POSTGRES_POOL) in .env.production.example — operators can't discover tuning options → .tmp/2026-03-14-deploy-scan/env-config.md | P2-debt | agent:deploy-scan
- [ ] Fix "Test Family family." redundant suffix in families/start heading — template appends "family." unconditionally; collides when name already contains "Family" → .tmp/2026-03-16-browser-walkthrough/agent-3-family-creation.md | P2-debt | browser-walkthrough-2026-03-16
- [ ] Fix "Resend setup link" button overflowing card boundary in `/en/admin` — button clipped outside viewport on long family names → .tmp/2026-03-16-browser-walkthrough/agent-3-family-creation.md | P2-debt | browser-walkthrough-2026-03-16
- [ ] Fix `/api/` and `/api` bare paths returning HTML 404 — falls through to browser catch-all; violates contract that `/api/*` never returns HTML → .tmp/2026-03-16-browser-walkthrough/agent-6-api-basher.md | P2-debt | browser-walkthrough-2026-03-16
- [ ] Fix "Famichat home" header link from `/en/admin` dropping authenticated session — click causes LiveView disconnect and redirects to login → .tmp/2026-03-16-browser-walkthrough/agent-5-link-basher.md | P2-debt | browser-walkthrough-2026-03-16
- [x] Fix Type dropdown in `/admin/message` resetting to "self" when Encrypt Messages toggled — unrelated controls share state; dropdown reverts on checkbox change → .tmp/2026-03-16-browser-walkthrough/agent-5-link-basher.md | P2-debt | browser-walkthrough-2026-03-16 (added selected={} to each <option>; c32ff93)
- [x] Fix `TypeError: null.getAttribute` crash in LiveView pushInput on `/admin/message` Type change — changing dropdown triggers JS crash after mount error → .tmp/2026-03-16-browser-walkthrough/agent-5-link-basher.md | P2-debt | browser-walkthrough-2026-03-16 (wrapped <select> in <form phx-change=...>, added name="value"; c32ff93)
- [-] Confirm `Plug.Debugger` / `debug_errors: true` absent in production config — already dev-only; `debug_errors: true` exists only in dev.exs; prod.exs and runtime.exs do not set it; Plug.Debugger is not included in any endpoint config → .tmp/2026-03-16-browser-walkthrough/agent-6-api-basher.md | P2-debt | browser-walkthrough-2026-03-16
- [ ] Normalize 401 error codes across auth endpoints — plug-level returns `"unauthorized"`, controller-level returns `"invalid_token"`; inconsistent API contract → .tmp/2026-03-16-browser-walkthrough/agent-6-api-basher.md | P2-debt | browser-walkthrough-2026-03-16
- [ ] Harden maybe_put_locale in auth_controller.ex to not overwrite URL-derived session locale — DB locale written on passkey auth could race URL locale; corrected on next page load but inconsistent with locale system → backend/lib/famichat_web/controllers/auth_controller.ex | P2-debt | agent:locale-audit
- [ ] Replace manual "/#{locale}/login" string in live_helpers.ex:86 with locale_path — inconsistent with all other redirect sites; will drift if path structure changes → backend/lib/famichat_web/live/live_helpers.ex | P2-debt | agent:locale-audit

## Someday/maybe (P3)
<!-- Documentation and guidance items — infra will change; don't invest in docs until it stabilizes -->
- [x] Create self-hosting docs folder (`docs/self-hosting/`) — deployment knowledge scattered across 4+ files → docs/self-hosting/security-defaults.md | P3-idea | agent:consensus (a85c2bd)
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
- [x] Decide: should self_service_enabled default to true for dogfood? — RESOLVED: yes; rate limit raised to 10/IP/hr; button demoted to text link → .tmp/2026-03-10-ideation/consensus.md | agent:consensus
- [x] Decide: rate limit threshold behind NAT (3/hr may collide for same-household devices) — RESOLVED: raise to 10/IP/hr → .tmp/2026-03-10-ideation/consensus.md | agent:consensus
- [x] Decide: accept double-biometric (register then sign-in) or auto-authenticate? — RESOLVED: auto-authenticate; 5/8 consensus angles agreed, user confirmed → .tmp/2026-03-09-mlp-ux/consensus.md | agent:consensus
- [ ] Decide: clean error path for browsers without WebAuthn support — no fallback for browsers that can't do passkeys → .tmp/2026-03-08-new-accounts/acceptance/consensus.md §5.4 | agent:consensus
- [x] Decide: Japanese translations for new gettext strings — RESOLVED: P0 blocking; user decision: must-have for Japanese-speaking spouse → .tmp/2026-03-09-mlp-ux/consensus.md | agent:consensus
- [x] Decide: clean up 66 pre-existing test failures as prerequisite or separate workstream? — RESOLVED: separate workstream; 3 mechanical root causes, zero hidden bugs → .tmp/2026-03-10-ideation/consensus.md | agent:consensus
- [x] Decide: is unauthenticated POST /api/v1/auth/passkeys/assert/challenge intentional? — RESOLVED: yes, WebAuthn discoverable credential spec; add rate limiting → .tmp/2026-03-10-ideation/consensus.md | agent:consensus
- [x] Decide: extend invite link TTL beyond 10 minutes for L1 dogfood? — RESOLVED: 72 hours; user decision; SPEC.md updated → .tmp/2026-03-09-mlp-ux/consensus.md | agent:consensus
- [x] Decide: is photo sharing required for 2-week dogfood? — RESOLVED: no; punt to next cycle; tracked as P2-debt → .tmp/2026-03-09-mlp-ux/consensus.md | agent:consensus
- [x] Decide: add "thinking of you" one-tap message? — RESOLVED: no; user decision: that's just a poke/like → .tmp/2026-03-09-mlp-ux/consensus.md | agent:consensus
- [x] Decide: reduce refresh token TTL from 30 to 7 days? — DEFERRED to L2: 30 days correct for dogfood; 7-day TTL adds auth friction with no security gain (revocation is device-level, not TTL-level) → .tmp/2026-03-10-ideation/09-rate-limiting-nat.md | agent:consensus
- [x] Decide: deployment strategy for L1 dogfood — RESOLVED: homelab + Docker Compose + Cloudflare Tunnel; dogfoods operator self-hosting experience; captures friction for future documentation | agent:consensus
- [x] Decide: remove `cache: disabled: true` entirely from prod.exs, not decouple rate limiting — RESOLVED: `Famichat.Cache` is only backing auth rate limiting, so preserving the dead flag adds coupling without user value → .tmp/2026-03-10-delivery-and-deployment/round-1/consensus.md | agent:consensus
- [ ] Decide: which reverse proxy to recommend for non-Cloudflare self-hosters? (Caddy, Nginx, Traefik) — operators without Cloudflare need TLS termination guidance → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | agent:consensus
- [ ] Decide: release cadence — ad-hoc for dogfood, sprint-aligned for L2+? — determines Watchtower polling and operator expectations → .tmp/2026-03-10-delivery-and-deployment/final-consensus.md | agent:consensus
- [ ] Decide: is `POST /api/v1/auth/otp/request` complete or a dead route? — endpoint rejects all parameter shapes; may be incomplete implementation or future-flow placeholder → .tmp/2026-03-16-browser-walkthrough/agent-6-api-basher.md | agent:consensus
- [ ] Decide: does WebAuthn ceremony hang reproduce in a real browser? — CDP virtual authenticator artifact in Playwright; if confirmed in Firefox/Chrome, elevates to P0-dogfood → .tmp/2026-03-16-browser-walkthrough/triage.md | agent:consensus
- [x] Decide: should `./run setup` prompt for optional customizations or keep minimal? — RESOLVED: no new surface; warm errors in runtime.exs only for L1; wizard/check-config deferred to P2 → .tmp/2026-03-11-config-ux/round-1/consensus.md | agent:consensus

## Cut / Won't do
<!-- Explicitly rejected — reason noted inline on each item -->
- [-] Bounded context refactor (Onboarding → Chat.create_family) — harmless violation in throwaway code; SPA will replace | agent:consensus
- [-] LiveView deduplication (merge FamilyNewLive into FamilySetupLive) — zero user value; throwaway code per SPEC | agent:consensus
- [-] PasskeyCeremony helper extraction — duplication is real but code is throwaway | agent:consensus
- [-] Doc updates (guardrails, lexicon, SPEC deep update) — deferred until post-dogfood stabilization | agent:consensus
- [-] QR pairing UI — invite link sufficient for L1 | spec-review
- [-] "Thinking of you" one-tap message button — user decision: that's just a poke/like; clutters minimal interface | agent:consensus
- [-] Static /help page — user decision: the operator IS the help desk; no self-service recovery page needed at L1 | agent:consensus
- [-] Letters at L1 — consensus: defer entirely; validate daily text use first; revisit at L2+ | agent:consensus
