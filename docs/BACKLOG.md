# Famichat Backlog

**Last updated:** 2026-03-10

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

## Blocks confidence (P1)
<!-- Can dogfood, but these make us nervous -->
- [ ] Add OrphanFamilyReaper — memberless families accumulate after abandoned setup attempts → .tmp/2026-03-08-new-accounts/07-robustness-error-paths.md | P1-confidence | agent:consensus
- [ ] Add TokenReaper for expired/consumed tokens — token table grows unbounded → .tmp/2026-03-08-new-accounts/07-robustness-error-paths.md | P1-confidence | agent:consensus
- [x] Normalize error tags (:retryable → :recoverable) — inconsistent atoms across auth LiveViews → .tmp/2026-03-08-new-accounts/acceptance/consensus.md | P1-confidence | agent:consensus (76776e4)
- [ ] Add rate limit to reissue_passkey_token/1 — unlimited token reissue is a brute-force vector → backend/lib/famichat/auth/onboarding.ex:586 | P1-confidence | agent:consensus
- [-] Add copy alignment: privacy line, empty-state forward path — privacy line already exists in both templates (peer-reviewed); empty-state tracked at P0 → .tmp/2026-03-10-ideation/consensus.md | agent:consensus
- [x] Fix green CTA button contrast ratio (2.38:1 → 4.5:1) — primary buttons unreadable for vision-impaired users → .tmp/2026-03-09-bug-bash/03-grandparent-user.md A11Y-01 | P1-confidence | bug-bash
- [ ] Add visible error feedback when passkey auth fails — button silently reverts with no message → .tmp/2026-03-09-bug-bash/01-community-admin.md BUG-04 | P1-confidence | bug-bash
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
- [ ] Show one-time "no read receipts" contextual note on first message — Japanese users interpret missing kidoku as bug, not feature → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus
- [-] Reduce name input minimum to 1 char for CJK scripts — UPGRADED to P0-dogfood; done in P0 section → .tmp/2026-03-10-ideation/04-i18n-cjk.md | agent:consensus
- [x] Fix 2 Japanese brand voice violations (管理者 in community_admin_live.ex) — role labels alienate the non-technical Japanese spouse → .tmp/2026-03-10-ideation/04-i18n-cjk.md | P1-confidence | agent:consensus
- [ ] Escalate passkey error copy after 3+ repeated failures — repeated "try again" trains users to give up → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus
- [x] Demote "Set up your own family space" button to text link on login page — non-technical users tap wrong button and enter orphan flow → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus
- [ ] Show social recovery guidance after 2-3 failed passkey attempts — user with lost credential has no forward path → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus
- [ ] Set browser tab title to partner name or family name — brand name in tab misses chance to reinforce "our space" → .tmp/2026-03-09-mlp-ux/consensus.md | P1-confidence | agent:consensus
- [x] Fix `Mix.env()` in application.ex — release builds crash on boot → .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P1-confidence | agent:consensus
- [x] Add prod guard for POSTGRES_PASSWORD in runtime.exs — default "password" gives no error if forgotten in prod → .tmp/2026-03-10-p0-next-four/round-2/consensus.md | P1-confidence | agent:consensus (dfd6091)
- [x] Fix 404/410 templates to content-only — 3-for-1: resolves duplicate LiveSocket, duplicate skip links, and locale-awareness → .tmp/2026-03-10-ideation/07-routing-locale.md | P1-confidence | agent:consensus
- [x] Add rate limiting to discoverable passkey assert/challenge endpoint — unauthenticated endpoint has no DoS protection → .tmp/2026-03-10-ideation/08-test-infrastructure.md | P1-confidence | agent:consensus
- [x] Raise family creation rate limit from 3 to 10/IP/hour — same-household devices collide at 3/hr behind NAT → .tmp/2026-03-10-ideation/09-rate-limiting-nat.md | P1-confidence | agent:consensus

## Known debt (P2)
<!-- Tracked, not blocking, will matter at scale or for public launch -->
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
- [ ] Decide: reduce refresh token TTL from 30 to 7 days? — affects re-auth frequency for infrequent users vs stolen-token window → .tmp/2026-03-10-ideation/09-rate-limiting-nat.md | agent:consensus

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
