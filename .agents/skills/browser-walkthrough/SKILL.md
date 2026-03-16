---
name: browser-walkthrough
description: Run a multi-agent browser QA pass against a fresh Famichat instance. Spawns 7 agents (bootstrap, invite, family, locale/errors, link basher, API basher, triage) that test every CUJ and click every interactive element.
argument-hint: "[--skip-api] [--only bootstrap,invite,family,locale,links,api,triage]"
---

# Browser Walkthrough — Agent-Per-CUJ QA

You are orchestrating a multi-agent QA pass of Famichat's user-facing flows. Each CUJ group runs in its own agent with a dedicated context window. The database should be freshly reset before running this.

Use today's date (YYYY-MM-DD) wherever `{DATE}` appears below.

Do NOT fix bugs during the walkthrough. Do NOT modify source files until Phase 3 (promote).

## Invocation

```
/browser-walkthrough                          # full run, all 7 agents
/browser-walkthrough --only bootstrap,locale  # run only specified agents
/browser-walkthrough --skip-api               # skip Agent 6 (API basher)
```

If `$ARGUMENTS` contains `--only`, parse the comma-separated list and only run those agents. If `--skip-api`, skip Agent 6.

---

## Architecture

| Agent | Browser? | Depends on | Tests |
|-------|----------|------------|-------|
| 1 — Bootstrap | Yes | none | Admin setup + sign-in (CUJ 1-2) |
| 2 — Invite Flow | Yes | Agent 1 | Create invite + accept invite (CUJ 3-4) |
| 3 — Family Creation | Yes | Agent 1 | Self-service family + admin panel + setup link (CUJ 5-7) |
| 4 — Locale & Errors | Yes | soft dep on Agent 1 | Japanese locale + error paths + edge cases (CUJ 8-10) |
| 5 — Link Basher | Yes | Agents 1-4 | Click every interactive element on every reachable page |
| 6 — API Basher | No (curl) | Agent 1 (for token) | Hit all API endpoints with valid + invalid requests |
| 7 — Triage | No | All above | Read all findings, dedupe against BACKLOG.md |

**Execution order:**
- Phase 0: Setup (orchestrator)
- Phase 1a: Agent 1 (bootstrap) — must complete first
- Phase 1b: Agent 6 (API basher) — starts in background after Agent 1
- Phase 1c: Agent 2 → Agent 3 → Agent 4 (sequential browser agents)
- Phase 1d: Agent 5 (link basher) — after all CUJ agents
- Phase 2: Agent 7 (triage)
- Phase 3: Promote to backlog

**P0 cascade rule:** If Agent 1 hits a P0 that blocks all auth flows:
- Skip Agents 2 + 3 (they need auth state)
- Still run Agent 4 (most locale/error tests don't need auth)
- Still run Agent 6 for unauthenticated API endpoints
- Run Agent 5 in degraded mode (unauthenticated pages only)

---

## Phase 0: Setup (orchestrator does this directly)

### 0.1 Verify environment

```bash
# Check the app is running
curl -sf http://localhost:9000/api/v1/health | jq .
# Expected: {"status":"ok"}
```

### 0.2 Set up virtual authenticator

Run via `browser_run_code`:

```js
async (page) => {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('WebAuthn.enable');
  const { authenticatorId } = await cdp.send('WebAuthn.addVirtualAuthenticator', {
    options: {
      protocol: 'ctap2',
      transport: 'internal',
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
    }
  });
  return { authenticatorId };
}
```

### 0.3 Initialize state file

Write `.tmp/{DATE}-browser-walkthrough/state.json`:

```json
{
  "date": "{DATE}",
  "app_url": "http://localhost:9000",
  "authenticator_id": "<from step 0.2>",
  "admin_username": null,
  "admin_authenticated": false,
  "invite_url": null,
  "invited_username": null,
  "family_setup_url": null,
  "api_access_token": null,
  "p0_blocker": null,
  "agents_completed": []
}
```

### 0.4 Create screenshots directory

```bash
mkdir -p .tmp/{DATE}-browser-walkthrough/screenshots
```

---

## Shared agent preamble

Inject this block at the top of every browser agent's prompt (Agents 1-5).

```
## Browser testing protocol

You have Playwright MCP browser tools. The app runs at http://localhost:9000.
A CDP virtual authenticator is already configured — passkey ceremonies work automatically.

### For EVERY page you visit

1. `browser_snapshot` — read the accessibility tree to see what's on screen
2. **Catalog every interactive element**: links, buttons, inputs, selects, disclosure widgets
3. Do the CUJ-specific action (happy path first)
4. `browser_snapshot` again to see the result
5. Then go back and test every OTHER interactive element on that page:
   - Click each link — does it navigate correctly? Record the target.
   - Click each button — does it do something sensible? Does it crash?
   - For the language switcher: click it, verify locale changes, click back
   - For "Skip to main content": click it, verify focus moves
   - For forms: try empty submit, try boundary-length input (200+ chars)
6. Record each element and result in your output file

### Result codes

- **PASS** — behaved as expected
- **FAIL** — crashed, showed wrong content, or didn't respond
- **UNEXPECTED** — didn't crash but behavior was surprising or confusing
- **BLOCKED** — could not test due to earlier failure

### On FAIL or UNEXPECTED, IMMEDIATELY capture

- `browser_console_messages` (level: "error")
- `browser_network_requests` (includeStatic: false)
- `browser_take_screenshot` → `.tmp/{DATE}-browser-walkthrough/screenshots/<descriptive-name>.png`
- If the docker container logs are accessible: `docker compose logs web --tail=40`

### State file

Read `.tmp/{DATE}-browser-walkthrough/state.json` at the start of your work.
Write back any new state you produce (new URLs, tokens, usernames) when done.

### Rules

- Do NOT fix bugs. Document only.
- Do NOT modify source files.
- Do NOT run mix commands, git operations, or anything that changes the app.
- If a passkey ceremony hangs for >10 seconds, capture console messages and move on.
- If a page crashes (500, "We can't find the internet"), capture everything and continue to next step.
- Write findings to your output file AS YOU GO — do not hold results in memory.
```

---

## Agent 1: Bootstrap (CUJ 1 + CUJ 2)

**Trigger:** Phase 0 complete
**Output file:** `.tmp/{DATE}-browser-walkthrough/agent-1-bootstrap.md`
**State writes:** `admin_username`, `admin_authenticated`, `api_access_token`

### Agent 1 prompt

```
{SHARED_PREAMBLE}

You are the Bootstrap Agent. Your job is to test the fresh-instance admin setup and first sign-in.

Write findings to: .tmp/{DATE}-browser-walkthrough/agent-1-bootstrap.md

### CUJ 1: Fresh instance → Admin bootstrap

Step 1: Navigate to http://localhost:9000/
- EXPECTED: 302 redirect chain → /en/setup (fresh instance with no users)
- Check: Does it end up on the setup page? Is the form visible?
- EXHAUSTIVE: Test every element on the page (language switcher, skip-to-content, Famichat home link)

Step 2: Test form validation BEFORE submitting valid data
- Submit with empty username → EXPECTED: validation error, NOT a crash
- Submit with a 200+ character username → EXPECTED: validation error
- Submit with empty family name → EXPECTED: either validation error or accepted (it's optional)

Step 3: Fill in valid data and submit
- Username: "zane", Family name: "Riley Family"
- Click Continue
- EXPECTED: Passkey registration step appears (a button to register passkey)

Step 4: Complete passkey registration
- Click the passkey register button
- The virtual authenticator handles navigator.credentials.create() automatically
- EXPECTED: Success feedback → advance to next step (invite generation or redirect)

Step 5: Note the final URL and page state
- If there's an "generate invite" button, note it
- If redirected to login, note that
- EXHAUSTIVE: Test every element on the post-registration page

### CUJ 2: Admin sign-in

Step 6: Navigate to http://localhost:9000/en/login
- EXPECTED: Sign-in page with a passkey button
- EXHAUSTIVE: Test every element (passkey button, language switcher, "Set up your own family space" link, skip-to-content)

Step 7: Click the passkey sign-in button
- The virtual authenticator handles navigator.credentials.get() automatically
- EXPECTED: Authenticated → redirected to home (/en/)

Step 8: Document the home page
- What does it show? Conversations? Empty state? Invite button?
- EXHAUSTIVE: Test every element on the home page (invite button, sign out, family switcher, any links)
- If there's a way to get an API access token from the page or session, capture it

Step 9: If an invite URL is visible on the home page, capture it for Agent 2

### After completing all steps

Update state.json with:
- admin_username: "zane"
- admin_authenticated: true
- api_access_token: (if obtainable)
- invite_url: (if visible on home page)

If CUJ 1 crashed with a P0 blocker, set:
- p0_blocker: "<description of the crash>"
```

---

## Agent 2: Invite Flow (CUJ 3 + CUJ 4)

**Trigger:** Agent 1 completed with `admin_authenticated: true`
**Output file:** `.tmp/{DATE}-browser-walkthrough/agent-2-invite-flow.md`
**State writes:** `invite_url`, `invited_username`

### Agent 2 prompt

```
{SHARED_PREAMBLE}

You are the Invite Flow Agent. Your job is to test creating an invite and accepting it as a new user.

Read state.json first — you need the admin session from Agent 1.

Write findings to: .tmp/{DATE}-browser-walkthrough/agent-2-invite-flow.md

### CUJ 3: Admin creates an invite

Step 1: Navigate to http://localhost:9000/en/ (home page, should be authenticated)
- If not authenticated, navigate to /en/login and sign in with passkey first
- EXPECTED: Home page with some way to generate an invite

Step 2: Find and use the invite generation mechanism
- Look for an "Invite" button, link, or similar
- Click it, generate an invite link
- Copy the full invite URL
- EXHAUSTIVE: Test every element on the invite generation UI

Step 3: If no invite mechanism exists on home, try:
- http://localhost:9000/en/admin — the admin panel may have invite generation
- Document what you find

### CUJ 4: Invitee accepts invite (different user context)

Step 4: Open a NEW browser tab (browser_tabs action: "new")
Step 5: Navigate to the invite URL from Step 2
- EXPECTED: Invite acceptance page with a username form
- EXHAUSTIVE: Test every element on the invite page

Step 6: Test form validation
- Submit with empty username → EXPECTED: validation error
- Submit with a 200+ character username → EXPECTED: validation error

Step 7: Submit with valid username: "parker"
- EXPECTED: Passkey registration step appears

Step 8: Complete passkey registration
- Click the passkey register button
- EXPECTED: Success → either auto-signed-in or redirected to login

Step 9: If redirected to login, open another new tab and sign in as "parker"
- Navigate to /en/login, click passkey sign-in
- EXPECTED: Authenticated → home page
- EXHAUSTIVE: Test every element on parker's home page
- Does parker see the Riley Family conversation?

Step 10: Navigate back to the invite URL (reuse it)
- EXPECTED: Friendly "already used" or "already have an account" message, NOT a crash

### After completing all steps

Update state.json with:
- invite_url: "<the URL used>"
- invited_username: "parker"
```

---

## Agent 3: Family Creation (CUJ 5 + CUJ 6 + CUJ 7)

**Trigger:** Agent 1 completed with `admin_authenticated: true`
**Output file:** `.tmp/{DATE}-browser-walkthrough/agent-3-family-creation.md`
**State writes:** `family_setup_url`

### Agent 3 prompt

```
{SHARED_PREAMBLE}

You are the Family Creation Agent. Your job is to test self-service family creation, the admin panel, and family setup link redemption.

Read state.json first — you need the admin session from Agent 1.

Write findings to: .tmp/{DATE}-browser-walkthrough/agent-3-family-creation.md

### CUJ 5: Self-service family creation

Step 1: Open a new tab, navigate to http://localhost:9000/en/families/new
- EXPECTED: Family name form (if self_service_enabled is true) OR redirect to login
- EXHAUSTIVE: Test every element on the page

Step 2: If the form appears, test validation
- Submit with empty name → EXPECTED: validation error
- Submit with 200+ character name → EXPECTED: validation error

Step 3: Submit with valid name: "Test Family"
- Follow through the setup flow (should go to /families/start/:token)
- EXPECTED: Username form appears

Step 4: Enter username "testadmin", complete passkey registration
- EXPECTED: Success → signed in or redirected

Step 5: Document the post-creation state
- EXHAUSTIVE: Test every element on the resulting page

### CUJ 6: Community admin panel

Step 6: Sign in as "zane" (the original admin)
- Navigate to /en/login, passkey sign-in

Step 6b: ROLE CHECK — Test admin panel access as a non-admin user
- Open a new tab
- Navigate to /en/login and sign in as "parker" (the invited non-admin user from Agent 2, if available)
- Navigate to /en/admin
- EXPECTED: 403, redirect to home page (/en/), or "not authorized" — NOT the admin panel
- If the admin panel loads for parker (shows families, add-family button), record this as P0: "Admin panel not gated by role check — any authenticated user has admin access"
- Navigate back to the zane tab (or sign out of parker and back in as zane) before continuing

Step 7: Navigate to http://localhost:9000/en/admin (as zane)
- EXPECTED: Admin panel showing at least "Riley Family"
- EXHAUSTIVE: Test every element (family list, add family button, any links)

Step 8: Click "Add a family" or equivalent
Step 9: Enter family name: "Neighbor Family", submit
- EXPECTED: Success → setup link appears

Step 10: Copy the setup link URL
- EXHAUSTIVE: Test any copy button, reissue link option, etc.

### CUJ 7: Family setup link redemption

Step 11: Open a new tab, navigate to the setup link from Step 10
- EXPECTED: Family setup page with username form
- EXHAUSTIVE: Test every element

Step 12: Test validation
- Empty username → EXPECTED: error
- 200+ char username → EXPECTED: error

Step 13: Enter username "neighbor", complete passkey registration
- EXPECTED: Success

Step 14: Navigate to the setup link again (reuse it)
- EXPECTED: Friendly error (already used), NOT a crash

### After completing all steps

Update state.json with:
- family_setup_url: "<the URL used>"
```

---

## Agent 4: Locale & Errors (CUJ 8 + CUJ 9 + CUJ 10)

**Trigger:** Agent 1 completed (soft dependency — runs even if Agent 1 hit P0, since most tests don't need auth)
**Output file:** `.tmp/{DATE}-browser-walkthrough/agent-4-locale-errors.md`

### Agent 4 prompt

```
{SHARED_PREAMBLE}

You are the Locale & Error Agent. Your job is to test Japanese locale rendering, error paths, and edge cases.

Read state.json — if p0_blocker is set, note that some tests requiring auth will be BLOCKED.

Write findings to: .tmp/{DATE}-browser-walkthrough/agent-4-locale-errors.md

### CUJ 8: Japanese locale

Step 1: Navigate to http://localhost:9000/ja/login
- EXPECTED: Japanese text renders correctly (not raw gettext keys like "Sign in")
- Check EVERY visible string: is it Japanese or English?
- EXHAUSTIVE: Test language switcher (JA → EN and back), all links

Step 2: Navigate to http://localhost:9000/ja/setup (or wherever the setup page is in fresh state)
- EXPECTED: Japanese text for all form labels, buttons, helper text
- Check: Are placeholder texts translated?

Step 3: Navigate to http://localhost:9000/ja/families/new
- EXPECTED: Japanese text throughout
- Note any English strings that should be Japanese

Step 4: If authenticated (admin_authenticated is true):
- Navigate to http://localhost:9000/ja/ (home)
- Check all strings for Japanese translation

Step 5: Navigate to http://localhost:9000/ja/invites/fake-token
- Check error message is in Japanese

### CUJ 9: Error paths

Step 6: Navigate to http://localhost:9000/en/invites/totally-invalid-token
- EXPECTED: Friendly error page or message, NOT a crash or generic 500
- EXHAUSTIVE: Test every element on the error page

Step 7: Navigate to http://localhost:9000/en/families/start/expired-fake-token
- EXPECTED: Friendly error page or message

Step 8: Navigate to http://localhost:9000/xx/login (unsupported locale)
- EXPECTED: 404 page or redirect to /en/, NOT a 200 with broken content
- EXHAUSTIVE: Test any "return home" link on the 404 page

Step 9: Navigate to http://localhost:9000/en/nonexistent-page
- EXPECTED: 404 page

Step 10: Navigate to http://localhost:9000/api/v1/health
- EXPECTED: 200 JSON {"status":"ok"}, NOT an HTML page

Step 11: Navigate to http://localhost:9000/api/v1/nonexistent
- EXPECTED: 404 JSON, NOT HTML

### CUJ 10: Edge cases

Step 12: Navigate to http://localhost:9000/en/setup
- If admin already exists: EXPECTED: redirect to /en/login or /en/ (setup is one-shot)
- If admin does NOT exist (P0 blocker): test form validation (empty username, long username)

Step 13: Navigate to http://localhost:9000/en/families/new
- Test form with very long name (200+ characters)
- EXPECTED: Validation error, NOT a crash

Step 14: Navigate to http://localhost:9000/ (bare root, no locale)
- EXPECTED: Redirect to /en/ or /en/login, NOT a crash

Step 15: Navigate to http://localhost:9000/en/logout (without being signed in)
- EXPECTED: Redirect to login, NOT a crash

Step 16: Try double-clicking submit buttons quickly
- On any available form, click submit twice rapidly
- EXPECTED: No duplicate submission, no crash
```

---

## Agent 5: Link Basher

**Trigger:** All CUJ agents (1-4) completed
**Output file:** `.tmp/{DATE}-browser-walkthrough/agent-5-link-basher.md`

### Agent 5 prompt

```
{SHARED_PREAMBLE}

You are the Link Basher. Your job is to visit EVERY reachable page and click EVERY interactive element.

Read state.json for authentication state and URLs discovered by previous agents.

Write findings to: .tmp/{DATE}-browser-walkthrough/agent-5-link-basher.md

### Crawl protocol

1. Build a seed list:
   a. Read backend/lib/famichat_web/router.ex — extract every `live` and `get` route that serves HTML
   b. For locale-prefixed routes, generate both /en/ and /ja/ variants
   c. Add any token-gated URLs from state.json (invite_url, family_setup_url)
   d. Add a few known-bad URLs for error path testing: /xx/login, /en/nonexistent, /api/v1/nonexistent
   e. Add /up, /up/databases, /api/v1/health as non-browser sanity checks

2. Maintain a visited-URLs set. Never visit the same URL twice.

3. For each URL in the queue:
   a. Navigate to it
   b. browser_snapshot — read the full accessibility tree
   c. Record the page title, final URL (after redirects), and element count
   d. For EVERY interactive element (link, button, input, select, details/summary):
      - Record: element type, label/text, ref, href (if link)
      - Click it (or for forms: fill with test data and submit)
      - browser_snapshot — what happened?
      - Record: PASS/FAIL/UNEXPECTED
      - On FAIL: capture screenshot + console errors
      - Navigate back to the page (browser_navigate_back or re-navigate)
   e. For any NEW links discovered (href not in visited set), add to queue
   f. Write the page's results immediately to your output file

4. Stop after visiting 50 unique pages OR exhausting the queue.

### Element interaction rules

| Element type | Action | What to check |
|-------------|--------|---------------|
| Link (internal) | Click | Does it navigate to the expected page? |
| Link (external) | Note target | Don't follow — just record the href |
| Link (anchor #) | Click | Does focus move? Is the target present? |
| Button | Click | Does it do something? Error? Crash? |
| Text input | Type "test" then clear | Does it accept input? Any JS errors? |
| Form | Submit empty, then submit with "test" values | Validation errors? Crashes? |
| Language switcher | Click each option | Does locale change? Do all strings update? |
| Details/summary | Click to toggle | Does it expand/collapse? |

### Output format

For each page, write:

### Page: [URL]
- Final URL: [after redirects]
- Page title: [title]
- Status: [200/404/500/redirect]
- Elements found: [count]

| # | Type | Label | Ref | Action | Result | Notes |
|---|------|-------|-----|--------|--------|-------|
| 1 | link | "Famichat home" | e5 | click | PASS | navigated to /en/ |
| 2 | button | "Sign in" | e12 | click | FAIL | console error, screenshot: ... |
| ... | ... | ... | ... | ... | ... | ... |
```

---

## Agent 6: API Basher

**Trigger:** Agent 1 completed (or immediately for unauthenticated endpoints)
**Output file:** `.tmp/{DATE}-browser-walkthrough/agent-6-api-basher.md`
**Runs in background** (`run_in_background: true`) using `Bash(curl)` — no browser needed.

### Agent 6 prompt

```
You are the API Basher. Your job is to test every API endpoint with valid and invalid requests.

Read .tmp/{DATE}-browser-walkthrough/state.json for any auth token.

Write findings to: .tmp/{DATE}-browser-walkthrough/agent-6-api-basher.md

Use curl for all requests. The app runs at http://localhost:9000.

### Step 1: Discover all routes

Read backend/lib/famichat_web/router.ex and extract every route declaration:
- `get`, `post`, `put`, `patch`, `delete` calls
- `live` declarations (these are GET routes)
- Note which pipeline each route is in (`:api`, `:api_authenticated`, `:browser`, `:browser_authenticated`)

Build a complete endpoint list organized by: auth required? method? path?

### Step 2: Test each endpoint

For every endpoint, test these scenarios using curl:

1. **Happy path** — valid request shape (with auth header if the route is in an authenticated pipeline)
2. **No auth** — omit the Authorization header (expect 401 for authenticated endpoints, normal response for public endpoints)
3. **Malformed input** — send `{"garbage": true}` as JSON body for POST/PUT/PATCH endpoints
4. **Wrong method** — send GET to a POST endpoint and vice versa (expect 404 or 405)

For each test, record:
- HTTP status code
- Content-Type header (API routes should return `application/json`, browser routes should return `text/html`)
- Whether the body contains stack traces, internal file paths, or Elixir module names (security issue if so)
- First 200 characters of the response body

### Step 3: Also test these cross-cutting concerns

- **API routes should never return HTML.** If any `/api/*` route returns `text/html`, that's a FAIL.
- **Browser routes should never return JSON.** If any `/:locale/*` route returns `application/json`, that's a FAIL.
- **Error catch-alls work.** Test `/api/v1/nonexistent` (expect 404 JSON) and `/totally-nonexistent` (expect 404 HTML).
- **Health endpoints are accessible.** Test `/up`, `/up/databases`, `/api/v1/health`.

### Output format

For each endpoint:

### [METHOD] [PATH] ([pipeline])
| Test | Status | Content-Type | Body preview | Result |
|------|--------|-------------|-------------|--------|
| happy path | 200 | application/json | {"status":"ok"} | PASS |
| no auth | 401 | application/json | {"error":"..."} | PASS |
| malformed | 422 | application/json | {"errors":...} | PASS |
| wrong method | 404 | ... | ... | FAIL — returned HTML |
```

---

## Phase 2: Triage (Agent 7)

After ALL agents (1-6) complete, spawn the Triage Agent.

### Agent 7 prompt

```
You are the Triage Agent for a Famichat browser QA walkthrough.

Read ALL of these files:
- .tmp/{DATE}-browser-walkthrough/agent-1-bootstrap.md
- .tmp/{DATE}-browser-walkthrough/agent-2-invite-flow.md
- .tmp/{DATE}-browser-walkthrough/agent-3-family-creation.md
- .tmp/{DATE}-browser-walkthrough/agent-4-locale-errors.md
- .tmp/{DATE}-browser-walkthrough/agent-5-link-basher.md
- .tmp/{DATE}-browser-walkthrough/agent-6-api-basher.md
- docs/BACKLOG.md (to check for duplicates)

Skip any agent files that don't exist (those agents may have been skipped).

### Your job

1. Extract every FAIL and UNEXPECTED from the agent reports
2. For each finding, check if it's already tracked in BACKLOG.md (grep for key nouns)
3. Assign severity to NEW findings:
   - P0-dogfood: Blocks handing the URL to family. Crashes, data loss, auth bypass, can't complete a core CUJ.
   - P1-confidence: Can dogfood, but erodes trust. Bad copy, confusing UX, missing feedback, a11y failures.
   - P2-debt: Known debt, not blocking. Minor visual issues, edge cases.

4. Format each finding as a BACKLOG.md-ready one-liner

### Output

Write to: .tmp/{DATE}-browser-walkthrough/triage.md

Use this structure:

# Triage — Browser Walkthrough {DATE}

## Summary
- Total elements tested: N (across all agents)
- Passed: N
- Failed: N
- Unexpected: N
- Blocked: N

## New findings (not already in BACKLOG.md)

- [ ] Short imperative description — why it matters in ≤15 words → source-agent-file.md | severity | browser-walkthrough
- [ ] ...

## Already tracked (skip these)

- [description] — already tracked in BACKLOG.md as "[existing item]"
- ...

## Needs human judgment

- [description] — unclear severity because [reason]
- ...
```

---

## Phase 3: Promote to backlog

After triage is complete, invoke `/promote .tmp/{DATE}-browser-walkthrough/triage.md` to update canonical docs.

If `/promote` is not available, do it manually:
1. Read `docs/BACKLOG.md`
2. For each new finding from triage, add it to the appropriate severity section
3. If any P0 findings exist, update `docs/NOW.md` to reflect the new blockers
4. Do NOT change severity of existing items

---

## Orchestration rules

1. **Spawn agents sequentially for browser work.** Only one agent can use Playwright at a time. The API Basher runs in background (parallel) since it uses curl.

2. **Write findings incrementally.** Each agent writes to its own file as it goes. Do not hold results in memory.

3. **Screenshot on failure.** Every FAIL or UNEXPECTED gets a screenshot in `.tmp/{DATE}-browser-walkthrough/screenshots/`. Name: `agent{N}-{descriptive-name}.png`.

4. **Verify state between agents.** After each browser agent completes, read `state.json` and verify the expected state was written before spawning the next agent.

5. **Do not fix during walkthrough.** Phases 0-2 are observation only. No source file edits. No mix commands. No git operations.

6. **Triage before promoting.** Phase 2 must complete before Phase 3 starts.

7. **Check for duplicates.** The Triage Agent must grep BACKLOG.md for each finding's key noun before flagging it as new.

8. **Context budget.** Each agent should complete within ~40 tool interactions. If an agent exceeds this, it should summarize progress so far and stop. Quality over quantity.

9. **Known Playwright limitation.** Passkey credentials from the virtual authenticator are shared across all tabs — "different users" in different tabs still share the same authenticator. This is acceptable for testing but should be noted if it causes confusion.

## Rules

- This skill is read-only on the codebase through Phases 0-2. Only Phase 3 (promote) edits canonical docs.
- Each agent writes exactly one output file. No shared state between agents except state.json.
- If an agent fails or is skipped, the run is still usable. Note the gap in triage.
- Running `/browser-walkthrough` twice produces separate dated output directories — no conflicts.
