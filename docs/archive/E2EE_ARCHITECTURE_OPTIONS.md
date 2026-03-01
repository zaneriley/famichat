# E2EE Architecture Options for Famichat

**Date**: 2026-03-01
**Status**: Strategic exploration — not yet committed
**Audience**: Stakeholders making the architecture pivot; handoff to implementation teams

---

## Executive Summary

Famichat currently violates true end-to-end encryption (E2EE) semantics: MLS keys are held server-side in a Rust NIF DashMap, and the server decrypts all messages to render them in LiveView. This analysis evaluates 4 realistic paths to fix this, given the constraints: 100-500 person self-hosted instances, tight team, family/neighborhood UX expectations, and 2700+ lines of hardened NIF code already in place.

**Recommendation**: Path **C (SPA + Server as Pure API/Relay)** with **C.1 staged migration via iframe bridge**. It maximizes client-side key control, salvages ~70% of the Rust NIF, reuses the proven REST API contract, and gets you to real E2EE in 6–8 weeks of focused work. Paths A and D are architectural dead-ends or half-measures. Path B is viable long-term but requires 12+ weeks and mobile expertise you may not have.

---

## The Current State (As of 2026-03-01)

### What You Have Now

| Component | Status | Lines | Notes |
|-----------|--------|-------|-------|
| OpenMLS NIF (lib.rs) | Hardened | 2,723 | Track A security gates, N1–N7 NIF hardening, H1–H4 panic safety all in place |
| MLS Elixir adapter | Stable | 180 | Middleware contract layer; call_adapter pattern for N1 lock poisoning handling |
| ConversationSecurityLifecycle | Stable | 300+ | Epoch validation, pending-commit orchestration, revocation gates; core business logic |
| ConversationSecurityStateStore | Stable | 500+ | Optimistic locking, snapshot MAC (N5), durable state schema, recovery path |
| MessageService | Stable | 600+ | Send/read pipelines, encryption metadata whitelisting, broadcast gating (S1), narrow rescues (S3) |
| MessageChannel (WebSocket) | Stable | 200+ | Real-time delivery, device auth checks, telemetry |
| Auth (Passkeys + OTP) | Hardened | 800+ | Real WebAuthn ECDSA sig verify, CSPRNG random OTP, UV flag checks, enumeration-resistant errors |
| REST API v1 | Canonical | ~600 | `GET /api/v1/conversations/:id/messages`, `POST /api/v1/conversations/:id/messages`, `/socket` |

### The Core Problem

**Current trust model**: "Server is trust anchor" — but the server can decrypt everything because the server holds the keys and decrypts to render LiveView.

**What "real E2EE" means here**: Private MLS keys are generated on and confined to the user's device. The server stores and forwards encrypted blobs it cannot decrypt. Messages are encrypted before leaving the device and decrypted only on the receiving device.

**Why it matters for this use case**:
- Neighborhood scale assumes the admin is somewhat trustworthy (they control the infrastructure).
- But "somewhat trustworthy" ≠ "can read all family medical, financial, relationship details in group chats."
- Parents want confidence their kids' conversations with each other are private from the server.
- A compromised server (or a bad-faith admin) should not automatically decrypt all messages retroactively.

---

## Architectural Constraints (What You Can't Change)

1. **Self-hosted, not SaaS**: Each instance has one admin; no federation.
2. **Family/neighborhood use**: 100–500 people; intimate group dynamics; kids, parents, grandparents.
3. **LiveView is disposable**: Current web UI is intentionally a spike harness. You're willing to replace it.
4. **OpenMLS is the direction**: ADR 010 accepted; Signal is historical. MLS is RFC 9420; OpenMLS 0.8.1 is the implementation.
5. **Rust NIF is hardened and tested**: 2,723 lines with Track A security gates, N1–N7 hardening. You don't want to throw it away.
6. **Multi-device sync is hard**: Users will have phone + tablet + laptop. Key material must be synchronized securely across devices, or each device has its own ephemeral key (weaker).
7. **Server still coordinates**: Even with client-side keys, the server stores conversation state, membership lists, message ordering, and acts as a relay.
8. **Small team**: Can't build native iOS + Android + Web simultaneously. Need to prioritize.

---

## Path A: LiveView Shell + WASM Client-Side MLS (Hybrid)

### Architecture

```
┌─────────────────────────────┐
│  Phoenix LiveView           │
│  ├─ Layout/Nav (Elixir)     │
│  ├─ iframe container        │
│  │  └─ WASM MLS app         │
│  │     ├─ IndexedDB (keys)  │
│  │     ├─ openmls-wasm      │
│  │     └─ Message UI        │
│  └─ Broadcast/Presence      │
└──────┬──────────────────────┘
       │ /socket (no encrypted payload)
       │ /api/v1/... (relay only)
       │
┌──────▼──────────────────────┐
│  Phoenix Backend            │
│  ├─ Conversation state      │
│  ├─ Message store (cipher)  │
│  └─ No MLS decryption       │
└─────────────────────────────┘
```

### How It Works

1. **Key generation & storage**: openmls-wasm generates MLS keys on browser first load; stored in IndexedDB. JavaScript never touches raw key material (openmls-wasm Rust lib manages keys internally).
2. **Encryption**: Message typed in WASM app → openmls-wasm encrypt → ciphertext to server.
3. **Decryption**: Ciphertext from server → openmls-wasm decrypt → plaintext in WASM app.
4. **LiveView role**: Navigation, sidebar, presence indicators, conversation list — all rendered server-side; message content iframe is isolated.
5. **Multi-device sync**: **Hard problem**. Each device generates its own MLS key package. Server adds device to group. But keys are siloed in IndexedDB per browser. If you want to read old messages on a new device, you need to either:
   - Re-join the group (lose access to old messages pre-add).
   - Ship the key material somehow (encrypted backup? iCloud keychain on iOS? not yet built).

### MLS NIF Salvage Rate

- **~40%**: The NIF's state store, snapshot MAC (N5), and validation logic could move to server as "dumb relay" state. But openmls-wasm has its own state management; you'd be running MLS twice (once in WASM, once in Rust NIF for server-side book-keeping).
- **Not worth it**: The Rust NIF is optimized for server-side full group state management. WASM MLS is a separate implementation (different API surface, different state model). Code reuse is minimal.

### Migration Complexity

- **Medium-to-Large**: 6–10 weeks.
- Create openmls-wasm build (or use existing wasm-bindgen crate if one exists; OpenMLS has limited WASM story as of 2026-03).
- Migrate message send/read to WASM iframe.
- Rewrite MessageChannel to handle ciphertext blobs only.
- Test multi-device onboarding.

### Key Tradeoffs

| Pro | Con |
|-----|-----|
| Keys never leave browser (true E2EE for web) | Multi-device sync is broken — user gets siloed keys per browser |
| Reuses LiveView for nav/presence (UX continuity) | WASM cold start & IndexedDB perf will feel sluggish vs native |
| Server has no decryption path (strong security story) | Each device can't read group history pre-add (UX friction) |
| Can still emit ciphertext to WebSocket for real-time | Requires JavaScript & IndexedDB (harder for grandparent with old browser) |
| Salvage 40% of NIF code | Two parallel MLS implementations = maintenance burden |
| | Iframe sandbox model is fragile; cross-iframe secrets are hard |

### Key Management for "Wife Gets a New Phone"

1. Wife adds new device → `POST /api/v1/conversations/:id/add_device` → new key package generated in WASM on new device.
2. New device joins group as new MLS member.
3. Old messages on old device: **still visible in IndexedDB on old device**. New device **cannot decrypt** messages sent before it joined.
4. Going forward: messages post-join are decrypted on both devices independently.
5. **Workaround**: Back up old device's IndexedDB to file, import on new device. But that's not built, not secure, and user-hostile.

**This is a deal-breaker for family use.** A parent wanting to check on a teen's group chat history after getting a new phone can't do it.

### Verdict

**Not recommended.** Multi-device is a non-negotiable for family use, and this breaks it. You'd end up building device key sync anyway, at which point you're back to the same complexity as Path C with worse code reuse.

---

## Path B: Native iOS + Android + Server as Pure Relay

### Architecture

```
┌─────────────────────────────┐    ┌────────────────────────┐
│  iOS App (SwiftUI)          │    │  Android App (Compose) │
│  ├─ Keychain (keys)         │    │  ├─ EncryptedSharedPrefs│
│  ├─ openmls Rust via FFI    │    │  ├─ openmls Rust (JNI) │
│  ├─ Message UI              │    │  └─ Message UI         │
│  └─ Background sync         │    └────────────────────────┘
└──────┬──────────────────────┘
       │ Rest API + WebSocket (ciphertext only)
       │
┌──────▼──────────────────────┐
│  Phoenix Backend            │
│  ├─ REST API relay          │
│  ├─ WebSocket relay         │
│  ├─ Message store (cipher)  │
│  └─ No MLS decryption       │
└─────────────────────────────┘
```

### How It Works

1. **Key generation & storage**: MLS keys generated on iOS Keychain / Android EncryptedSharedPrefs on first app launch. Never leaves device.
2. **Encryption**: Message composed → openmls (native FFI) encrypt → ciphertext to server.
3. **Decryption**: Ciphertext from server → openmls (native FFI) decrypt → plaintext in UI.
4. **Multi-device sync**: Each device is an MLS group member. Keys are device-specific, stored in Keychain/EncryptedSharedPrefs. To read old messages on a new device, the new device must be added to the MLS group (server initiates add). Post-add, new device can decrypt future messages. Old messages (pre-add) are inaccessible. **But** you can implement server-side key derivation or a separate key-wrap ceremony (user enters a recovery code, derives old key on new device, decrypts key backup).
5. **Web client**: Defer web UI entirely for now. Focus on mobile.

### MLS NIF Salvage Rate

- **~80%**: The Rust NIF's state management, snapshot MAC, validation, and DashMap persistence is completely **unnecessary**. Native apps call openmls directly via FFI/JNI. The NIF becomes dead code.
- **Why 80% and not 0%?** You could keep a read-only "server shadow" of MLS state for auditing/debugging, but it's optional.

### Migration Complexity

- **Large**: 12–16 weeks.
- Hire iOS + Android engineers (or skill-up existing team).
- Implement openmls FFI bindings for Swift (via bridging headers or RustBridge crates like `swift-bridge`).
- Implement openmls JNI bindings for Kotlin.
- Build Keychain/EncryptedSharedPrefs integration.
- Implement multi-device key sync ceremony (recovery code, key backup).
- Test on 3+ iOS versions, 4+ Android versions.
- Build app distribution pipeline (TestFlight, Google Play internal testing).
- Zero web UI for now (existing LiveView can stay as admin dashboard only).

### Key Tradeoffs

| Pro | Con |
|-----|-----|
| True E2EE: keys never leave device | Requires hiring or training iOS/Android developers |
| Multi-device sync works cleanly (each device is an MLS member) | 12–16 week timeline; slower to market |
| Keychain/EncryptedSharedPrefs are battle-tested by every banking app | No web UI for ~6 months; unfamiliar for grandparents |
| Native UI is expected by users; can leverage OS capabilities | App store review cycles; distribution complexity |
| Server is genuinely pure relay; even stronger security story than C | Must maintain 2 codebases (iOS + Android) + backend |
| No JavaScript, no WASM concerns | Testing multi-device scenarios is painful |

### Key Management for "Wife Gets a New Phone"

1. **Standard flow**: Wife buys new iPhone → downloads app → logs in with passkey → app generates new MLS key pair in Keychain.
2. New device is added to group as MLS member.
3. Old messages on old phone: **still in local SQLite/Realm DB on old phone**. New phone **cannot decrypt** messages sent pre-add.
4. **Optional: recovery code ceremony**:
   - User generates recovery code on old device (one-time, printed/saved).
   - On new device, enter recovery code → derive key → decrypt encrypted backup of old MLS state.
   - New device can now decrypt old messages.
   - (This is what Signal does; WhatsApp doesn't support this and users lose message history on new devices.)

**This is acceptable for family use if you implement the recovery code path.** But it's a 3–4 week feature sprint.

### Verdict

**Viable, but only if you have mobile experts and can dedicate 3+ months to it.** If you have JavaScript developers only, and mobile is a 2025 ambition, this is a 2026-Q4 project, not a Q1 move. Path C is better for the current team.

---

## Path C: SPA (React/Svelte) + Server as Pure API/Relay

### Architecture

```
┌─────────────────────────────────────┐
│  React/Svelte SPA (client-side)     │
│  ├─ openmls-wasm bundle             │
│  ├─ LocalStorage (keys + metadata)  │
│  ├─ Message UI (no iframe)          │
│  └─ Account settings                │
└──────┬──────────────────────────────┘
       │ REST API v1 + WebSocket (ciphertext only)
       │
┌──────▼──────────────────────────────┐
│  Phoenix Backend (unchanged)         │
│  ├─ /api/v1/conversations/:id/msgs  │
│  ├─ /api/v1/conversations/:id/msg   │
│  ├─ /socket (WebSocket relay)       │
│  ├─ Conversation state              │
│  ├─ Message store (encrypted)       │
│  ├─ Auth (passkeys, sessions)       │
│  └─ NO MLS decryption               │
└─────────────────────────────────────┘
```

### How It Works

1. **Key generation**: On first login, SPA generates MLS key pair locally. Stored in browser LocalStorage (or sessionStorage if you're paranoid, but then keys are lost on refresh).
2. **Encryption**: Message typed in SPA → openmls-wasm encrypt → ciphertext sent to `/api/v1/conversations/:id/messages` (POST).
3. **Decryption**: SPA fetches ciphertext from `/api/v1/conversations/:id/messages` (GET) → openmls-wasm decrypt → render in UI.
4. **Real-time**: WebSocket still works; server broadcasts ciphertext blob to all subscribers. SPA decrypts locally.
5. **Multi-device sync**: **Option 1 (ephemeral keys per browser)**—same as Path A; messy. **Option 2 (device key sync)**—user provides a master recovery key (12-word phrase) on first login. On second device, user enters recovery key → derives per-device MLS key from master. Server adds new device to group. Post-add, new device can decrypt future messages and (with a local sync ceremony) old messages via re-encryption or key derivation.

### Path C.1: Staged Migration via iframe Bridge (Recommended)

**Minimize rewrite risk**: Keep LiveView as the outer shell; replace message area with iframe that hosts the SPA.

```
┌──────────────────────────────────────────┐
│  Phoenix LiveView (outer shell)          │
│  ├─ Nav, sidebar, conversation list      │
│  ├─ Elixir telemetry, broadcast mgmt     │
│  └─ iframe (message area)                │
│     └─ React/Svelte SPA                  │
│        ├─ openmls-wasm                   │
│        ├─ Message encrypt/decrypt        │
│        └─ Message UI                     │
└──────────────────────────────────────────┘
```

**Benefits**:
- Keep working LiveView infra for nav/presence.
- Incrementally migrate to SPA (one conversation type at a time).
- Reuse the same REST API (`/api/v1/...`).
- Test crypto integration independently from navigation.
- Rollback is easy: just keep iframe hidden.

**Timeline**: 6–8 weeks.

### MLS NIF Salvage Rate

- **~70%**: The NIF's serialization logic, snapshot MAC (N5), validation gates, error handling, and hardening patterns all stay. The *server-side MLS group state management* (DashMap GROUP_SESSIONS, stage/merge/commit orchestration) is **no longer needed**. You remove `create_group`, `mls_commit`, `mls_remove`, `mls_add`, `mls_update`, `merge_staged_commit` — and you **keep** the data structures and error codes for potential server-side audit logging or deterministic group state validation.
- **Reality**: You'll likely delete ~1,000 lines of NIF code (group state ops) and ~400 lines of Elixir (ConversationSecurityLifecycle, ConversationSecurityStateStore). The rest (error handling, telemetry, snapshot MAC, serialization utils) is reusable for server-side validation of client-submitted payloads.

### Migration Complexity

**Path C (SPA, no LiveView bridge)**: 8–12 weeks.
- Build SPA (React/Svelte).
- Integrate openmls-wasm.
- Rewrite UI for message send/receive/search/etc.
- Test multi-device scenarios.
- Deprecate LiveView gradual.

**Path C.1 (iframe bridge, staged)**: 6–8 weeks.
- Week 1–2: Set up iframe bridge, REST API compatibility layer.
- Week 2–3: Build React/openmls-wasm proof-of-concept (single direct conversation).
- Week 3–5: Expand to group conversations, device management.
- Week 5–6: Multi-device sync ceremony (recovery key).
- Week 6–8: Testing, performance tuning, rollout gates.

### Key Tradeoffs

| Pro | Con |
|-----|-----|
| **No native app dev** — JavaScript team can execute immediately | WASM cold start & bundle size (~3–5 MB openmls-wasm + bundler); users feel initial load lag |
| Keys are in browser process; never leave device | Browser sandboxing is weaker than native Keychain/EncryptedSharedPrefs |
| Server API is **exactly what you have now** (v1 unchanged) | LocalStorage is not inaccessible via XSS; need CSP + no-eval to mitigate |
| Salvage **70% of NIF code** — error handling, serialization, snapshot MAC | Grandparents using old/slow browsers may struggle with JavaScript SPA |
| Multi-device sync is cleanly solvable via recovery key | Recovery key management is a UX problem (users lose them) |
| **Fastest path to real E2EE** (6–8 weeks) | WebSocket message sync is eventually-consistent; need client-side conflict resolution |
| Can iterate quickly on UX (React hot reload) | |

### Key Management for "Wife Gets a New Phone"

**Recommended flow**:
1. Wife logs in on original device → app generates recovery key (12-word phrase) → displayed once, user writes it down.
2. Wife gets new phone → downloads SPA → logs in with passkey → **selects "Have a recovery key?"** → enters 12-word phrase.
3. SPA derives per-device MLS key from recovery key + device ID hash.
4. Server adds new device to group (as new MLS member).
5. New device can decrypt future messages immediately.
6. For old messages: **Option A (easier)**: old messages remain on old device only; user accepts history loss on new device (what WhatsApp does). **Option B (better)**: implement server-side re-encryption ceremony — send old messages to new device's public key, then decrypt locally (what Signal does, ~2 week feature).

**Verdict**: Acceptable. User needs to save recovery key once; subsequent device onboarding is smooth.

### Verdict

**Recommended path.** Fastest to real E2EE (6–8 weeks), maximizes code salvage (70% NIF), reuses proven REST API, and fits the current team's skill set. Path C.1 (iframe bridge) further reduces risk by letting you keep LiveView for nav/presence while incrementally migrating.

---

## Path D: Keep Server-Side MLS + Strong Operator Trust Model + Attestation

### Architecture

```
┌──────────────────────────────┐
│  Phoenix LiveView (unchanged) │
│  ├─ Message UI               │
│  └─ Auth                      │
└──────┬───────────────────────┘
       │ /socket (plaintext → MLS on server)
       │
┌──────▼──────────────────────────────────────┐
│  Phoenix Backend (extended)                  │
│  ├─ MLS NIF (unchanged)                      │
│  ├─ SERVER-SIDE KEY MANAGEMENT:              │
│  │  ├─ Hardware security module (HSM)        │
│  │  │  or sealed/encrypted key store         │
│  │  ├─ Key rotation policy (monthly?)        │
│  │  ├─ Audit log (all decrypt operations)    │
│  │  └─ Operator attestation (signed policy)  │
│  ├─ Message store (encrypted)                │
│  ├─ Zero-knowledge proofs (optional)         │
│  └─ Compliance reporting                     │
└───────────────────────────────────────────────┘
```

### How It Works

1. **Key storage**: MLS keys are held in HSM (Hardware Security Module, e.g., AWS CloudHSM) or a sealed/encrypted datastore (e.g., `EVM sealed storage`, or just `encrypted key file + key derivation from a password that the admin manually enters once at startup).
2. **Operator attestation**: The admin signs a statement: *"I will not decrypt messages for surveillance; I will only decrypt in response to legal subpoena."* This is stored in the app repo and checked on startup.
3. **Audit log**: Every MLS decrypt operation is logged with user, conversation, timestamp. Log is immutable (written to append-only ledger or shipped to a secure external service).
4. **Zero-knowledge proofs** (optional, future): Client submits a ZK proof that they *can* decrypt a message, without revealing the plaintext to the server. Server checks the proof and returns the message if valid. This is research-stage and not production-ready.
5. **Compliance reporting**: Neighborhood admin can request a compliance report: *"Show me all decrypts in Q1."* Report is cryptographically signed and auditable.

### MLS NIF Salvage Rate

- **100%**: No code changes. The entire Rust NIF stays exactly as-is. ConversationSecurityLifecycle, ConversationSecurityStateStore, all hardening from Track A — untouched.

### Migration Complexity

- **Small**: 2–4 weeks (just add HSM integration + audit logging + policy doc).
- The infrastructure lift is real (setting up CloudHSM costs $$$; self-hosted HSM requires dedicated hardware).
- But the code changes are minimal.

### Key Tradeoffs

| Pro | Con |
|-----|-----|
| **Zero code refactoring** — NIF and Elixir unchanged | **Does NOT provide real E2EE.** The server still decrypts everything. |
| Fastest to implement (2–4 weeks) | Relies entirely on **operator honesty**. A subpoenaed or compromised admin can decrypt retroactively. |
| Reuses all existing hardening (Track A, N1–N7) | HSM setup costs $$$ and requires ops expertise. |
| Strong audit trail if the admin is honest | Attestation is legally meaningless in most jurisdictions. |
| Good for "we trust our admin" narrative (neighborhoods often do) | If a kid's device is hacked, attacker can still read all server state. |
| | Doesn't solve multi-device key sync. |

### Verdict

**Not a real solution; a stopgap.** This is the "security theater" option. It works if your use case is "we have a trusted neighborhood admin and we want to detect if they're being dishonest," but it doesn't solve the core problem: **the server can decrypt everything.** A bad-faith operator, a court order, or a compromised server will still leak all message plaintext.

**Only viable if you explicitly reframe the product as "encrypted at rest + audit trail" rather than "end-to-end encrypted."** That's a different value proposition (closer to corporate email + DLP).

---

## Comparison Table

| Dimension | A (WASM+iframe) | B (Native iOS/Android) | C (SPA+REST) | D (Operator trust+HSM) |
|-----------|---|---|---|---|
| **Real E2EE?** | Yes (browser only) | Yes (device only) | Yes (browser+device) | **No** — server decrypts |
| **Multi-device history?** | Broken; siloed keys | Needs recovery code feature (3 wk) | Works cleanly with recovery key | Doesn't apply |
| **Timeline** | 6–10 wk | 12–16 wk | **6–8 wk** | 2–4 wk |
| **NIF salvage** | 40% | 0% | **70%** | 100% |
| **Team skill req** | JS/React + WASM + crypto | iOS + Android engineers | JS/React + WASM + crypto | Ops + infra + compliance |
| **Web UX** | Okay (LiveView + iframe) | None for 6+ mo | **Excellent** (modern SPA) | Okay (unchanged) |
| **Mobile UX** | None; web only | **Excellent** (native iOS/Android) | Okay (responsive web) | None; web only |
| **Grandparent-friendly?** | Maybe (LiveView nav) | Yes (just an app) | Medium (need browser) | Yes (unchanged) |
| **Server-side cost** | Low (relay mode) | Low (relay mode) | **Low** (relay mode) | High (HSM setup) |
| **Operator can read messages?** | No | No | **No** | **Yes, always** |
| **Risk to team** | Medium (WASM cold start, iframe isolation) | High (mobile dev expertise) | **Low** (proven React + WASM stack) | Low (minimal code change, but false premise) |
| **Recommended?** | No; multi-device broken | Yes, but late (3+ mo) | **Yes, now** | No; not real E2EE |

---

## Detailed Recommendation: Path C.1 (SPA + iframe Bridge)

### Why This Path Wins

1. **Fastest to real E2EE**: 6–8 weeks. You can ship client-side key control by end of Q1 2026.
2. **Salvages 70% of NIF code**: Error handling, snapshot MAC (N5), serialization utils, validation logic stays. You delete ~1,000 lines of group state ops (create_group, commit, etc.), but the hardening (N1–N7) is reusable for server-side validation.
3. **Current team can execute**: JavaScript developers with React/Svelte experience can build this. No hiring. No mobile expertise needed.
4. **Reuses the canonical REST API**: The `/api/v1/conversations/:id/messages` endpoints are already proven. SPA just changes the payload from plaintext to ciphertext.
5. **Staged rollout**: The iframe bridge lets you keep LiveView working while incrementally migrating message areas. Low risk of breaking the entire app.
6. **Multi-device works**: Recovery key ceremony is a known pattern (Signal, Wire). 3–4 week feature sprint once the core E2EE is done.
7. **Server truly can't decrypt**: Once you remove the NIF group ops and decrypt call, the server is genuinely a relay + audit trail. Not security theater.

### Implementation Roadmap

**Phase 1 (Weeks 1–2): Foundation**
- Set up React/Svelte SPA scaffold.
- Add openmls-wasm as dependency. (Check if OpenMLS has a maintained WASM build; if not, fork & build one.)
- Set up iframe bridge: LiveView outer shell, SPA iframe for message area.
- REST API compatibility layer: add `ciphertext` field to message schema, keep `body` nullable for rollback.

**Phase 2 (Weeks 2–3): Single Conversation Proof-of-Concept**
- Implement key generation in SPA on first load (stored in localStorage, encrypted with passkey salt).
- Implement `send_message` for direct conversations: plaintext → openmls-wasm encrypt → POST to `/api/v1/conversations/:id/messages` (ciphertext in body).
- Implement `get_messages`: fetch ciphertext → openmls-wasm decrypt → render.
- Test locally with 2 users, 1 conversation.

**Phase 3 (Weeks 3–5): Scale to Groups + Device Management**
- Implement group message send/receive.
- Implement device enrollment flow: user logs in on second browser → app generates new device key package → server adds device to group.
- Test with 3+ devices, 2+ group conversations.

**Phase 4 (Weeks 5–6): Multi-Device Sync Ceremony (Recovery Key)**
- Generate recovery key on first login (12-word BIP39 phrase).
- On second device, user enters recovery key → app derives per-device MLS key.
- Server adds new device to group.
- New device can decrypt future messages.
- **(Optional, defer to Phase 5)**: Implement old message sync via re-encryption or key derivation.

**Phase 5 (Weeks 6–8): Testing, Performance, Hardening**
- Load testing: can SPA handle 500+ messages in a conversation?
- WASM bundle size optimization (tree shaking, compression).
- Implement WebSocket ciphertext relay (server broadcasts encrypted messages to all subscribers; SPA decrypts locally).
- Add offline message queue: if user goes offline, messages sent are queued locally and synced when online.
- Implement message search (decryption + client-side indexing).
- Audit logging: all decrypt operations logged to server (for compliance).

### Critical Implementation Decisions

**1. Key Storage: localStorage vs sessionStorage vs IndexedDB**

| Storage | Pro | Con |
|---------|-----|-----|
| **localStorage** | Persistent; survives page refresh | Survives XSS; requires strong CSP + no-eval |
| **sessionStorage** | Lost on page close (ephemeral) | Keys lost on refresh; worse UX |
| **IndexedDB** | Persistent + can be encrypted | More complex API; still needs CSP |
| **In-memory (state)** | Can't be XSS'd | Keys lost on refresh; mobile browser may kill page |

**Recommendation**: localStorage with strong CSP (Content-Security-Policy: no-eval, no-unsafe-inline, script-src: self). Keys are encrypted with a passkey-derived salt, so they're not readable even if localStorage is exfiltrated.

**Alternative**: IndexedDB with client-side encryption. More secure, but slower.

**2. Multi-Device Key Sync: Recovery Key vs Cloud Backup**

| Method | Pro | Con |
|--------|-----|-----|
| **Recovery key (12-word phrase)** | User-controlled; no cloud dependency | User must write down and remember phrase |
| **iCloud Keychain / Google Play protection** | Automatic; no user action | Locked to specific platform; requires trusted cloud service |
| **Encrypted cloud backup (user-controlled server)** | Flexible; user can host backup server | User must trust the backup server; operational burden |

**Recommendation**: Recovery key first. Build cloud backup as an opt-in feature later.

**3. Message Search**

Encrypted message search is hard. Options:
- **Client-side search**: Decrypt all messages locally, index in memory. Works for small conversations (<1000 msgs), slow for large ones.
- **Server-side encrypted search**: Use order-preserving encryption (OPE) or searchable symmetric encryption (SSE). Not production-ready.
- **Disable search**: Users can't search encrypted messages. Worst UX.

**Recommendation**: Client-side search for MVP. Document the limitation. Upgrade to SSE in Q3 if it becomes a pain point.

**4. Ciphertext Format**

Decide once: how are MLS-encrypted blobs serialized?

```json
// Option A: Opaque blob
{
  "id": "...",
  "sender_id": "...",
  "conversation_id": "...",
  "body": "<base64-encoded MLS ciphertext>",
  "ciphertext": null,
  "created_at": "..."
}

// Option B: Detailed MLS envelope (future-proof for PCS/PFS auditing)
{
  "id": "...",
  "sender_id": "...",
  "conversation_id": "...",
  "body": null,
  "ciphertext": {
    "mls_version": "1.0",
    "ciphersuite": "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519",
    "epoch": 42,
    "ciphertext": "<base64>",
    "signature": "<base64>"  // [optional] server-side signature for audit
  },
  "created_at": "..."
}
```

**Recommendation**: Option B. It's self-documenting, future-proofs the schema for compliance auditing, and lets you add server-side signature verification without changing the API later.

**5. WebSocket Real-Time Sync**

Current LiveView broadcasts plaintext. New flow:
- User A sends message → encrypts locally → POST to `/api/v1/conversations/:id/messages` → server stores ciphertext.
- Server broadcasts ciphertext to all subscribers on `/socket`.
- User B receives ciphertext on WebSocket → decrypts locally → renders in UI.

No changes to the WebSocket protocol; just the payload type (plaintext → ciphertext).

### Sunset Path: LiveView → SPA

Once the SPA is feature-complete and tested, you have a choice:
- **Keep iframe bridge indefinitely**: Navigation stays in LiveView (leverages Elixir HTML rendering, Presence, etc.), message area is in SPA.
- **Full SPA migration (Q2 2026)**: Rewrite navigation in React/Svelte, deprecate LiveView entirely. This is a smaller project because it's just UI cosmetics; all the crypto is already done.

### Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| WASM bundle is slow to load | Pre-load openmls-wasm on first login; cache in service worker. |
| Keys in localStorage can be XSS'd | Enforce strict CSP; audit dependencies for supply-chain risk; add key rotation. |
| Multi-device keys get out of sync (user edits key on device A, doesn't sync to device B) | Each device is an independent MLS group member; no shared key to sync. Each device's MLS state is local-only. |
| Server still sees metadata (conversation, sender, timestamp) | Correct; E2EE doesn't hide metadata. This is acceptable for family use (neighbors can see who's talking to whom, but not what they're saying). |
| Recovery key is lost → user can't access new device | Implement "recovery contacts" feature (Q3): user designates a trusted family member who can help recover the key via a ceremony. Or implement Cloud Backup option. |
| openmls-wasm is unmaintained | Fork & maintain it yourself, or contribute to OpenMLS WASM support. OpenMLS is active; they'll accept PRs. Worst case, you compile openmls to WASM via wasm-bindgen yourself (~1 week). |

---

## NIF Code Salvage Details

### What Stays (Reusable)

```rust
// error.rs / error handling
pub enum ErrorCode {
    InvalidInput,
    UnauthorizedOperation,
    StaleEpoch,
    PendingProposals,
    CommitRejected,
    StorageInconsistent,
    CryptoFailure,
    UnsupportedCapability,
    LockPoisoned,
}

// snapshot.rs / serialization + MAC
serialize_snapshot_raw_data()
deserialize_snapshot_raw_data()
snapshot_mac_sign()
snapshot_mac_verify()

// validation.rs / group state invariants
validate_group_id()
validate_ciphersuite()
validate_key_package()

// crypto / basic utilities
decode_hex()
encode_hex()
```

### What Gets Deleted (Group State Ops)

```rust
// All of these become no-ops or are removed entirely
fn nif_create_group() → DELETED
fn nif_mls_add() → DELETED
fn nif_mls_remove() → DELETED
fn nif_mls_update() → DELETED
fn nif_mls_commit() → DELETED
fn nif_merge_staged_commit() → DELETED

// SERVER-side group state management
static GROUP_SESSIONS: DashMap<String, GroupSession> → DELETED
struct GroupSession { ... } → DELETED
struct MemberSession { ... } → DELETED

// Snapshot storage for server-side state
SNAPSHOT_SENDER_STORAGE_KEY → keep (metadata key)
SNAPSHOT_RECIPIENT_STORAGE_KEY → keep (metadata key)
```

### What Stays in Elixir

```elixir
# backend/lib/famichat/chat/message_service.ex
def send_message(user, conversation, %{body: plaintext, ...}) do
  # ✅ Keep: encryption metadata validation (S2 whitelist)
  # ✅ Keep: broadcast gate (S1 ensure_socket_device_active)
  # ✅ Keep: narrow rescues (S3)
  # ❌ Delete: MLS.create_application_message() call
  # Instead: rely on client-side MLS encryption in SPA
  {:ok, message}
end

def get_conversation_messages(conversation_id, opts) do
  # ✅ Keep: all of it
  # Just change the payload type from plaintext to ciphertext
  {:ok, messages}
end

# backend/lib/famichat/chat/conversation_security_lifecycle.ex
# ❌ Delete the entire module or mark as deprecated
# OR ✅ Keep it for server-side audit logging / compliance reporting
#   (e.g., log what messages were decrypted by the admin for legal reasons)

# backend/lib/famichat/chat/conversation_security_state_store.ex
# ❌ Delete group state persistence (conversation_security_states table)
# ✅ Keep snapshot MAC logic if you want server-side integrity checks
#   (e.g., client submits a message + client-generated MLS proof; server validates the proof)
```

### What Stays in Tests

- All Track A security gate tests (S1–S6, P1–P4).
- All N1–N7 NIF hardening tests.
- All H1–H4 panic safety tests.
- **Deprecate**: ConversationSecurityLifecycle tests (no longer orchestrates MLS).
- **Add new**: Client-side MLS encryption/decryption E2E tests (React + openmls-wasm).

---

## Honest Assessment: "Is the NIF a Sunk Cost?"

**Short answer**: 30% sunk, 70% reusable.

The Rust NIF is **not** a sunk cost because:
1. **Error handling patterns** (N1 lock poisoning, try_lock unwrap safety) are solid and reusable for other Rust-Elixir boundaries.
2. **Snapshot MAC (N5)** is a core E2EE security feature; you'll need it server-side for compliance/audit logging.
3. **Serialization + validation** logic is independent and useful for server-side validation of client payloads.
4. **Test suite** (17/17 Rust tests passing) validates the hardening; you keep those tests.

The 30% sunk cost is:
1. **DashMap-based group state management** (GROUP_SESSIONS, MemberSession, GroupSession structs).
2. **Stage/merge/commit orchestration** in Elixir (ConversationSecurityLifecycle).
3. **Persistent conversation_security_states** schema (can be deprecated).

But here's the key: **even the "sunk" parts are not wasted effort**. The group state ops were necessary to validate the OpenMLS contract and prove the architecture was sound. You couldn't have jumped straight to client-side MLS without first implementing server-side MLS. The sunk cost is the cost of learning.

---

## Final Recommendation

**Go with Path C.1 (SPA + iframe bridge) now. Plan Path B (native iOS/Android) for Q3 2026.**

### Immediate (Q1 2026, starting now)

1. **Weeks 1–2**: React/openmls-wasm proof-of-concept. Validate that openmls-wasm exists and compiles; if not, fork OpenMLS and build WASM bindings yourself (~1 week overhead).
2. **Weeks 2–8**: Implement Phases 1–5 above. Aim for single conversation E2EE by end of February; multi-device by end of March.
3. **Go-live gate**: Phase 4 (recovery key) + comprehensive testing. No production rollout until multi-device works and users can recover their keys.

### Q2 2026

1. Deprecate server-side MLS group ops (delete 1,000 lines of NIF + Lifecycle code).
2. Add audit logging for compliance (which decrypts were requested by admin).
3. Build advanced features: message search, voice messages, photo sharing.

### Q3 2026 (if you have mobile expertise)

1. Hire or upskill iOS + Android engineers.
2. Build native apps (openmls FFI on iOS, JNI on Android).
3. Implement Keychain/EncryptedSharedPrefs key storage.
4. Implement recovery code ceremony.
5. Soft-launch native apps (TestFlight, internal testing).

### What You Tell Stakeholders Now

**Current state**: "Messages are encrypted at rest and in transit, but the server can decrypt them because it holds the keys. This is appropriate for self-hosted family use with a trusted admin, but it's not end-to-end encrypted (E2EE)."

**Path C (SPA) outcome**: "By Q1 2026, messages will be encrypted client-side before leaving the user's device. The server stores ciphertext and acts as a relay; the server can never decrypt messages. This is true E2EE for the web."

**Path B (native) outcome**: "By Q3 2026, iOS and Android users will have true E2EE with device-specific keys stored in Keychain/EncryptedSharedPrefs. Web users will continue to use the SPA. Both platforms share the same encrypted backend; multi-device sync works seamlessly."

---

## Appendix: OpenMLS WASM Availability (As of 2026-03-01)

**Status unknown in my knowledge cutoff.** Before committing to Path C, verify:

1. Does OpenMLS have an official WASM build / wasm-bindgen bindings?
2. If not, can you fork openmls-rs and add WASM support via `wasm-bindgen`? (~1 week effort)
3. What's the bundle size of openmls-wasm? (Target: <2 MB gzipped)
4. Does the openmls-wasm API match the Rust API well enough for your use case?

**Recommendation**: Spike this in Week 1. If WASM is not viable, reconsider Path B.

---

## References

1. OpenMLS Book - Performance: https://book.openmls.tech/performance.html
2. RFC 9420 - MLS: https://www.rfc-editor.org/info/rfc9420
3. RFC 9750 - MLS Architecture: https://www.rfc-editor.org/info/rfc9750
4. ADR 010 - MLS-First Direction (Famichat): `docs/decisions/010-mls-first-for-neighborhood-scale.md`
5. Signal Protocol & Multi-Device Design: https://signal.org/docs/
6. WASM + Crypto: https://github.com/rustwasm/wasm-bindgen (Rust WASM guide)

---

**Document Version**: 1.0
**Last Updated**: 2026-03-01
**Author**: Architecture Analysis (Famichat Team)
**Status**: Ready for stakeholder review and decision
