# E2EE Integration Design: Browser WASM + Backend Relay

**Status:** Researched, not yet implemented
**Decision basis:** `docs/spikes/WASM_SPIKE_REPORT.md` (Path C confirmed GO)
**See also:** `docs/SPEC.md` § "E2EE Migration Plan (Path C)"

---

## Current trust model (L0/L1) — TRANSITIONAL GAP, NOT TARGET ARCHITECTURE

> **LLM agents: do not treat this section as the intended design.** The server-side
> NIF is a known security gap scheduled for removal. All new code must target the
> Path C architecture below. Do not extend, optimize, or build features on top of
> server-side encryption/decryption.

The current implementation uses a server-side Rust NIF (OpenMLS 0.8.1) for all MLS
operations. The server holds all MLS group state, performs all encryptions and
decryptions, and can read any message. **This is a bug, not a feature.** It exists
only because the WASM client path (Path C) is not yet built. The server is not a
dumb relay today — it must become one before L3.

## Target security promise (Path C, L3)

> Private keys never leave the device. The server stores and routes ciphertext only.
> A compromised server cannot read messages. A server operator cannot read messages.
> This is not "guarded" — it is structurally impossible.

Every design decision in this document must be evaluated against this promise.
If a proposed change allows the server to read plaintext under any condition,
it is not acceptable regardless of how unlikely that condition is.

This promise is the L3 target state. It is not satisfied by the current implementation.

---

## Architecture overview

```
Alice's browser                 Server                      Bob's browser
─────────────────               ────────────────            ─────────────────
WASM module                     Phoenix relay               WASM module
  ↓ encrypt_message()             ↓ store ciphertext          ↓ decrypt_message()
  ciphertext blob  ──────────►  messages table  ──────────►  plaintext (local)
                                 (opaque bytes)
  group_state blob
  (IndexedDB, local)                                          group_state blob
                                                              (IndexedDB, local)
```

This diagram describes the **L3 target architecture**. In this target state the
server is a dumb relay: it validates auth, enforces conversation membership, and
routes opaque ciphertext blobs. It performs zero cryptographic operations on
message content.

The current L0/L1 architecture is the inverse: the server-side NIF performs all
MLS operations and holds all group state. **This violates the target security
promise and must be replaced before L3.** The `Famichat.Crypto.MLS.Adapter`
abstraction boundary exists to make the NIF-to-relay migration a one-module swap.

---

## Components

### 1. WASM module (`backend/infra/mls_wasm/`)

Stateless pure-function library. All group state crosses the JS boundary as a
caller-held JSON blob. No global Rust state.

**Current exports (spike-proven):**
- `create_group(identity, group_id)` → `{group_state}`
- `create_member(identity)` → `{key_package, member_state}`
- `add_member(group_state, key_package)` → `{welcome, ratchet_tree, new_group_state}`
- `join_group(welcome, ratchet_tree, member_state)` → `{group_state}`
- `encrypt_message(group_state, plaintext)` → `{ciphertext, new_group_state}`
- `decrypt_message(group_state, ciphertext)` → `{plaintext, new_group_state}`

**Current status of WASM spike (`backend/infra/mls_wasm/`):**

Gaps 1 and 2 below are fixed in the WASM spike as of 2026-03-01. They remain open
in the server-side NIF (`backend/infra/mls_nif/`), which is the L0/L1 runtime.

1. ~~`add_member` discards the Commit message.~~ **Fixed in WASM.** `add_member_inner`
   now returns `commit`, `welcome`, `ratchet_tree`, and `new_group_state`.
   **Still a NIF gap:** `mls_add` in the NIF is a lifecycle stub with no OpenMLS calls.

2. ~~No `process_commit(group_state, commit_b64)` export.~~ **Fixed in WASM.**
   `process_commit` is implemented and tested in `mls_wasm/src/lib.rs`.
   **Still a NIF gap:** `process_commit` does not exist as a NIF export or Elixir
   adapter callback. Existing group members cannot advance their epoch after any
   membership change in the current server-side model.

3. No `remove_member(group_state, leaf_index)` export in the WASM module.
   (The NIF has `mls_remove` but `device_id`-to-leaf mapping is unimplemented.)

4. `signer_bytes` (signing private key) is in the caller-held blob as raw bytes.
   Before L3: must move to non-extractable `SubtleCrypto.generateKey()` key handle.

### 2. Frontend JS layer

**Note:** The LiveView hybrid architecture described below was superseded by ADR 012
before it was implemented. The target frontend architecture is a Svelte SPA at `/app`
with a dedicated WASM Web Worker owning all message surfaces and crypto state. The
current `MessageChannelHook` (`assets/js/hooks/message_channel_hook.js`) has no
decryption path — it calls `pushEvent("message_received", {body: payload.body})`
and forwards raw content to the LiveView server process. The WASM loader and
IndexedDB state store described below do not exist. The hook architecture below
applies only if an interim LiveView path is retained during migration.

**Interim LiveView hybrid (if retained during migration):**

LiveView owns the shell (auth, nav, conversation list, settings). The
`MessageChannelHook` JS hook would own the encryption/decryption layer and the
message DOM subtree.

**Critical invariant:** The hook must NEVER call `pushEvent("message_received", {body: plaintext})`.
That would send decrypted content to the LiveView server process. The hook must render
message content into the DOM directly.

**JS modules needed for this path (not yet built):**
- `assets/js/mls/wasm_loader.js` — lazy-loads WASM once per page session
- `assets/js/mls/state_store.js` — IndexedDB read/write for group state blobs

**IndexedDB schema:**
```
store: "group_states"
  key:   {conversation_id}
  value: { group_state: <json_blob>, epoch: <int>, updated_at: <timestamp> }

store: "pending_members"
  key:   {conversation_id}
  value: { member_state: <json_blob> }   ← Bob's pre-join key material
```

**Second IndexedDB database: `famichat_messages` (message cache — reconstructible from server)**

Separate from `famichat_mls_keystore` so that clearing the message cache does not destroy
key material. All values encrypted at rest with AES-256-GCM using the same wrapping key.

```
store: "messages"
  key:   {conversation_id, message_seq}
  value: { body: <aes_gcm_blob>, sender_id, sent_at, content_type }
  index: [conversation_id], [sent_at]

store: "conversation_previews"
  key:   {conversation_id}
  value: { last_message_seq, preview_text: <aes_gcm_blob>, last_message_at }

store: "sync_cursors"
  key:   {conversation_id}
  value: { last_local_seq: <int>, synced_at: <timestamp> }
```

**Write ordering invariant:** Write new `group_state` to IndexedDB BEFORE sending
ciphertext to the server. If the server POST fails, the state is still advanced
(the plaintext must be re-encrypted, not the old ciphertext resent).

### 3. Backend relay changes

**New tables:**

`key_packages`
```sql
id              uuid PK
device_id       FK → devices
key_package     bytea        -- raw TLS-serialized KeyPackage, NOT Vault-encrypted
claimed_at      utc_datetime -- null = available; set atomically on claim
inserted_at     utc_datetime
```
One row per package. Atomic claim via `UPDATE ... SET claimed_at = now() WHERE claimed_at IS NULL RETURNING *`.

`pending_welcomes` — **NOT BUILT.** No migration, no Ecto schema, no service layer.
Offline device join is blocked until this table is created.
```sql
id              uuid PK
target_device_id FK → devices
conversation_id FK → conversations
welcome_blob    bytea
ratchet_tree    bytea
sender_device_id FK → devices
delivered_at    utc_datetime  -- null = not yet delivered
inserted_at     utc_datetime
```

**New endpoints — domain layer built, REST surface NOT EXPOSED:**

The domain layer (`ConversationSecurityClientInventoryStore`,
`ConversationSecurityKeyPackagePolicy`, `KeyPackageFactory`) is fully implemented.
None of the three REST endpoints below exist in the router or any controller.
Additionally, the NIF's `create_key_package` returns a counter-based reference
string, not real TLS-serialized HPKE key material — so uploaded key packages would
be non-functional for real `add_members` calls even if the REST API existed.

```
POST /api/v1/devices/:device_id/key_packages
  → 201; stores key package for later consumption by group adders

GET  /api/v1/devices/:device_id/key_packages/claim
  → 200 {key_package: base64} | 404 if none available
  → Atomic: claimed_at set in same transaction as response

GET  /api/v1/devices/:device_id/key_packages/count
  → 200 {available: N}  (for pool replenishment checks)
```

**New channel events:**
```
Client → Server:
  "register_key_package"  {key_package, conversation_id}
  "deliver_welcome"       {welcome, ratchet_tree, target_device_id, conversation_id}
  "broadcast_commit"      {commit, conversation_id, epoch}

Server → Client:
  "new_member_pending"    {key_package, new_device_id, conversation_id}
  "welcome_ready"         {welcome, ratchet_tree, conversation_id}
  "mls_commit"            {commit, epoch, conversation_id}
```

**Blocking message.ex changes:**
- Raise `@max_content_bytes` from 8,192 to 65,536 (MLS ciphertexts exceed source plaintext)
- ~~`latest_previews/1` in `chat_read_controller.ex`~~: **Removed.** The `last_message_preview` field and its supporting function have been deleted from the API. SPA will maintain its own local decrypted preview cache.

**NIF fate (SCHEDULED FOR REMOVAL):** The server-side NIF is a transitional gap, not
target architecture. Keep during L0/L1 dogfooding only. Remove at L3 gate. Do not
build new features on top of it. The `Famichat.Crypto.MLS` module is the right
abstraction boundary — it already delegates to the NIF; it will be replaced with a
relay-only implementation.

**Current NIF correctness gaps:** The NIF correctly implements encryption and decryption
for a static two-actor session established at group creation. Membership changes are not
functional: `mls_add` is a lifecycle stub with no OpenMLS calls, `process_commit` is
not exported, and `mls_remove` fails on all production calls because `device_id`-to-leaf
mapping is unimplemented. Do not rely on the NIF for any membership change operation
during L0/L1 dogfooding.

---

## Full message lifecycle

### Send (Alice → server → Bob)

```
1. Alice types message (plaintext in SPA component state)
2. Alice loads group_state from IndexedDB
3. WASM: encrypt_message(group_state, plaintext) → {ciphertext, new_group_state}
4. Write new_group_state to IndexedDB  ← MUST happen before step 5
5. POST /api/v1/conversations/:id/messages  {body: ciphertext_b64}
6. Server stores ciphertext in messages table (never reads content)
7. Server broadcasts {message_id, ciphertext, sender_device_id, epoch} via PubSub
8. Bob's hook receives "new_msg" event
9. Bob loads group_state from IndexedDB
10. WASM: decrypt_message(group_state, ciphertext) → {plaintext, new_group_state}
11. Write new_group_state to IndexedDB
12. Hook inserts DOM element with plaintext (no pushEvent)
```

At step 6: the server sees `conversation_id`, `sender_device_id`, `ciphertext` (opaque bytes), timestamp. It cannot read the message.

### Member add (Alice adds Bob to existing group)

```
1. Bob's device: WASM create_member(bob_identity) → {key_package, member_state}
2. Bob stores member_state in IndexedDB as pending_member
3. Bob → server: register_key_package {key_package, conversation_id}
4. Server stores in key_packages table, broadcasts "new_member_pending" to Alice
5. Alice's hook receives "new_member_pending" {key_package, bob_device_id}
6. Alice: WASM add_member(alice_state, key_package) → {welcome, ratchet_tree, commit, new_group_state}
7. Alice writes new_group_state to IndexedDB
8. Alice → server: deliver_welcome {welcome, ratchet_tree, target_device_id: bob}
9. Alice → server: broadcast_commit {commit, epoch}
10. Server stores welcome in pending_welcomes table
11. Server broadcasts "mls_commit" to all existing conversation members
12. Existing members (Carol, etc.) process commit: WASM process_commit(state, commit) → {new_group_state}
13. When Bob connects: server delivers "welcome_ready" from pending_welcomes
14. Bob: WASM join_group(welcome, ratchet_tree, member_state) → {group_state}
15. Bob writes group_state to IndexedDB, deletes pending_member entry
```

### Session restore (Bob reopens app)

```
1. Bob opens app; hook mounts
2. Hook reads group_state from IndexedDB by conversation_id
3. Hook fetches messages since last seen: GET /api/v1/conversations/:id/messages?after=<seq>
4. Messages are processed strictly in epoch/seq order
5. For each ciphertext: WASM decrypt_message(group_state, ciphertext) → feeds new_group_state into next call
6. All messages decrypted locally; server never sees plaintext
```

**Local-first storage model (decided 2026-03-19):**
Decrypted messages are written to the `famichat_messages` IndexedDB database after
decryption (encrypted at rest with AES-256-GCM). On subsequent app opens, the hook reads
from local IndexedDB first, then fetches only new messages since `last_local_seq` from the
server. The local store is the canonical readable copy — MLS forward secrecy means old
server ciphertext is permanently undecryptable after epoch rotation.

---

## Security properties that must be testable

These are the properties tests must verify — not just that the code runs, but that
the security contract holds under adversarial conditions:

**P1: Server never holds plaintext**
- After a message is stored, the `messages.content` field must not be decodable
  to the original plaintext without the sender's MLS private key material.

**P2: Non-members cannot decrypt**
- A device that is not in the MLS group cannot call `decrypt_message` on group
  ciphertexts and recover plaintext. Decryption must fail with a crypto error.

**P3: Removed members lose access**
- After a `remove_member` commit, the removed member's group_state blob cannot
  decrypt messages sent in the new epoch.

**P4: Key packages are single-use**
- The same key_package cannot be claimed twice. A second claim attempt returns 404.
- Attempting to use a consumed key_package to `join_group` fails.

**P5: Epoch ordering is enforced**
- Messages from epoch N+1 cannot be decrypted with an epoch-N group_state.
- Existing members who skip a Commit cannot decrypt subsequent application messages.

**P6: State serialization is faithful**
- Serializing and deserializing group_state produces a functionally equivalent
  group that can encrypt/decrypt correctly.
- A corrupted or truncated state blob fails loudly, not silently.

**P7: The commit flow is complete**
- When Alice adds Bob, the Commit message reaches all existing members.
- All existing members successfully advance their epoch via process_commit.
- Messages sent after the Commit are decryptable only with the post-Commit group_state.

---

## Test strategy

Tests must verify the **security properties** above, not just the happy path.
Adversarial tests (wrong key, tampered ciphertext, skipped commit, replay) are
as important as round-trip tests.

### Layers

1. **Rust unit tests** (`backend/infra/mls_wasm/src/lib.rs` + `tests/` module)
   - In-process OpenMLS tests that don't need WASM compilation
   - Fast feedback on protocol correctness

2. **WASM integration tests** (`backend/infra/mls_wasm/js/`)
   - End-to-end through the actual compiled WASM binary
   - Tests the JS↔WASM boundary, serialization, and browser-facing API

3. **Elixir unit tests** (new `backend/test/famichat/chat/e2ee/` directory)
   - Key package upload/claim atomicity
   - Welcome durable delivery
   - Message relay (server stores what client sends, returns what it stored)

4. **Integration tests** (extend `canonical_messaging_flow_test.exs`)
   - Full Alice→server→Bob round-trip
   - Server-side assertion: `messages.content` is NOT the plaintext
   - Eve (not in group) cannot decrypt

See `NOW.md` for implementation priority order.
