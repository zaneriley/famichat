# Canonical Messaging Flow Runbook

**Status**: Active  
**Purpose**: One deterministic `auth -> subscribe -> send -> receive` drill on the canonical product path.

## Why this runbook exists

This is the shared proof path for humans and LLMs.

It validates:
1. Bearer-authenticated sender can call `POST /api/test/broadcast`.
2. A real channel subscriber receives `new_msg`.
3. Sent messages are persisted and visible via `GET /api/v1/conversations/:id/messages`.
4. Non-happy paths (`401/403/422`) emit no channel message side effects.

## Preconditions

1. Containers are running.
2. You run commands from the repo root.
3. Environment is `dev` or `test`.

## Fast verification (recommended)

Run the end-to-end integration contract:

```bash
cd backend && ./run elixir:test:canonical-flow
```

This command executes:
- auth/session issuance
- channel subscribe
- canonical broadcast send
- message receive assertion
- message history persistence assertion
- non-happy no-broadcast assertions

## Seed data for manual drills

Get stable users/topic plus fresh access tokens as JSON:

```bash
cd backend && ./run runbook:seed
```

Override defaults when needed (hyphenated flags are canonical; underscored forms are also accepted):

```bash
cd backend && ./run runbook:seed \
  --family-name "Runbook Family" \
  --sender-username runbook_sender \
  --receiver-username runbook_receiver
```

Input validation is strict:
1. Unknown flags fail fast.
2. Positional arguments fail fast.
3. `sender_username`/`receiver_username` must be non-empty and different.

If local compile warnings are printed before the JSON, extract only the JSON block with:

```bash
cd backend && ./run runbook:seed | sed -n '/^{/,$p'
```

Output includes:
1. `sender.access_token`
2. `receiver.access_token`
3. `conversation.id`
4. `conversation.topic`
5. canonical payload template

## Timing capture

Use timing around the canonical test command:

```bash
cd backend && /usr/bin/time -f "elapsed=%e s" ./run elixir:test:canonical-flow
```

## Source of truth in code

1. Canonical endpoint: `backend/lib/famichat_web/controllers/message_test_controller.ex`
2. Contract tests (`200/401/403/422` + no-broadcast): `backend/test/famichat_web/controllers/message_test_controller_test.exs`
3. End-to-end runbook integration test: `backend/test/famichat_web/integration/canonical_messaging_flow_test.exs`
4. Seed task: `backend/lib/mix/tasks/famichat.runbook_seed.ex`

## Related Runbook

1. Messaging red-team + RCA + solution triage loop: `docs/runbooks/messaging-redteam-rca-solution-loop.md`
