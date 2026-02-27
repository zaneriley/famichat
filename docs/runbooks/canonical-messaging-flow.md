# Canonical Messaging Flow Runbook

**Status**: Active  
**Purpose**: One deterministic `auth -> subscribe -> send -> receive` drill on the canonical product path.

## Why this runbook exists

This is the shared proof path for humans and LLMs.

It validates:
1. Bearer-authenticated sender can call `POST /api/v1/conversations/:id/messages`.
2. A real channel subscriber receives `new_msg`.
3. Sent messages are persisted and visible via `GET /api/v1/conversations/:id/messages`.
4. Non-happy paths (`401/404/409/422`) emit no channel message side effects.
5. Revoked connected devices receive explicit `security_state` and do not receive new `new_msg` payloads.
6. Required recovery states are explicit (`recovery_required`) and recovery/rejoin restores messaging.

## Preconditions

1. Containers are running.
2. You run commands from the repo root.
3. Environment is `dev` or `test`.
4. No pending migrations (`cd backend && ./run qa:messaging:preflight`).

## Fast verification (recommended)

Run the end-to-end integration contract:

```bash
cd backend && ./run elixir:test:canonical-flow
```

This command executes:
- auth/session issuance
- channel subscribe
- canonical message send (`201 Created`)
- message receive assertion
- message history persistence assertion
- non-happy no-broadcast assertions

Run recovery/rejoin characterization:

```bash
cd backend && ./run elixir:test test/famichat_web/integration/recovery_rejoin_security_flow_test.exs
```

This verifies:
- missing MLS state fails with explicit `recovery_required`
- `recover_conversation_security_state` succeeds and is idempotent on replay
- post-recovery send succeeds on canonical path

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

For live QA matrix runs (self/direct/group/family + outsider + multi-device),
use:

```bash
cd backend && ./run runbook:seed:matrix | sed -n '/^{/,$p'
```

## Timing capture

Use timing around the canonical test command:

```bash
cd backend && /usr/bin/time -f "elapsed=%e s" ./run elixir:test:canonical-flow
```

Or use the first-class runbook command (writes timing to artifacts):

```bash
cd backend && ./run qa:messaging:fast
```

`qa:messaging:fast` now includes revoked-device and recovery/rejoin gates (`S1..F2 + R1 + R2`) in addition to canonical flow timing artifacts.

Artifacts:
- `.tmp/_qa_messaging/<RUN_ID>/canonical_flow_result.txt`
- `.tmp/_qa_messaging/<RUN_ID>/canonical_flow_timing.txt`
- `.tmp/_qa_messaging/<RUN_ID>/gate_report.json`

## Coverage snapshot capture

Capture canonical-flow coverage in the deep run:

```bash
cd backend && ./run qa:messaging:deep
```

Coverage artifact:
- `.tmp/_qa_messaging/<RUN_ID>/canonical_flow_coverage.txt`
- `.tmp/_qa_messaging/<RUN_ID>/recovery_rejoin_contract.txt` (deep mode recovery/rejoin integration gate)

## Source of truth in code

1. Canonical send/recovery endpoint: `backend/lib/famichat_web/controllers/api/chat_write_controller.ex`
2. API contract tests (`201/401/404/409/422` + no-broadcast): `backend/test/famichat_web/integration/api_chat_write_controller_test.exs`
3. End-to-end runbook integration test: `backend/test/famichat_web/integration/canonical_messaging_flow_test.exs`
4. Seed task: `backend/lib/mix/tasks/famichat.runbook_seed.ex`
5. Revoked-device integration contract: `backend/test/famichat_web/integration/revoked_device_security_flow_test.exs`
6. Recovery/rejoin integration contract: `backend/test/famichat_web/integration/recovery_rejoin_security_flow_test.exs`

## Related Runbook

1. Messaging red-team + RCA + solution triage loop: `docs/runbooks/messaging-redteam-rca-solution-loop.md`
