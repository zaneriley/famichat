# E2EE Integration Design: Browser WASM + Backend Relay

**Status:** Researched, not yet implemented
**Decision basis:** `docs/spikes/WASM_SPIKE_REPORT.md` (Path C confirmed GO)
**See also:** `docs/SPEC.md` § "E2EE Migration Plan (Path C)"

---

## Security promise

> Private keys never leave the device. The server stores and routes ciphertext only.
> A compromised server cannot read messages. A server operator cannot read messages.
> This is not "guarded" — it is structurally impossible.

Every design decision in this document must be evaluated against this promise.
If a proposed change allows the server to read plaintext under any condition,
it is not acceptable regardless of how unlikely that condition is.

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

The server is a **dumb relay**: it validates auth, enforces conversation membership,
and routes opaque ciphertext blobs. It performs zero cryptographic operations on
message content after Path C cutover.

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

**Known gaps (must fix before multi-member groups work):**

1. `add_member` discards the Commit message (`_commit_msg` at `lib.rs:451`).
   The Commit must be returned so the server can broadcast it to existing members.
   Without this, adding a third member breaks all existing members (wrong epoch).

2. No `process_commit(group_state, commit_b64)` export.
   Existing members receiving a Commit cannot advance their epoch.

3. No `remove_member(group_state, leaf_index)` export.

4. Build target must be `--target bundler` for browser + esbuild (currently `--target nodejs`).

5. `signer_bytes` (signing private key) is in the caller-held blob as raw bytes.
   Before L3: must move to non-extractable `SubtleCrypto.generateKey()` key handle.

### 2. Frontend JS layer

**Architecture:** LiveView hybrid. LiveView owns the shell (auth, nav, conversation
list, settings). The `MessageChannelHook` JS hook owns the encryption/decryption
layer and the message DOM subtree.

**Critical invariant:** The hook must NEVER call `pushEvent("message_received", {body: plaintext})`.
That would send decrypted content to the LiveView server process. The hook renders
message content into the DOM directly.

**New JS modules needed:**
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

`pending_welcomes`
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

**New endpoints:**
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
- `latest_previews/1` in `chat_read_controller.ex`: return `nil` for content; client
  computes preview from locally-decrypted cache. Do not display ciphertext bytes as preview.

**NIF fate:** Keep during L0/L1 dogfooding (server-side MLS for current sessions).
Remove at L3 gate. The `Famichat.Crypto.MLS` module is the right abstraction boundary —
it already delegates to the NIF; it will be replaced with a relay-only implementation.

---

## Full message lifecycle

### Send (Alice → server → Bob)

```
1. Alice types message (plaintext in React/hook component state)
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
