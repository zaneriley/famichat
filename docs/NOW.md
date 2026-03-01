# Famichat NOW

**Last updated:** 2026-03-01

Non-evergreen context. For stable design guidance, see [SPEC.md](SPEC.md).

---

## One-line state

Backend security is solid enough for MVP. No human has used this app yet. The single highest-ROI action is building the L1 UI so two people can actually use it daily.

---

## What just happened (this session)

- Consolidated ~40 docs → `SPEC.md` (archived the rest to `docs/archive/`)
- Established E2EE architecture direction: **Path C** (SPA + OpenMLS WASM); server becomes a dumb relay; gate is L3 (before any other family trusts the server)
- Documented that the Rust NIF is ~70% salvageable — the crypto logic transfers, the deployment model changes
- Updated security stance: "impossible, not guarded" — data you don't hold can't be exposed
- Added anti-patterns table to SPEC so bad directions are named and blocked early

---

## Immediate next steps (in order)

### 1. Commit this session's doc work
Conventional commits for: doc consolidation, SPEC creation, archive, E2EE decision, anti-patterns.

### 2. Spike OpenMLS → WASM (days, not weeks)
- Try compiling the existing Rust NIF with the OpenMLS `js` feature flag + `wasm-bindgen`
- This is a binary gate on Path C: if it works cleanly, E2EE path is locked; if blocked, reassess
- File: `backend/infra/mls_nif/Cargo.toml`

### 3. Build the L1 UI (highest user ROI)
The backend is ready. Nothing has been used by a real person yet. What's missing:
- WebAuthn JS (`navigator.credentials.create()` / `navigator.credentials.get()`) — does not exist
- Real login page — does not exist
- Invite redemption UI — does not exist
- `home_live.ex` is a 712-line test harness with hardcoded users; needs to become a real chat view
- Key files: `backend/lib/famichat_web/live/home_live.ex`, `backend/lib/famichat_web/router.ex`

**L1 success criteria:** you + wife use it daily and stop using iMessage/WhatsApp for family messages.

### 4. device_id → MLS leaf mapping (blocks full revoke flow)
`revoke_device` kills the session but the device stays in the MLS group.
- `backend/lib/famichat/chat/device_mls_removal.ex`
- `backend/lib/famichat/chat/conversation_security_client_inventory_store.ex`

### 5. 66 pre-existing test failures
All in lifecycle, channel, and MLS contract modules. Pre-date this session. Worth a cleanup pass before any wider rollout.

---

## Key decisions locked since last reset

| Decision | Details |
|---|---|
| E2EE path | Path C: SPA + OpenMLS WASM; gate before L3 |
| NIF fate | ~70% salvageable; crypto logic transfers; deployment model changes |
| Doc structure | SPEC.md = evergreen; NOW.md = temporal; archive/ = history |
| UI strategy | Keep Phoenix views throwaway and coupled until dogfooding informs design system |
| Security stance | "Impossible, not guarded" — don't hold data you don't need to hold |

---

## Known gaps (not blocking L1)

- Path A (passkey) pending-state schema for non-admin device adds — not built
- `device_id` → MLS leaf index mapping — not built (blocks full revoke→MLS)
- Production env vars not configured (`WEBAUTHN_ORIGIN`, `WEBAUTHN_RP_ID`, `WEBAUTHN_RP_NAME`)
- Test coverage unknown (need `mix coveralls`)
