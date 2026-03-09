# Famichat Backlog

**Last updated:** 2026-03-09

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
- [ ] Fix PutRemoteIp to parse X-Forwarded-For — all visitors share one rate-limit bucket behind any proxy → .tmp/2026-03-08-new-accounts/07-robustness-error-paths.md | P0-dogfood | agent:consensus
- [ ] Fix setup_token lost on FamilyNewLive WebSocket reconnect — mobile users lose family setup mid-flow → .tmp/2026-03-08-new-accounts/07-robustness-error-paths.md | P0-dogfood | agent:consensus
- [x] Add validate_length(:name, max: 100) to Family.changeset — unbounded input reaches DB without constraint → backend/lib/famichat/chat/family.ex:33 | P0-dogfood | agent:consensus (76776e4)
- [ ] Remove last_message_preview from API — server can't produce previews under E2EE; active spec violation → backend/lib/famichat_web/controllers/api/chat_read_controller.ex:175 | P0-dogfood | spec-review (bug-bash: security tester reports field may already be removed — verify)
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
- [ ] Add copy alignment: privacy line, empty-state forward path — onboarding copy doesn't match brand voice → .tmp/2026-03-08-new-accounts/acceptance/consensus.md | P1-confidence | agent:consensus
- [ ] Fix green CTA button contrast ratio (2.38:1 → 4.5:1) — primary buttons unreadable for vision-impaired users → .tmp/2026-03-09-bug-bash/03-grandparent-user.md A11Y-01 | P1-confidence | bug-bash
- [ ] Add visible error feedback when passkey auth fails — button silently reverts with no message → .tmp/2026-03-09-bug-bash/01-community-admin.md BUG-04 | P1-confidence | bug-bash
- [ ] Increase "Getting started?" text from 12.5px to ≥16px — critical guidance invisible to older users → .tmp/2026-03-09-bug-bash/03-grandparent-user.md A11Y-02 | P1-confidence | bug-bash
- [ ] Fix skip-to-content target — #main-content ID missing from main tag → backend/lib/famichat_web/components/layouts/app.html.heex | P1-confidence | bug-bash
- [ ] Rewrite 410 error page to match brand voice — ALL-CAPS terminal aesthetic terrifies non-tech users → backend/lib/famichat_web/controllers/error_html/410.html.heex | P1-confidence | bug-bash
- [x] Disable HEEx debug annotations in prod — 85 HTML comments leak internal file paths → backend/config/prod.exs | P1-confidence | bug-bash (76776e4)
- [x] Switch CSP from report-only to enforcing; remove unsafe-eval — zero XSS protection currently → .tmp/2026-03-09-bug-bash/04-security-tester.md SEC-02 | P1-confidence | bug-bash (76776e4)
- [ ] Add ~30 missing Japanese gettext translations — login, invite, family creation, home all partially English → .tmp/2026-03-09-bug-bash/05-japanese-user.md | P1-confidence | bug-bash

## Known debt (P2)
<!-- Tracked, not blocking, will matter at scale or for public launch -->
- [ ] Add visible focus indicators on interactive elements — WCAG 2.4.7 violation; outline-style is none → .tmp/2026-03-09-bug-bash/03-grandparent-user.md A11Y-05 | P2-debt | bug-bash
- [ ] Remove or populate empty footer landmark — screen readers announce empty contentinfo region → .tmp/2026-03-09-bug-bash/01-community-admin.md BUG-05 | P2-debt | bug-bash
- [ ] Add aria-live region for passkey button state changes — loading/error invisible to screen readers | P2-debt | bug-bash
- [x] Add HSTS header for production HTTPS deployments | P2-debt | bug-bash (76776e4)
- [x] Gate console.log output behind dev flag — LiveSocket config leaks to browser console | P2-debt | bug-bash (76776e4)
- [ ] Fix 410 page hardcoded lang="en" — CJK font overrides won't apply → backend/lib/famichat_web/controllers/error_html/410.html.heex | P2-debt | bug-bash
- [ ] Root / should respect Accept-Language header for locale redirect | P2-debt | bug-bash

## Decisions needed
<!-- Need human judgment, not implementation -->
- [ ] Decide: should self_service_enabled default to true for dogfood? — controls whether strangers can create families on your server → .tmp/2026-03-08-new-accounts/acceptance/consensus.md §5.1 | agent:consensus
- [ ] Decide: rate limit threshold behind NAT (3/hr may collide for same-household devices) — same-household family members share one IP → .tmp/2026-03-08-new-accounts/acceptance/consensus.md §5.2 | agent:consensus
- [ ] Decide: accept double-biometric (register then sign-in) or auto-authenticate? — new users must biometric twice to reach home → .tmp/2026-03-08-new-accounts/acceptance/consensus.md §5.3 | agent:consensus
- [ ] Decide: clean error path for browsers without WebAuthn support — no fallback for browsers that can't do passkeys → .tmp/2026-03-08-new-accounts/acceptance/consensus.md §5.4 | agent:consensus
- [ ] Decide: Japanese translations for new gettext strings — LLM candidates need native review → .tmp/2026-03-08-new-accounts/acceptance/consensus.md §5.5 | agent:consensus
- [ ] Decide: clean up 66 pre-existing test failures as prerequisite or separate workstream? — new tests may not run cleanly on broken foundation → .tmp/2026-03-08-new-accounts/acceptance/consensus.md §5.6 | agent:consensus

## Cut / Won't do
<!-- Explicitly rejected — reason noted inline on each item -->
- [-] Bounded context refactor (Onboarding → Chat.create_family) — harmless violation in throwaway code; SPA will replace | agent:consensus
- [-] LiveView deduplication (merge FamilyNewLive into FamilySetupLive) — zero user value; throwaway code per SPEC | agent:consensus
- [-] PasskeyCeremony helper extraction — duplication is real but code is throwaway | agent:consensus
- [-] Doc updates (guardrails, lexicon, SPEC deep update) — deferred until post-dogfood stabilization | agent:consensus
- [-] QR pairing UI — invite link sufficient for L1 | spec-review
