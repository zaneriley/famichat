# E2EE Architecture Decision — Executive Summary

**Date**: 2026-03-01
**Recommendation**: **Path C.1 (SPA + iframe bridge)**
**Timeline**: 6–8 weeks to real E2EE
**Team impact**: JavaScript/React developers; no mobile expertise required

---

## The Problem

Famichat currently violates end-to-end encryption (E2EE): the server holds MLS private keys and decrypts all messages to render them in LiveView. A compromised server (or bad-faith admin) can read all family conversations retroactively.

## The Solution

Move MLS key generation and encryption to the client browser. The server becomes a relay that stores and forwards ciphertext it cannot decrypt. Real E2EE.

## Why Path C.1 Wins

| Criterion | Path A (WASM+iframe) | Path B (Native) | **Path C.1 (SPA)** | Path D (Operator trust) |
|-----------|---|---|---|---|
| **Real E2EE?** | Yes | Yes | **Yes** | No |
| **Timeline** | 6–10 wk | 12–16 wk | **6–8 wk** | 2–4 wk |
| **Multi-device works?** | ❌ Broken | ✅ (needs recovery code) | ✅ (with recovery key) | N/A |
| **NIF salvage** | 40% | 0% | **70%** | 100% |
| **Team can execute?** | ✅ JS | ❌ Needs iOS+Android | **✅ JS** | ✅ Ops |
| **Server truly can't decrypt?** | Yes | Yes | **Yes** | **No** |

**Path C.1 advantages**:
- Fastest to real E2EE (6–8 weeks vs. 12–16 for native).
- Salvages ~70% of the hardened Rust NIF code (error handling, snapshot MAC, validation).
- Current team can execute immediately (JavaScript developers).
- Reuses the proven REST API `/api/v1/...`.
- Staged rollout: keep LiveView for nav, replace message area with encrypted SPA iframe. Low risk.
- Multi-device sync works cleanly via recovery key (12-word phrase).

**Why not the others**:
- **Path A**: Multi-device breaks (each browser gets siloed keys). User can't read old messages on new device. Deal-breaker for families.
- **Path B**: 12+ weeks; requires hiring iOS + Android engineers. Good long-term, but too slow for Q1.
- **Path D**: Not real E2EE. Server can still decrypt. Just security theater. Only viable if you reframe product as "encrypted at rest" not "end-to-end encrypted."

---

## What Happens to the Rust NIF?

**Not a sunk cost.** ~70% is reusable:

**Keep (~1,700 lines)**:
- Error handling patterns (N1 lock poisoning safety).
- Snapshot MAC (N5) — still needed for server-side compliance/audit logging.
- Serialization + validation utilities.
- All Track A security hardening tests.

**Delete (~1,000 lines)**:
- DashMap-based group state management (GROUP_SESSIONS, MemberSession).
- Stage/merge/commit orchestration in NIF.
- Persistent conversation_security_states table (can be deprecated).

**Deleted code was not wasted**: It validated the OpenMLS contract. You couldn't have jumped straight to client-side MLS without first proving the architecture server-side.

---

## Implementation Roadmap

### Phase 1 (Weeks 1–2): Foundation
- Set up React/Svelte SPA + openmls-wasm.
- Create iframe bridge: LiveView outer shell, SPA message area.
- Validate openmls-wasm exists; if not, fork OpenMLS and build WASM bindings (~1 week overhead).

### Phase 2 (Weeks 2–3): Single Conversation PoC
- Key generation in SPA (stored in localStorage, encrypted).
- Encrypt on send; decrypt on receive.
- Test with 2 users, 1 conversation.

### Phase 3 (Weeks 3–5): Groups + Multi-Device
- Implement group encryption.
- Implement device enrollment (each device is an MLS group member).
- Test with 3+ devices, multiple conversations.

### Phase 4 (Weeks 5–6): Recovery Key Ceremony
- Generate 12-word recovery key on first login.
- On new device, user enters recovery key → derive device key → join group.
- Multi-device messaging works seamlessly.

### Phase 5 (Weeks 6–8): Testing & Hardening
- Load testing, WASM optimization.
- WebSocket real-time sync for encrypted messages.
- Offline queue; message search (client-side).
- Audit logging for compliance.

**Go-live gate**: Phase 4 (recovery key) works reliably. No production rollout until multi-device is tested.

---

## Key Management for "Wife Gets a New Phone"

1. Wife logs in on original device → app generates recovery key (12-word phrase) → she writes it down.
2. Wife gets new phone → logs in with passkey → enters recovery key → app derives per-device key → server adds device to group.
3. New device can decrypt all future messages immediately.
4. Old messages: user keeps them on old device; new device has "history loss" (acceptable; what WhatsApp does). Or implement re-encryption ceremony later (Q2, ~2 weeks).

**Acceptable for family use.** User needs to save one recovery key; subsequent device onboarding is smooth.

---

## Risk & Mitigation

| Risk | Mitigation |
|------|-----------|
| WASM bundle is slow | Pre-load on first login; cache in service worker. |
| Keys in localStorage can be XSS'd | Strict CSP + audit dependencies. Keys are already encrypted. |
| Multi-device keys out of sync | Each device is an independent MLS member; no shared key to sync. |
| Recovery key is lost | Build "recovery contacts" feature (Q3): user designates trusted family member for key recovery. Or optional cloud backup. |
| openmls-wasm is unmaintained | Fork & maintain it, or contribute to OpenMLS. Worst case: compile to WASM yourself (~1 week). |

---

## What You Tell Users Now vs. Q1 2026

**Now**: "Messages are encrypted at rest and in transit. The server can decrypt them (it holds the keys). This is appropriate for self-hosted family use with a trusted admin, but it's not end-to-end encrypted."

**After Path C (by end of Q1)**: "Messages are encrypted on your device before leaving your phone/computer. The server stores ciphertext and acts as a relay. The server can never decrypt your messages. This is true end-to-end encryption (E2EE)."

---

## Next Steps

1. **This week**: Verify openmls-wasm is viable (or fork + build WASM bindings).
2. **Week 1–2**: Spike Phase 1 (iframe bridge + SPA scaffold).
3. **Week 2–8**: Execute Phases 2–5.
4. **End of March**: Ship multi-device E2EE to production.

---

## Full Details

See `docs/E2EE_ARCHITECTURE_OPTIONS.md` for:
- Detailed architectural diagrams for each path.
- NIF code salvage breakdown.
- Ciphertext format design decisions.
- Multi-device sync strategies.
- Message search, recovery contacts, cloud backup options.
- Long-term roadmap (Path B native apps in Q3).

---

**Recommendation**: Approve Path C.1. Start Phase 1 spike immediately. Aim to decide on openmls-wasm viability by end of this week.
