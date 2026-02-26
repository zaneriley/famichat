# Messaging QA Runbook (Live Probe First)

**Status**: Active
**Purpose**: Prove messaging behavior through live black-box probing (what users experience), then optionally run code-level regression checks.
**Audience**: Engineers and agents performing manual QA and red-team probing.

## 1. Non-Negotiables

1. Bug claims must come from black-box evidence (HTTP/WS/IEX client behavior), not source inspection.
2. One runtime path only: probes must hit real app endpoints and channel flows.
3. Every scenario requires artifacts. No artifacts means no confidence.
4. Required coverage is `self`, `direct`, `group`, and `family` with multi-actor/multi-device permutations.
5. If any required scenario cannot run, the run is `BLOCKED` (not `PASS`).

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

`S1..F2` are hard gates. A run cannot pass without all 8 rows executed with artifacts.

## 7. Probe Command Patterns

### 7.1 HTTP send probe (`curl`)

```bash
BASE_URL="${QA_BASE_URL:-http://localhost:9000}"
A_TOKEN="$(jq -r '.actors.a_tab1.access_token' "$ROOT/seed_matrix.json")"
CONV_ID="$(jq -r '.conversations.direct.id' "$ROOT/seed_matrix.json")"

curl -sS -X POST "$BASE_URL/api/test/broadcast" \
  -H "Authorization: Bearer $A_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"conversation_type\":\"direct\",\"conversation_id\":\"$CONV_ID\",\"body\":\"qa-$RUN_ID-d1\"}" \
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

Each scenario must have its own folder:

```text
.tmp/_qa_messaging/<RUN_ID>/
  S1/
    request.json
    response.json
    ws_A_tab1.log
    ws_A_tab2.log
    ws_A_dev2.log
    ws_B.log
    ws_C.log
    ws_O.log
    assert.json
  S2/
  D1/
  D2/
  G1/
  G2/
  F1/
  F2/
  matrix_results.csv
  gate_report.json
  summary.md
```

Bug output for red-team passes:

```text
.tmp/_bugs/list.md
```

## 9. Assertions Per Scenario (`assert.json`)

Each scenario folder must include:

```json
{
  "scenario_id": "D1",
  "status": "PASS|FAIL",
  "send_status": 200,
  "authorized_receivers": ["A-tab1", "A-tab2", "A-dev2", "B"],
  "unauthorized_receivers": [],
  "persistence_check": "PASS|FAIL",
  "notes": "short factual note"
}
```

## 10. Gate Decision and Severity

Hard pass criteria:
1. `S1..F2` all executed
2. No unauthorized delivery in any scenario
3. Rejected actions produce no side effects
4. Same-user two-tab/two-device behavior matches expected fanout

Severity:
- `S0`: unauthorized visibility/send succeeds, or reject path causes delivery/persistence side effect
- `S1`: wrong fanout/parity creating security or correctness risk
- `S2`: inconsistent behavior without proven cross-boundary leak
- `S3`: evidence hygiene/runbook quality issues

Gate outcome rules:
- Any `S0`/`S1`: run `FAIL`
- Missing required scenario artifacts: run `BLOCKED`
- Only `S2`/`S3`: run `WARN`
- Zero findings with complete evidence: run `PASS`

## 11. Fast Loop (<=10 Minutes)

```bash
cd backend && ./run qa:messaging:fast
```

Fast loop performs:
1. Preflight with migration gate.
2. Matrix seed generation (`runbook:seed:matrix`).
3. Canonical flow timing capture.
4. Live `S1..F2` HTTP matrix with WS parity on success paths.
5. Artifact + gate report generation.

## 12. Deep Loop (<=60 Minutes)

```bash
cd backend && ./run qa:messaging:deep
```

Deep loop extends fast with:
1. Canonical-flow coverage artifact capture (`canonical_flow_coverage.txt`).
2. Full artifact validation and summary for release/nightly runs.

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

1. PR job: run fast live-probe loop and fail on `S0/S1`.
2. Nightly/release job: run deep loop and upload `.tmp/_qa_messaging/<RUN_ID>/` artifacts.
3. Keep regression tests as secondary checks, not primary evidence of user-visible behavior.
4. Preserve migration preflight in CI so pending migrations block QA before probe execution.

## 15. Related Docs

- `docs/runbooks/canonical-messaging-flow.md`
- `docs/runbooks/messaging-redteam-rca-solution-loop.md`
- `_agents/AGENTS.md` (Messaging Invariants and Bug-Bash Gates)
