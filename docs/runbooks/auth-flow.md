# Authentication flow

## Admin bootstrap (`/setup`)

1. First visit: enter username + optional family name
2. `bootstrap_admin/2` creates an `:active` admin user, family, membership, and passkey registration token
3. Advisory lock prevents concurrent bootstrap
4. If browser closes after step 2 and the instance is still in the single-user, no-passkey state, the public entry points redirect back to `/setup` and that page resumes at the passkey step
5. Passkey registration via `PasskeyAdminSetup` hook
6. On success: the passkey is registered and the session cookie is set by the register endpoint
7. Generate invite link(s) for family members
8. Once recovery no longer applies, `/setup` redirects away to `/login`
9. "Go to your family space" links to `/` (no re-auth needed)

## Invite acceptance (`/invites/:token`)

1. `ValidateInviteToken` plug gates structurally malformed tokens (404)
2. `accept_invite/1` consumes the token on first mount
3. On reconnect, `peek_invite/1` recovers payload without re-consuming
4. If registration was started but passkey setup was not finished yet, `peek_invite/1` re-issues a registration token and the flow resumes
5. If invite already completed (an active user tied to that invite exists), returns `:already_completed`
6. Username form with min 2 / max 50 character validation
7. Passkey registration via `PasskeyRegister` hook
8. Once `step1-complete` fires (passkey_register_token set), "Go back" button is hidden
9. On success: 1.5 s confirmation, then redirect to `/`

## Login (`/login`)

1. If session already has a valid access token, redirects to `/`
2. `PasskeyLogin` hook drives discoverable credential assertion
3. On success: session cookie set by assert endpoint, navigates to `/`

## Logout (`/:locale/logout`)

1. `SessionController.delete/2` clears all session data
2. Redirects to `/:locale/login`

## Session lifecycle

- `SessionRefresh` plug runs on authenticated routes (home)
- Expired sessions redirect to login
- `PendingUserReaper` GenServer sweeps abandoned `:pending` users every 15 minutes

## Error states

- Invalid/expired invite: shows explanation + "Already have an account? Sign in" link
- Completed invite reuse: shows "already used" message + sign-in link
- Unsupported browser: fatal passkey error with go-back option
