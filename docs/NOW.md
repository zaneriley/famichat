# Famichat NOW

**Last updated:** 2026-03-01

Non-evergreen context. For stable design guidance, see [SPEC.md](SPEC.md).

---

## One-line state

Path C (WASM E2EE) is confirmed feasible. Architecture is fully researched. Next work is the E2EE integration layer (key distribution, Welcome routing) + the L1 UI shell (auth, chat view) in parallel.

---

## What just happened (this session)

- OpenMLS WASM spike: all 7 criteria pass with real two-member MLS round-trip. Path C locked in.
  - Report: `docs/spikes/WASM_SPIKE_REPORT.md`
- Full architecture research: MLS lifecycle, backend changes, frontend integration
  - Key finding: LiveView hybrid is the right model (not a full SPA). LiveView owns the shell; JS hook owns message encryption/decryption + DOM.
  - Key finding: `add_member` currently discards the Commit message — this must be fixed before multi-member groups work.
  - Key finding: the WASM `--target nodejs` build is wrong for browser use; needs `--target bundler`.

---

## Immediate next steps (in order)

### 1. Fix the WASM module for browser deployment (blocking for E2EE)
Two gaps that block real browser E2EE:

**a. Commit message is discarded in `add_member`** (`lib.rs` line 451: `let (_commit_msg, welcome, _group_info)`).
- `_commit_msg` must be returned so the server can broadcast it to existing members
- A new `process_commit(group_state, commit_b64)` WASM export is needed so existing members can advance their epoch when someone is added
- Without this: two-member groups work, but adding a third member breaks all existing members

**b. Build target must change**
- Current: `wasm-pack build --target nodejs` (spike/test only)
- Needed: `wasm-pack build --target bundler` for esbuild integration
- Copy output to `priv/static/wasm/` and verify MIME type

### 2. Backend: key package + Welcome infrastructure (blocking for E2EE)
New tables and endpoints needed before any browser E2EE can work:

**New tables:**
- `key_packages` — one row per package, indexed by `(device_id, claimed_at IS NULL)`. Replaces packed `conversation_security_client_inventories` format. Not Vault-encrypted (server cannot read MLS key material).
- `pending_welcomes` — durable inbox for Welcome messages to offline devices: `(target_device_id, conversation_id, welcome_blob, ratchet_tree_blob, delivered_at)`

**New endpoints/channel events:**
- `POST /api/v1/devices/:device_id/key_packages` — device uploads key packages at registration
- `GET /api/v1/devices/:device_id/key_packages/claim` — consume-on-fetch (atomic DELETE + RETURNING)
- Channel event `register_key_package` → broadcasts `new_member_pending` to current group members
- Channel event `deliver_welcome` → stores in `pending_welcomes`; delivers on channel join if pending

**Backend message changes (blocking):**
- Raise `@max_content_bytes` from 8KB to 64KB in `message.ex` (MLS ciphertexts are larger than plaintext)
- `latest_previews/1` in `chat_read_controller.ex` must not try to render ciphertext as preview text

### 3. Build the L1 UI shell (parallel with #2)
These are independent of E2EE and can be built now:
- Real login page with WebAuthn JS (`navigator.credentials.create()` / `.get()`)
- Invite redemption UI
- Replace `home_live.ex` test harness with a real conversation view (LiveView shell)
- Key files: `backend/lib/famichat_web/live/home_live.ex`, `backend/lib/famichat_web/router.ex`

**Architecture:** LiveView owns shell (auth, nav, conversation list). JS hook (`MessageChannelHook`) owns message encryption/decryption. Stop calling `pushEvent("message_received", {body: plaintext})` — the hook manages the message DOM directly, plaintext never goes to the server.

**L1 success criteria:** you + wife use it daily and stop using iMessage/WhatsApp for family messages.

### 4. Wire the JS hook to WASM (after #1 + #2 + #3 are ready)
- New `assets/js/mls/wasm_loader.js` — lazy-loads WASM module once per page
- New `assets/js/mls/state_store.js` — IndexedDB read/write for group state blobs
- Rewrite `MessageChannelHook` receive path: decrypt via WASM, insert DOM directly (no `pushEvent` for content)
- Rewrite send path: `encrypt_message` → write IndexedDB → POST ciphertext

### 5. 66 pre-existing test failures
All in lifecycle, channel, and MLS contract modules. Pre-date this session. Not blocking L1 dogfooding but worth a cleanup pass before wider rollout.

---

## Key decisions locked

| Decision | Details |
|---|---|
| E2EE path | Path C: OpenMLS WASM in browser; confirmed GO per spike |
| Frontend model | LiveView hybrid — shell stays LiveView, hook owns E2EE layer |
| NIF fate | Keep during L0/L1 dogfooding; remove at L3 gate (before other families trust the server) |
| Doc structure | SPEC.md = evergreen; NOW.md = temporal; archive/ = history |
| Security stance | "Impossible, not guarded" — don't hold data you don't need to hold |

---

## Known gaps

**Blocking E2EE (before L3 gate):**
- `add_member` WASM export discards Commit message — multi-member groups broken
- No `process_commit` WASM export — existing members can't advance epoch on member add
- `signer_bytes` (signing private key) in caller-held JS blob — must move to non-extractable Web Crypto key before L3
- No key package table or distribution endpoints
- No durable Welcome delivery for offline devices

**Not blocking L1 dogfooding:**
- `device_id` → MLS leaf index mapping (blocks full revoke→MLS)
- Path A passkey pending-state schema for non-admin device adds
- Production env vars not configured (`WEBAUTHN_ORIGIN`, `WEBAUTHN_RP_ID`, `WEBAUTHN_RP_NAME`)
- Full-text search is architecturally foreclosed on server side — must be client-side when built
- Push notification previews must be content-free (server can't generate them)
