# Messaging QA Runbook (Live Probe First)

**Status**: Active
**Purpose**: Prove messaging behavior through live black-box probing (what users experience), then optionally run code-level regression checks.
**Audience**: Engineers and agents performing manual QA and red-team probing.

## 1. Non-Negotiables

1. Bug claims must come from black-box evidence (HTTP/WS/IEX client behavior), not source inspection.
2. One runtime path only: probes must hit real app endpoints and channel flows.
3. Every scenario requires artifacts. No artifacts means no confidence.
4. Required coverage is `self`, `direct`, `group`, and `family` with multi-actor/multi-device permutations, plus revoked-device and recovery/rejoin enforcement.
5. If any required scenario cannot run, the run is `BLOCKED` (not `PASS`).
6. Run only one `qa:messaging:*` command at a time; overlapping runs invalidate WS/HTTP timing evidence.

## 2. Runbook Shape

1. Preflight (<=2 minutes)
2. Seed deterministic context
3. Live Probe Matrix (primary gate)
4. Artifact validation
5. Gate decision (`S0`-`S3`)
6. Optional regression safety net (tests/lint/coverage)

## 3. Tooling (Standard, Minimal, Semantically Clear)

Primary tools:
- `./run qa:messaging:preflight`
- `./run runbook:seed:matrix`
- `./run qa:messaging:fast`
- `./run qa:messaging:deep`
- `curl`
- `jq`
- `node` (WebSocket probe client used by `qa:messaging:*`)
- `tmux` (recommended for multi-actor sessions)
- `iex -S mix` (allowed for runtime interaction when useful)

Secondary tools (not primary proof):
- `./run elixir:test:canonical-flow`
- `./run elixir:test`
- `./run elixir:test:coverage`
- `./run elixir:lint`
- `./run elixir:static-analysis`
- `./run elixir:security-check`

## 4. Preflight

```bash
set -euo pipefail

cd backend && ./run qa:messaging:preflight
```

Preflight hard-blocks on:
1. Docker/runtime not available.
2. Pending/failed migrations (`mix ecto.migrations` shows any `down` rows).
3. Missing host probe dependencies (`curl`, `jq`, `node`).

## 4.1 First-Class Command Path

```bash
# Fast live matrix with artifacts
cd backend && ./run qa:messaging:fast

# Deep live matrix + canonical-flow coverage artifact
cd backend && ./run qa:messaging:deep
```

Artifacts are written to:

```text
.tmp/_qa_messaging/<RUN_ID>/
```

Seed context now uses matrix actor/conversation data:

```bash
cd backend && ./run runbook:seed:matrix | sed -n '/^{/,$p'
```

## 4.2 Stability Guardrail

If you see repeated `curl` transport errors (for example `Empty reply from server` or timeout), treat that run as invalid environment signal:
1. Stop overlapping `qa:messaging:*` commands.
2. Confirm containers are healthy.
3. Rerun from preflight and keep a single active QA run.
4. If a second run starts while one is active, expect a `BLOCKED` gate report with `reason: qa_run_already_active`.

## 4.3 Runtime Knobs (When Tuning Probe Stability)

`qa:messaging:*` supports these environment overrides:

1. Transport timeout guards:
   - `QA_CURL_CONNECT_TIMEOUT_SECONDS` (default: `3`)
   - `QA_CURL_MAX_TIME_SECONDS` (default: `12`)
2. Shared WS listener readiness:
   - `QA_WS_WAIT_SECONDS` (default: `8`)
   - `QA_WS_READY_TIMEOUT_SECONDS` (default: `10`)
   - `QA_WS_READY_ATTEMPTS` (default: `5`)
   - `QA_WS_READY_RETRY_SLEEP_SECONDS` (default: `1`)
   - `QA_WS_POST_READY_DELAY_SECONDS` (default: `0.5`)
3. Revocation scenario (`R1`) overrides:
   - `QA_WS_WAIT_SECONDS_R1` (default: `12`)
   - `QA_WS_READY_TIMEOUT_SECONDS_R1` (default: inherits shared, fallback `12`)
   - `QA_WS_READY_ATTEMPTS_R1` (default: inherits shared, fallback `5`)
   - `QA_WS_POST_READY_DELAY_SECONDS_R1` (default: `1.5`)
4. Recovery/rejoin scenario (`R2`) overrides:
   - `QA_WS_WAIT_SECONDS_R2` (default: `10`)
   - `QA_WS_READY_TIMEOUT_SECONDS_R2` (default: inherits shared, fallback `12`)
   - `QA_WS_READY_ATTEMPTS_R2` (default: inherits shared, fallback `5`)
   - `QA_WS_POST_READY_DELAY_SECONDS_R2` (default: inherits shared, fallback `1`)

## 5. Actor Model

Minimum actor/device set for each deep run:
- `A-tab1`: sender primary client
- `A-tab2`: same user second tab/socket
- `A-dev2`: same user second device/session
- `B`: authorized peer/member
- `C`: additional authorized member (group/family)
- `O`: outsider/non-member

## 6. Live Probe Matrix (Primary Gate)

| ID | Type | Action | Expected Receivers | Must Not Receive | Expected Status |
|---|---|---|---|---|---|
| S1 | self | `A-tab1` sends to own self | `A-tab1`,`A-tab2`,`A-dev2` | `B`,`C`,`O` | success |
| S2 | self | `A-tab1` attempts send to `B` self | none | all | reject (`403/404`) |
| D1 | direct | `A-tab1` sends in A<->B | `A-*`,`B` | `C`,`O` | success |
| D2 | direct | `O` sends to A<->B conversation | none | all | reject (`403/404`) |
| G1 | group | member `A` sends in group(A,B,C) | `A-*`,`B`,`C` | `O` | success |
| G2 | group | outsider `O` sends to group | none | all | reject (`403/404`) |
| F1 | family | member `A` sends in family conversation | family members + `A-*` | `O` | success |
| F2 | family | outsider `O` sends to family | none | all | reject (`403/404`) |
| R1 | revoked | revoked `A-dev2` is subscribed while healthy sender posts | healthy subscribers only | revoked `A-dev2` gets no `new_msg` and receives explicit `security_state` | success |
| R2 | recovery | reset state, recover with stable `recovery_ref`, replay recovery, then send | authorized members receive post-recovery `new_msg` | no silent recovery failure; replay must be idempotent | success |
| C1 | continuity (pilot) | sender posts while `A-dev2` offline, `A-dev2` joins later, reads history, then sender posts again | `A-dev2` catches missed message via history and receives later `new_msg` live | no gaps/duplicates in message ids | success |

`S1..F2 + R1 + R2` are hard gates. A run cannot pass without all 10 rows executed with artifacts. `C1` is tracked as a pilot scenario until runner support is fully wired.
`qa:messaging:deep` also records `recovery_rejoin_contract.txt` as an additional integration guardrail.
Reject-path scenarios (`S2`, `D2`, `G2`, `F2`) now include a guard observer and must show `guard_ws_parity: pass`.
Runner determinism hardening:
`qa:messaging:*` seeds run-scoped users/families (`<run_id>`-suffixed) and pre-seeds conversation recovery for matrix conversations before probes, so stale prior-message state does not poison history/read assertions.

## 7. Probe Command Patterns

### 7.1 HTTP send probe (`curl`)

```bash
BASE_URL="${QA_BASE_URL:-http://localhost:9000}"
A_TOKEN="$(jq -r '.actors.a_tab1.access_token' "$ROOT/seed_matrix.json")"
CONV_ID="$(jq -r '.conversations.direct.id' "$ROOT/seed_matrix.json")"

curl -sS -X POST "$BASE_URL/api/v1/conversations/$CONV_ID/messages" \
  -H "Authorization: Bearer $A_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"body\":\"qa-$RUN_ID-d1\"}" \
  | tee "$ROOT/D1_response.json"
```

### 7.2 WS subscribe/observe probe (`websocat`)

```bash
WS_URL="${QA_WS_URL:-ws://localhost:9000/socket/websocket?vsn=2.0.0}"
B_TOKEN="$(jq -r '.actors.b.access_token' "$ROOT/seed_matrix.json")"
TOPIC="message:direct:${CONV_ID}"

{
  printf '["1","1","%s","phx_join",{}]\n' "$TOPIC"
  sleep 20
} | websocat -t "${WS_URL}&token=${B_TOKEN}" | tee "$ROOT/D1_ws_B.log"
```

### 7.3 Optional `wscat` equivalent

```bash
NPM_CONFIG_USERCONFIG=/dev/null npx -y wscat --no-color \
  -c "${QA_WS_URL:-ws://localhost:9000/socket/websocket?vsn=2.0.0}&token=$B_TOKEN" \
  -x "[\"1\",\"1\",\"$TOPIC\",\"phx_join\",{}]" \
  -w 4
# send join/new_msg envelopes in phoenix format for the scenario under test
```

### 7.4 `tmux` layout (recommended)

- Pane 1: `A-tab1` WS/log
- Pane 2: `A-tab2` WS/log
- Pane 3: `B` WS/log
- Pane 4: `O` WS/log + curl sends

## 8. Evidence Contract (Required)

Each scenario must have its own folder with generated probe artifacts (exact file names vary by scenario):

```text
.tmp/_qa_messaging/<RUN_ID>/
  S1..F2/
    request.json
    response.json            # present when HTTP probe ran
    history_before.json
    history_after.json
    ws_listener.log          # present for WS-parity scenarios
    ws_guard.log             # present for reject scenarios with guard observer
    assert.json
  R1/
    request.json
    revoke_request.json
    revoke_response.json
    ws_healthy.log
    ws_revoked.log
    assert.json
  R2/
    request.json
    reset_request.json
    reset_response.json
    recover_request.json
    recover_response.json
    recover_replay_response.json
    ws_<observer>.log
    assert.json
  matrix_results.csv
  gate_report.json
  summary.md
```

Bug output for red-team passes:

```text
.tmp/_bugs/list.md
```

## 9. Assertions Per Scenario (`assert.json`)

`assert.json` is scenario-specific and currently includes:

```json
{
  "scenario_id": "D1",
  "status": "PASS|FAIL|BLOCKED",
  "severity": "none|S0|S1|S2|S3",
  "send_status": 200,
  "before_count": 12,
  "after_count": 13,
  "ws_parity": "pass|fail|not_checked|blocked",
  "guard_ws_parity": "pass|fail|not_checked|blocked",
  "notes": "short factual note"
}
```

Additional fields are present for specialized scenarios:
1. `S2`/`D2`/`G2`/`F2`: `guard_ws_parity` must remain `pass` (`fail` means unauthorized fanout leak)
2. `R1`: `revoke_status`, `healthy_has_new_msg`, `revoked_has_new_msg`, `revoked_has_security_state`
3. `R2`: `reset_status`, `recover_status`, `recover_replay_status`, `replay_idempotent`, `observer_has_new_msg`
4. `C1` (pilot): `late_join_history_has_first`, `late_join_live_has_second`, `message_id_continuity`

## 10. Gate Decision and Severity

Hard pass criteria:
1. `S1..F2` all executed
2. `R1` executed with explicit revoked-device evidence (`security_state`, no `new_msg`)
3. `R2` executed with explicit recovery replay idempotency evidence
4. No unauthorized delivery in any scenario
5. Rejected actions produce no side effects
6. Same-user two-tab/two-device behavior matches expected fanout
7. Success-path persistence checks prove message identity in `history_after` (not only count deltas)

Severity:
- `S0`: unauthorized visibility/send succeeds, or reject path causes delivery/persistence side effect
- `S1`: wrong fanout/parity creating security or correctness risk
- `S2`: inconsistent behavior without proven cross-boundary leak
- `S3`: evidence hygiene/runbook quality issues

Gate outcome rules:
- Any required scenario with status `BLOCKED`: run `BLOCKED`
- Any `S0`/`S1`: run `FAIL`
- Missing required scenario artifacts: run `BLOCKED`
- Any lock contention (`reason: qa_run_already_active`): run `BLOCKED` and retry with one active QA run
- Only `S2`/`S3`: run `WARN`
- Zero findings with complete evidence: run `PASS`

Review rule:
1. Always inspect both `blocked_failures` and `critical_failures` arrays in `gate_report.json`; do not rely only on `outcome`.

Implementation note:
- `qa:messaging:*` emits scenario-level `status` values (`PASS|FAIL|BLOCKED`) and a gate-level `outcome` (`PASS|WARN|FAIL|BLOCKED`) in `gate_report.json`.

## 11. Fast Loop (<=10 Minutes)

```bash
cd backend && ./run qa:messaging:fast
```

Fast loop performs:
1. Preflight with migration gate.
2. Matrix seed generation (`runbook:seed:matrix`).
3. Canonical flow timing capture.
4. Live `S1..F2 + R1 + R2` matrix (including revoked-device and recovery/rejoin enforcement) with WS parity on success paths and guard-observer parity on reject paths.
5. Artifact + gate report generation.

## 12. Deep Loop (<=60 Minutes)

```bash
cd backend && ./run qa:messaging:deep
```

Deep loop extends fast with:
1. Canonical-flow coverage artifact capture (`canonical_flow_coverage.txt`).
2. Full artifact validation and summary for release/nightly runs.
3. Automated recovery/rejoin characterization gate (`recovery_rejoin_contract.txt`) to keep explicit `recovery_required` and rejoin behavior under continuous verification.

## 13. Optional Regression Safety Net (Secondary)

These commands help prevent reintroductions, but they do not replace live probing as proof:

```bash
cd backend && ./run elixir:test:canonical-flow
cd backend && ./run elixir:test test/famichat/chat/ test/famichat_web/channels/ test/famichat_web/integration/
cd backend && ./run elixir:test:coverage
cd backend && ./run elixir:lint
cd backend && ./run elixir:static-analysis
cd backend && ./run elixir:security-check
```

## 14. CI Integration Direction

1. PR job: run fast live-probe loop and enforce `gate_report.outcome == PASS`.
2. Nightly/release job: run deep loop, enforce `gate_report.outcome == PASS`, and upload `.tmp/_qa_messaging/<RUN_ID>/` artifacts.
3. Keep regression tests as secondary checks, not primary evidence of user-visible behavior.
4. Preserve migration preflight in CI so pending migrations block QA before probe execution.

## 15. Related Docs

- `docs/runbooks/canonical-messaging-flow.md`
- `docs/runbooks/messaging-redteam-rca-solution-loop.md`
- `_agents/AGENTS.md` (Messaging Invariants and Bug-Bash Gates)
