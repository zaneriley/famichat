# Famichat

Private, self-hosted messaging platform for families and neighborhoods.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Project Status: Alpha](https://img.shields.io/badge/Project%20Status-Alpha-orange)](https://en.wikipedia.org/wiki/Software_release_life_cycle#Alpha)

## Status (2026-02-27)

- Alpha.
- Backend/API and cryptographic lifecycle correctness are the current focus.
- MLS-first E2EE direction is accepted (ADR 010).
- LiveView chat screens are a design and QA spike harness, not a final product client UX.
- Not production-ready for broad user rollout.

## Product Direction

1. Secure, private messaging with fail-closed behavior.
2. Neighborhood-scale group communication with family intimacy.
3. Canonical backend contracts that can be driven by humans, LLM tools, CLI, and alternate frontends.
4. Fast feedback loops via repeatable QA gates and adversarial tests.

## What Works Now

1. Auth and session/device lifecycle APIs.
2. Real-time messaging across self/direct/group/family conversation types.
3. Canonical v1 messaging read/write/recover endpoints.
4. Explicit revoked-device and recovery-required semantics.
5. MLS-backed vertical slice with persisted conversation security state.
6. Repeatable messaging QA gates (`qa:messaging:fast`, `qa:messaging:deep`) with artifacts.

## What Is Still In Progress

1. Deeper MLS lifecycle semantics for commit/update/add/remove under churn.
2. Remaining key lifecycle hardening for production trust posture.
3. Multi-node/state-distribution strategy.
4. Final user-facing product UX (current LiveView is intentionally disposable).
5. Repo-wide lint/static baseline cleanup outside the current MLS slice.

## Quick Start (Local)

Prerequisites:

- Docker and Docker Compose
- Node.js (used by websocket probe tooling in QA runbooks)

Commands:

```bash
cd backend

# Start local stack
docker compose up -d --remove-orphans

# See available task runner commands
./run help

# Focused backend verification
./run qa:messaging:fast
./run qa:messaging:deep
./run docs:boundary-check
```

Local manual spike routes:

1. `http://localhost:9000/admin/spike` (actor-link launcher)
2. `http://localhost:9000/en` (throwaway chat harness over real backend paths)

Note: Port can differ if you changed `backend/.env` (`DOCKER_WEB_PORT_FORWARD` / `PORT`).

## Crypto Stack

```
OpenMLS (Rust library — the actual MLS implementation)
    │
    ├── backend/infra/mls_nif/     ← server-side wrapper (current)
    │   Rustler NIF in the Elixir VM. Holds group sessions in memory.
    │   Server decrypts for LiveView rendering — known gap, not the target.
    │
    └── (planned) mls_wasm/        ← browser-side wrapper (Path C)
        wasm-bindgen targeting wasm32. Keys stay on device.
        Server becomes a dumb relay. Required before other families trust the server.
```

We didn't reimplement MLS — we wrap it. Both the NIF and the future WASM module are thin deployment wrappers around the same library. ~70% of the NIF's crypto logic transfers directly. See [SPEC.md — Security](docs/SPEC.md) for the full decision and migration plan.

## Canonical API Surfaces

1. `GET /api/v1/conversations/:id/messages`
2. `POST /api/v1/conversations/:id/messages`
3. `POST /api/v1/conversations/:id/security/recover`
4. `/socket` (Phoenix channel transport)

`/api/test/*` routes exist only as dev/test harness helpers and are not the product contract.

## Read These Docs First

1. [Design spec (vision, UX, auth, architecture, open questions)](docs/SPEC.md)
2. [Messaging QA runbook](docs/runbooks/messaging-qa-runbook.md)
3. [ADR 010: MLS-first direction](docs/decisions/010-mls-first-for-neighborhood-scale.md)

## Repo Structure

```text
.
├── backend/
│   ├── run
│   ├── lib/
│   ├── test/
│   └── infra/mls_nif/
├── docs/
│   ├── SPEC.md
│   ├── ia-lexicon.md
│   ├── ia-boundary-guardrails.md
│   ├── runbooks/
│   ├── decisions/
│   └── archive/
└── README.md
```

## License

MIT
