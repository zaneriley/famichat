# Famichat L1 Onboarding — Consensus Plan

**Status:** Approved for implementation
**Supersedes:** `l1-ux-proposal.md` (draft)
**Scope:** L1 dyad — installer (admin) + spouse
**Last updated:** 2026-03-01

---

## Resolved decisions from peer review

These were conflicts or ambiguities across the design drafts. All are resolved here.

| Decision | Resolution |
|---|---|
| Invitee role | Admin. Pending state never fires at L1. Pending device state screen deferred to L2. |
| Conversation creation | Created inside `complete_registration` when second user joins. Starts empty — no pre-seeded welcome message. |
| Welcome message field | Cut. Too much engineering for L1. The installer sends a first message naturally once both are in. |
| OTP delivery | Out-of-band only at L1. Server generates code; installer reads it from server logs and tells spouse. Copy must not promise SMS delivery. |
| "You're in" / passkey success screens | Zero transitional screens. Passkey success → straight to conversation. |
| Pending device state screen | Removed from L1 scope entirely. `trust_state` column doesn't exist. Spouse is admin anyway. |
| Invite expiry | Clock starts at creation. Installer copy: "expires in 10 minutes — send it now." |
| Passkey button label | "Set up your passkey" — OS-neutral, avoids Save vs. Create mismatch between iOS and Android. |
| E2EE copy | Softened. Server decrypts at L1. No "only you can read this" claim. Use "private — just the two of you" instead. |
| "Family" in copy | Replace with "your people" or just names. Consistent with brand positioning (inner circle, not nuclear family). |

---

## Installer flow

### Screen I-1: First Setup

**Route:** `/setup`
**Trigger:** Any admin user exists? No → show this. Yes → redirect to `/`.

```
This is your private space.
Set up your account first.

[  Get started  ]
```

Sub-copy (small, below button):
```
This only runs once.
```

---

### Screen I-2: Your name

**Route:** `/setup` (same view, step 2)

```
What should people call you?

[ Your name              ]

[  Continue  ]
```

Helper text:
```
This is how you'll appear to the people you invite.
```

---

### Screen I-3: Set up your passkey

**Route:** `/setup` (same view, step 3)
**Triggers:** `navigator.credentials.create()` via JS on button tap.

```
Set up your passkey.

We'll use your device's built-in security —
whatever you use to unlock your phone.

[  Set up your passkey  ]
```

**If passkey is dismissed or fails:**

Inline below the button (not a new screen):
```
Didn't work? [Try again]  ·  [Use a code instead]
```

**OTP path for installer (server logs):**
Since no SMS infra exists at L1, the installer is a developer who can read logs. Show:

```
Check your server logs for a 6-digit code,
or run: docker logs famichat | grep OTP

[ __ __ __ — __ __ __ ]

[  Confirm  ]
```

---

### Screen I-4: Home screen (pre-invite)

**Route:** `/`
**State:** Installer is in; no invite sent yet; no conversations exist.

```
[ Your name ]

────────────────────────────────────

  No one else is here yet.
  Invite someone to get started.

  [  Send an invite  ]

────────────────────────────────────
```

**State:** Invite sent; spouse not yet joined.

```
[ Your name ]

────────────────────────────────────

  Waiting for [name] to join.

────────────────────────────────────
```

**State:** Spouse joins (PubSub fires, list updates live).

Flash notice (unobtrusive, top of screen):
```
[Name] just joined. Your conversation is ready.
```

Conversation list updates to show the active 1:1. Navigate there automatically if the installer is on the home screen.

---

### Screen I-5: Send an invite

**Route:** `/invite/new`

```
Invite someone

[  Their name or nickname  ]
(optional — helps you remember who this is for)

[  Create invite link  ]
```

No email field. No role picker (defaults to admin). No welcome message field.

---

### Screen I-6: Invite link ready

**Route:** `/invite/sent`

```
Link ready — send it now.

[ https://[your-domain]/invites/abc123... ]   [Copy]

────────────────────────────────────

[  Share  ]

────────────────────────────────────

This link expires in 10 minutes.
Send it now, then tell [name] to open it right away.

If it expires, you can create a new one here.

────────────────────────────────────

[  Back to messages  ]
```

Pre-written text to copy alongside the link (displayed below the URL, copyable separately):
```
I set something up for us — just for the two of us.
Tap this and it'll take a minute to get in: [link]
(It expires soon, so open it when you see this.)
```

**Share button:** Web Share API on mobile; copies to clipboard on desktop.

---

## Invitee flow

### Screen V-1: Welcome gate

**Route:** `/invites/:token`
**State:** Token valid, not yet consumed.

```
[Name] invited you.

This is their private space — just the two of you.
You're one of them.

[  Join  ]

────────────────────────────────────
This link was created by [Name] and expires soon.
```

Tapping Join: `POST /auth/invites/accept` — consumes token, mints registration JWT, redirects to V-2.

**State: Token expired (410)**
```
This link has expired.

Invite links only last 10 minutes.
Ask [Name] to send a new one — it takes a few seconds.
```

**State: Token already used (410)**
```
This link has already been used.

Each invite works once.
If that wasn't you, ask [Name] for a new link.
```

**State: Token invalid (404)**
```
This link isn't valid.

Check that you copied the full link,
or ask [Name] to send a new one.
```

*Show installer name on expired/invalid screens by decoding JWT claims without signature verification — safe since no access is being granted.*

---

### Screen V-2: Your name

**Route:** `/invites/:token/profile`

```
What should people call you?

[ Your name              ]

[  Continue  ]
```

Helper text:
```
This is how [Installer name] will see you.
```

---

### Screen V-3: Set up your passkey

**Route:** `/invites/:token/passkey`

```
Set up your passkey.

We'll use your device's built-in security —
whatever you use to unlock your phone.
No password needed.

[  Set up your passkey  ]
```

Pre-frame copy above the button matters here — many users have never deliberately used a passkey. The phrase "whatever you use to unlock your phone" is the anchor: Face ID, fingerprint, PIN — all of those.

**If passkey is dismissed (browser prompt cancelled):**

Inline below button:
```
Looks like that was dismissed.
[Try again]  ·  [Use a code instead]
```

**If passkey not supported (detect `PublicKeyCredential` absence):**
```
Your browser doesn't support the sign-in method we use.
Try opening this link in Safari or Chrome.
Or:  [Use a code instead]
```

**OTP fallback path (invitee):**
At L1, the installer must read the code from logs and send it to the invitee out-of-band. The OTP screen reflects this:

```
[Installer name] will send you a 6-digit code.

[ __ __ __ — __ __ __ ]

[  Confirm  ]
```

Do not show a phone number entry field. Do not say "We sent a code to..." — the server cannot deliver it.

If code is wrong:
```
That code didn't match.
Check with [Name] — they may need to send a new one.
```

---

### Screen V-4: First arrival

**Route:** `/` (redirected after passkey registration + session start)

The invitee lands directly in the 1:1 conversation. No transitional "You're in" screen.

If the conversation is empty (installer hasn't sent a message yet):

```
Just the two of you, for now.

Messages here are end-to-end encrypted —
only the two of you can read them.

[ What's on your mind?                    ]  ▶
```

**On first message sent** (one-time, never shown again):
```
Sent. Only [name] can read this.
```

*Stored in localStorage. Shows once, disappears.*

---

## Returning user: login

**Route:** `/login`

```
Welcome back.

[  Unlock with passkey  ]

────────────────────────────────────
Use a code instead
```

On successful passkey assertion: navigate to most recently active conversation.

**If device has no stored passkey / passkey fails:**
```
[Use a code instead]
```
→ OTP path (same as V-3 fallback).

**Session expired (not "Your session has expired" — user doesn't know what a session is):**
```
You've been away for a while.
Sign back in to continue.

[  Unlock with passkey  ]
```

---

## Backend requirements (ordered by dependency)

Everything blocks on this list before any screen can work end-to-end.

1. **`GET /api/v1/system/status` or `Identity.any_admin_exists?/0`** — First-run detection. SetupLive checks this on mount; redirects to `/` if any admin exists.

2. **`POST /api/v1/setup`** — Creates first admin user + household in a single transaction. Returns `passkey_register_token`. Returns 410 if any admin already exists (single-use guard). Does not require auth.

3. **`POST /api/v1/conversations` (internal, not user-facing yet)** — Called inside `Onboarding.complete_registration/2` when second user joins. Creates `:direct` conversation between installer and invitee. Idempotent (SHA256 of sorted user IDs + family_id + salt per SPEC).

4. **`complete_registration/2` update** — After user + membership are created, call conversation creation. Emit `PubSub.broadcast(topic: "household:#{household_id}", event: :member_joined, payload: %{user_id, display_name})`.

5. **HomeLive PubSub subscription** — Subscribe to `household:#{household_id}`. On `:member_joined`: update conversation list, flash "[Name] just joined. Your conversation is ready.", navigate to conversation if installer is on home screen.

6. **Invite landing LiveView** — `GET /invites/:token` renders V-1. On Join tap: calls `POST /auth/invites/accept`, stores registration JWT, redirects to V-2.

7. **PasskeyRegistrationLive** — Wires `navigator.credentials.create()` to `/api/v1/auth/passkeys/register/challenge` + `/api/v1/auth/passkeys/register`. On success: immediate assertion to start session. On failure: inline copy, OTP fallback link.

8. **PasskeyAssertionLive** — Wires `navigator.credentials.get()` to challenge + assert endpoints. On success: navigate to most recent conversation. On failure: OTP fallback.

---

## Cut list

These were proposed across the design drafts and are explicitly not in L1 scope.

| Cut | Why |
|---|---|
| Welcome message field on invite form | 4 pieces of engineering; installer sends first message naturally |
| "Message [Name]" deep link on expired token | Requires stored phone number; complex for a rare path |
| 1.5-second forced display on success screen | Animation engineering for a throwaway view |
| OTP nudge after auth ("save a passkey next time") | Will be dismissed reflexively; belongs in settings |
| Passkey success confirmation screen | Introduces recovery anxiety at the wrong moment |
| Pending device state screen | `trust_state` column doesn't exist; spouse is admin at L1 |
| Installer in-app notification on token expiry | Background job + notification surface; overkill for L1 |
| Cancel recovery as a distinct screen | Inline copy handles it |
| Profile photo upload | Wrong moment, wrong signal |
| Feature tour / walkthrough overlay | If it needs a tour, it's a design problem |
| Notification permission request during onboarding | Will be denied; ask contextually after first message received while backgrounded |
| "Invite more people" prompt post-join | Growth mechanic masquerading as helpfulness |
| Password as auth path | Not on the roadmap; showing a password field sets a permanent expectation |
| Recovery phrase setup during onboarding | L3 work, not L1 |
| Typing indicators (even disabled) | Don't build what you don't want; off-by-default still implies it exists |
| Conversation actions in header (video, search) | Absence is better than disabled ghost icons |
| Animated message arrivals | Content is the event, not the delivery |
| Red unread badge counts | Quiet dot or weight change only |

---

## First message experience

**Composer**
- Default height: 3–4 lines (not a single-line chat input; implies more than one sentence is welcome)
- Placeholder: *"What's on your mind?"*
- Send: explicit button tap, not Enter-to-send
- No attachment button, emoji picker button, GIF, voice memo, overflow menu — they don't exist yet, don't show them disabled

**Message rendering**
- Full-width typographic blocks, not chat bubbles
- 16–17px body, line-height 1.5
- Timestamps in human language: "this morning," "yesterday," "Tuesday" — not "10:42 AM" by default. Precise time on tap/hover only.

**Conversation header**
- Name only. No status, no avatar in header, no video call icon, no search icon.

**Notifications** (deferred from onboarding)
- Ask for notification permission the first time a message arrives while the user is not in the app — not at registration
- Default notification copy: "[Name] sent you a message" (person-first, no preview)

---

## Open questions

These need product owner judgment before build. They don't block design but will cause backtracking if left unresolved.

1. **Invite expiry behavior:** Clock currently starts at creation time. Proposal doc suggests changing to start at POST-accept time (more forgiving). Backend change required. Worth it for L1?

2. **Letters toggle placement:** Plain message is the default. When and how prominently does Letters mode appear in the composer? After first send? On second session?

3. **Cozy kill criterion:** L1 kill condition is "UI feels clinical not cozy." What's the testable version? Suggested: spouse uses an unprompted warm/calm word to describe the app AND opens the app on at least one day without receiving a notification first.

4. **Second invite during L1:** If L1 goes well early, is a third person (child away at school) in scope before the two-week window closes? Recommendation: hold the dyad strictly. Any additional person is L2.

5. **Installer OTP at L1:** "Check server logs" is rough. Is there a simpler surface — e.g., the setup screen temporarily displays the OTP — that doesn't require real delivery infrastructure?
