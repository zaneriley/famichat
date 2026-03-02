# Onboarding — Backend Requirements

**Scope:** L1 dogfood. What needs to exist before the onboarding screens in `onboarding-l1.md` work end-to-end.
**Last updated:** 2026-03-01

---

## What already exists (no work needed)

| Piece | Location |
|---|---|
| `Chat.create_family/1` | `chat.ex:64` |
| `Households.add_member/3` | `auth/households.ex:22` |
| `ConversationService.create_direct_conversation/2` | `chat/conversation_service.ex` |
| `Tokens.issue(:passkey_registration, ...)` | `auth/tokens.ex:66` |
| `Identity.permit_user_attrs/1` | `auth/identity.ex:162` |
| `Famichat.PubSub` process | `application.ex:25` |
| All invite API endpoints (accept, complete) | `auth_controller.ex`, `router.ex` |
| Admin-exists guard pattern | `auth/recovery.ex:241` |

---

## What needs to be built

### 1. `Onboarding.bootstrap_admin/2` + `SetupController`

**What it does:** Creates first admin user + household in a single transaction. Dead after first call.

**Location:** New function in `auth/onboarding.ex`. New `SetupController` (or action in `AuthController`).

**Route:** `POST /api/v1/setup` — in the unauthenticated `:api` scope (NOT in `[:api, :api_authenticated]`).

**Step by step:**
1. Guard: `Repo.exists?(from m in HouseholdMembership, where: m.role == :admin)` — return `410` if true
2. Validate: require `username`, `family_name` from params
3. `Repo.transaction`:
   - `Chat.create_family(%{name: family_name})`
   - `User.changeset(%User{}, attrs) |> Repo.insert()` — use `Identity.permit_user_attrs/1` + add `status: :active, confirmed_at: now`
   - `Households.add_member(family.id, user.id, :admin)`
   - `Tokens.issue(:passkey_registration, %{"user_id" => user.id}, user_id: user.id)`
4. Return `201` with `{user_id, username, household_id, passkey_register_token}`

**Note:** Seeds in `priv/repo/seeds.exs` are stale — they target old schema fields (`role` on user, `family_id` on user) that don't exist. Don't rely on them.

---

### 2. `inviter_id` in invite token payload (3 touch points)

**Why:** `complete_registration` needs to know who the installer is to create the 1:1 conversation. Currently `inviter_id` is in scope during invite issuance but never stored in the token.

**Changes:**

**`invite_payload/2` in `onboarding.ex`** — add `"inviter_id"` to the returned map. The `inviter_id` arg is already present in `do_issue_invite/4`'s scope.

**`accept_invite/1` in `onboarding.ex`** — `sign_invite_registration_token/1` is called with a payload map; add `"inviter_id" => Map.get(invite.payload, "inviter_id")` to that map.

**`sanitize_invite_payload/1` in `onboarding.ex`** — currently strips all keys except `household_id`, `role`, `email_fingerprint`. It does NOT need to expose `inviter_id` to the client — `inviter_id` only needs to be in the signed `registration_token`, which is already a separate path. No change needed here.

---

### 3. Conversation creation inside `complete_registration`

**What:** After user + membership are created, call `ConversationService.create_direct_conversation(inviter_id, invitee_id)` inside the existing transaction.

**Why it's safe:** Ecto joins inner transactions to the outer one via savepoints. The membership row (written earlier in the same transaction) is visible to the `create_direct_conversation` query.

**Change to `complete_registration/2`:** Add after `upsert_membership` step:
```elixir
{:ok, _conversation} <- ConversationService.create_direct_conversation(
  claims["inviter_id"],
  user.id
)
```

Add alias at top of `onboarding.ex`: `alias Famichat.Chat.ConversationService`

**If conversation creation fails:** The existing `Repo.rollback(reason)` path rolls back user creation and membership too. Full atomicity is the right behavior.

**Required env var:** `UNIQUE_CONVERSATION_KEY_SALT` must be set. Add to Docker setup docs and `.env.example`.

---

### 4. PubSub broadcast in `complete_invite/2`

**What:** After `complete_registration` succeeds, broadcast to the household topic so the installer's HomeLive can update live.

**Location:** `auth_controller.ex`, in the `{:ok, result}` branch of `complete_invite/2`. NOT inside `Onboarding` — that module has no web/PubSub dependency.

**Topic:** `"household:#{household_id}"`
**Payload:** `{:household_member_joined, %{user_id: user.id, display_name: user.username, household_id: household_id}}`

**`household_id` gap:** It's not in `complete_registration`'s return value. Simplest fix: extend the return value to include it, or query `HouseholdMembership` by `user.id` after registration. Extend the return value — add `household_id: family.id` to the map returned inside the transaction.

---

### 5. `/invites/:token` route + `InviteLive`

**What:** Browser-facing invite landing page. Not an API route — a LiveView.

**Route placement:** Outside the `scope "/:locale"` wrapper. Standalone top-level scope, `:browser` pipeline, no auth plug:
```elixir
scope "/", FamichatWeb do
  pipe_through :browser
  live "/invites/:token", InviteLive, :index
end
```

**`InviteLive` responsibilities:**
- On mount: validate token format, render welcome gate (Screen V-1 in `onboarding-l1.md`)
- On "Join" click: `POST /api/v1/auth/invites/accept` via JS fetch, store `registration_token` in socket assigns
- Step 2: name entry form — on submit: store username in assigns
- Step 3: trigger passkey ceremony via JS hook, POST to `/api/v1/auth/invites/complete` with `{registration_token, username}`, then immediately trigger passkey assert flow
- On success: navigate to `/` (HomeLive)

**Token passing between steps:** Socket assigns. Do not use Plug session for the registration JWT.

---

### 6. Session bridge — HomeLive auth (critical path)

**The gap:** After passkey assertion, the API returns `{access_token, refresh_token, device_id}` as JSON. There is currently no mechanism to carry these into a LiveView's `mount/3`. HomeLive's current `mount` ignores session entirely.

**Decision needed:** Two options.

**Option A — Plug session cookie (simpler for throwaway views):**
- In `passkey_assert/2` in `auth_controller.ex`, after `Sessions.start_session` succeeds: `put_session(conn, "access_token", access_token)` and `put_session(conn, "user_id", user_id)`
- In HomeLive `mount/3`: read from `session["access_token"]`, call `Sessions.verify_access_token/1`, halt with redirect to `/login` if invalid
- Tradeoff: cookie-stored access token requires CSRF protection (Phoenix's `protect_from_forgery` handles this for LiveView sockets automatically)

**Option B — JS handoff via `sessionStorage` (consistent with SPA pattern):**
- After passkey assert returns tokens, JS stores `access_token` in `sessionStorage`
- JS redirects to `/` — HomeLive mounts
- On LiveView connect, JS sends `access_token` via `push_event("set_auth", %{token: ...})`
- HomeLive `handle_event("set_auth", ...)` verifies and assigns
- Tradeoff: requires JS hook on HomeLive; more complex for a throwaway view

**Recommendation for L1 throwaway:** Option A. The Plug session cookie approach matches how Phoenix auth is conventionally done (Pow, Phx.Gen.Auth), requires no JS hook, and is simpler to delete when SPA takes over. Flag the session cookie as "throwaway — SPA uses sessionStorage handoff."

---

### 7. HomeLive refactor — real session auth + PubSub

**What changes:**
- Remove `ensure_test_user_and_session/2` call in `mount/3`
- Read `user_id` and `access_token` from Plug session (Option A above)
- Verify token via `Sessions.verify_access_token/1` — redirect to `/login` on failure
- Query `HouseholdMembership` by `user_id` to get `household_id` for PubSub subscription
- Add PubSub subscription on connected mount: `Phoenix.PubSub.subscribe(Famichat.PubSub, "household:#{household_id}")`
- Add `handle_info({:household_member_joined, payload}, socket)` — flash "[display_name] joined", navigate to conversation

**Existing spike harness (`SpikeStartLive`, `HomeLive` test user creation):** Leave in place behind a compile-time flag or dev-only route if needed for NIF testing. Don't delete — it's load-bearing for the NIF spike path. Just don't let it be the only path.

---

## Build order (dependency-sorted)

1. **`POST /api/v1/setup` + `bootstrap_admin/2`** — installer can't get in without this
2. **`inviter_id` in invite token payload** — blocks conversation creation
3. **Conversation creation in `complete_registration`** — needs #2; requires `UNIQUE_CONVERSATION_KEY_SALT` in env
4. **Session bridge decision + implementation** — blocks HomeLive auth
5. **HomeLive real-session auth** — needs #4
6. **`/invites/:token` route + `InviteLive`** — can be built in parallel with #4–5
7. **PubSub broadcast in `complete_invite/2`** — needs #3 for `household_id` in return value
8. **HomeLive PubSub subscription + `handle_info`** — needs #5 and #7

---

## Environment variables required

| Var | Used by | Required for |
|---|---|---|
| `UNIQUE_CONVERSATION_KEY_SALT` | `ConversationService.compute_direct_key/3` | Conversation creation (step 3 above) |
| `WEBAUTHN_ORIGIN` | Wax passkey verification | Passkey flows |
| `WEBAUTHN_RP_ID` | Wax passkey verification | Passkey flows |
| `WEBAUTHN_RP_NAME` | Wax passkey verification | Passkey flows |

All four must be set before end-to-end testing is possible.
