# Famichat API Design

**Last Updated**: 2026-02-27  
**Status**: Active (v1, no external users yet, breaking changes allowed)

## North Star

1. Production-first API contracts (`/api/v1`) are the source of truth.
2. Test-only routes (`/api/test/*`) are harness utilities, never product contracts.
3. Clients (human, LLM, CLI, alternate frontends) must be able to drive all core messaging/security behavior via stable HTTP + WS contracts.
4. Error handling must be machine-parseable and stable.

## Current Route Surfaces

1. `"/api/v1"`: canonical production API.
2. `"/api/test"`: development/test-only verification helpers, compiled only in `:dev/:test`.
3. `"/socket"`: real-time channel transport.

## Response Envelope Policy (v1)

### Success

```json
{
  "data": {}
}
```

Optional metadata:

```json
{
  "data": {},
  "meta": {}
}
```

### Error

```json
{
  "error": {
    "code": "invalid_request",
    "message": "Optional human-readable summary",
    "action": "Optional client action hint",
    "details": {}
  }
}
```

Rules:

1. `error.code` is required and stable.
2. Never leak `inspect(reason)` or internal exception payloads.
3. Prefer explicit status-code semantics over overloaded `200` responses.

## Status Code Contract

1. `200/201`: success.
2. `204`: idempotent delete/revoke success.
3. `400`: invalid/missing required parameters.
4. `401`: authentication failed/expired.
5. `403`: authenticated but forbidden.
6. `404`: resource not visible/not found.
7. `409`: valid request blocked by security lifecycle state.
8. `413`: payload too large.
9. `422`: semantically invalid request.
10. `429`: rate-limited (with `retry-after` header when possible).

## Stable Error Codes (Messaging + Auth)

Current/approved set:

1. `unauthorized`
2. `invalid_parameters`
3. `invalid_request`
4. `forbidden`
5. `not_found`
6. `rate_limited`
7. `message_too_large`
8. `recovery_required`
9. `conversation_security_blocked`
10. `recovery_in_progress`
11. `recovery_failed`
12. `invalid_refresh`
13. `reauth_required`
14. `invalid_credentials`
15. `invalid_challenge`

## Production Messaging Contract (Target)

Canonical production endpoints:

1. `GET /api/v1/conversations/:id/messages`
2. `POST /api/v1/conversations/:id/messages`
3. `POST /api/v1/conversations/:id/security/recover`

Important:

1. These routes are the product contract for LLM/CLI and alternate clients.
2. `POST /api/test/broadcast` is a legacy harness route and not part of the product contract.
3. `GET /api/v1/conversations/:id/messages` supports reconnect catch-up via `after=<message_id>` and returns:
   - `meta.has_more` (`boolean`)
   - `meta.next_cursor` (`message_id | null`)
   - `422 invalid_pagination` for malformed `after`, foreign-conversation cursors, or incompatible `after + offset`.

## WS Contract Alignment

1. WS `new_msg` payloads should include stable `message_id`.
2. WS error payloads should converge on `error.code` and `action` semantics used by HTTP.
3. `security_state` push events must remain explicit for revoked/recovery-required states.

## Idempotency and Retry

1. Recovery operations require a caller-provided stable `recovery_ref`.
2. Revocation/recovery flows should expose replay-safe semantics (`idempotent: true/false` or equivalent).
3. Future mutation endpoints should accept an `Idempotency-Key` header where retries are expected.

## QA and Verification Policy

1. Primary product verification should run against `/api/v1` + `/socket`.
2. `/api/test/*` is allowed for harness bootstrapping but must not be the only proof path for product behavior.
3. Runbook scenario definitions and runner implementation must stay in lockstep (no doc-only hard gates).

## Near-Term Work (v1 Hardening)

1. Keep QA runner/integration contracts pinned to `/api/v1` routes and remove remaining `/api/test` write-path dependencies.
2. Close response-envelope drift between auth/chat/read/write paths.
3. Landed: cursor-based message catch-up contract on read API (`after` + `meta.has_more` + `meta.next_cursor`) for reconnect continuity.
4. Normalize bearer-token parsing and 401 payloads across trusted + authenticated plugs.

## Related Docs

1. [Architecture](./ARCHITECTURE.md)
2. [Current Sprint](./sprints/CURRENT-SPRINT.md)
3. [Status](./sprints/STATUS.md)
4. [Messaging QA Runbook](./runbooks/messaging-qa-runbook.md)
