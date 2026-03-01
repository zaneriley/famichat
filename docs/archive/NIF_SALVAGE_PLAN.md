# Rust NIF Salvage Plan (Path C Implementation)

**Date**: 2026-03-01
**Status**: Implementation guide for Path C.1 migration
**Scope**: What stays, what gets deleted, how to refactor with zero regressions

---

## Current State

| Component | File | Lines | Status |
|-----------|------|-------|--------|
| Core NIF | `backend/infra/mls_nif/src/lib.rs` | 2,723 | Hardened; Track A security gates + N1–N7 |
| Elixir adapter | `backend/lib/famichat/crypto/mls.ex` + `adapter/*.ex` | 500 | Stable; call_adapter pattern |
| Lifecycle | `backend/lib/famichat/chat/conversation_security_lifecycle.ex` | 300+ | Orchestrates stage/merge/clear |
| State store | `backend/lib/famichat/chat/conversation_security_state_store.ex` | 500+ | Durable state + snapshot MAC (N5) |
| Message service | `backend/lib/famichat/chat/message_service.ex` | 600+ | Send/read pipelines |
| Tests | `backend/test/**/*mls*.exs` | 2,000+ | 17/17 Rust tests passing; 66+ Elixir tests |

---

## Salvage Strategy: 70% Reuse, 30% Delete

### Tier 1: Keep (Reusable, No Changes)

These are independent, security-hardened, and directly usable in Path C.

#### Error Handling (lib.rs: lines 19–100+)

```rust
// KEEP: ErrorCode enum and error construction
pub enum ErrorCode {
    InvalidInput,
    UnauthorizedOperation,
    StaleEpoch,
    PendingProposals,
    CommitRejected,
    StorageInconsistent,
    CryptoFailure,
    UnsupportedCapability,
    LockPoisoned,  // N1: Poisoned Mutex safety
}

impl MlsError {
    pub fn invalid_input(details: Payload) -> Self { ... }
    pub fn crypto_failure(details: Payload) -> Self { ... }
    // ... all error constructors
}
```

**Why keep**: These error codes are the contract between client and server. Client-side MLS will still need the same error semantics (stale epoch, invalid input, crypto failure). If client sends a malformed message, server needs to validate and respond with the right error code.

**Usage in Path C**: Server-side validation of client-submitted MLS payloads. Example:
```rust
// Server receives encrypted message from client; validate format
fn nif_validate_application_message(payload: &MlsMessageIn) -> Result<(), ErrorCode> {
    // Check message structure without decrypting
    // Return InvalidInput, CryptoFailure, etc.
}
```

**No code change needed.**

---

#### Snapshot MAC (N5) — lib.rs + Elixir

```rust
// backend/infra/mls_nif/src/lib.rs
fn nif_snapshot_mac_sign(plaintext: &[u8], key: &[u8]) -> Result<String, MlsError> {
    // HMAC-SHA256
}

fn nif_snapshot_mac_verify(plaintext: &[u8], mac: &str, key: &[u8]) -> Result<bool, MlsError> {
    // Verify HMAC
}
```

```elixir
# backend/lib/famichat/crypto/mls/snapshot_mac.ex
defmodule Famichat.Crypto.MLS.SnapshotMac do
  def sign(plaintext) do
    key = System.fetch_env!("MLS_SNAPSHOT_HMAC_KEY")
    MLS.snapshot_mac_sign(%{plaintext: plaintext, key: key})
  end

  def verify(plaintext, mac) do
    key = System.fetch_env!("MLS_SNAPSHOT_HMAC_KEY")
    MLS.snapshot_mac_verify(%{plaintext: plaintext, mac: mac, key: key})
  end
end
```

**Why keep**: Snapshot MAC is a **server-side compliance & audit feature**, not client-side encryption. It protects against tampering with archived MLS group state. In Path C, the server no longer stores active group state (client holds it), but you might store snapshots of group membership for audit logging.

**Usage in Path C**:
- Server receives client-submitted group snapshot ("this is the current group state").
- Server computes HMAC of snapshot.
- Server logs: `{conversation_id, group_snapshot_hash, timestamp}` for audit trail.
- On compliance request ("show me all decryptions in Q1"), server can verify the integrity of its audit trail.

**No code change needed.** Still use N5 (N1–N7 unchanged).

---

#### Serialization & Validation Utilities

```rust
// lib.rs: lines ~200–400
fn hex_encode(bytes: &[u8]) -> String { ... }
fn hex_decode(hex: &str) -> Result<Vec<u8>, MlsError> {
    // N2: MAX_HEX_DECODE_BYTES guard
}

fn validate_group_id(group_id: &str) -> Result<(), MlsError> {
    // N3: empty, len > 256, NUL byte checks
}

fn validate_ciphersuite(cs: &str) -> Result<Ciphersuite, MlsError> {
    // Check against allowed ciphersuites
}

fn validate_key_package(kp: &KeyPackage) -> Result<(), MlsError> {
    // Structural validation
}
```

**Why keep**: These are low-level, hardened utility functions. Client-side MLS validation can reuse the same validation rules (N2, N3). Server-side can also validate client payloads.

**Usage in Path C**:
- Client generates key package; client-side uses validate_key_package().
- Server receives key package; server-side could run the same validation as a safety check (defense in depth).
- Both sides validate group_id, ciphersuite.

**Action**: Extract into a separate `validation.rs` module. Reduce coupling to DashMap and GROUP_SESSIONS.

---

### Tier 2: Delete (Group State Ops)

These are tightly coupled to server-side MLS group management. In Path C, the client holds the group state; server is a relay.

#### DELETE: Group Session Management

```rust
// lib.rs: lines ~60–95
struct GroupSession {
    sender: MemberSession,
    recipient: MemberSession,
    decrypted_by_message_id: HashMap<String, CachedMessage>,
    decrypted_message_order: VecDeque<String>,
}

struct MemberSession {
    provider: OpenMlsRustCrypto,
    signer: SignatureKeyPair,
    group: MlsGroup,
}

static GROUP_SESSIONS: std::sync::LazyLock<DashMap<String, GroupSession>> = ...;
```

**Why delete**: In Path C, the client holds the MlsGroup and manages it. The server doesn't have an MlsGroup at all. These structs are server-specific.

**Implication**: Lines of code deleted: ~150.

---

#### DELETE: NIF Functions for Group Management

```rust
// DELETE all of these:
fn nif_create_group(env: Env, args: &[Term]) -> Result<Term, Error> { ... }
fn nif_mls_add(env: Env, args: &[Term]) -> Result<Term, Error> { ... }
fn nif_mls_remove(env: Env, args: &[Term]) -> Result<Term, Error> { ... }
fn nif_mls_update(env: Env, args: &[Term]) -> Result<Term, Error> { ... }
fn nif_mls_commit(env: Env, args: &[Term]) -> Result<Term, Error> { ... }
fn nif_merge_staged_commit(env: Env, args: &[Term]) -> Result<Term, Error> { ... }

// DELETE: OpenMLS state mutation helpers
fn extract_snapshot_raw_data(...) { ... }
fn serialize_snapshot_raw_data(...) { ... }
fn apply_snapshot_to_session(...) { ... }
```

**Why delete**: In Path C, the client calls openmls-wasm directly. The server never calls these functions.

**Implication**: Lines of code deleted: ~800.

**Register removal**: Remove NIF function exports:
```rust
// DELETE from rustler_export_nifs! macro:
rustler_export_nifs! {
    m,
    [
        // KEEP:
        ("nif_version", 0, nif_version),
        ("nif_health", 0, nif_health),
        ("snapshot_mac_sign", 1, snapshot_mac_sign),
        ("snapshot_mac_verify", 1, snapshot_mac_verify),

        // DELETE:
        // ("create_group", 1, nif_create_group),
        // ("mls_add", 1, nif_mls_add),
        // ... etc
    ]
}
```

---

#### DELETE: Elixir Lifecycle Orchestration

```elixir
# backend/lib/famichat/chat/conversation_security_lifecycle.ex
# ENTIRE MODULE: ~500 lines

defmodule Famichat.Chat.ConversationSecurityLifecycle do
  def stage_pending_commit(conversation_id, operation, attrs) do
    with {:ok, state} <- load_state(conversation_id, :stage_pending_commit),
         :ok <- ensure_no_pending_commit(state, operation),
         request <- build_request(state, attrs),
         {:ok, payload} <- apply(MLS, operation, [request]),  # ← NIF CALL
         # ... more orchestration
    end
  end

  def merge_pending_commit(conversation_id, attrs) do
    # ... orchestrates stage → merge → commit lifecycle
  end
end
```

**Why delete**: ConversationSecurityLifecycle orchestrates **server-side MLS operations** (stage, merge, commit). In Path C, the client does all this. The server doesn't have pending commits.

**Implication**: Lines of code deleted: ~500.

**Exception**: If you want to add **optional server-side audit logging** ("client submitted a commit; here's the hash"), you could stub out a "no-op audit logger" version of these functions. But the active orchestration is gone.

---

#### DELETE: Persistent Conversation Security State Store

```elixir
# backend/lib/famichat/chat/conversation_security_state_store.ex
# Most of this: ~500 lines

defmodule Famichat.Chat.ConversationSecurityStateStore do
  @doc """
  Load durable MLS group state from database.
  """
  def load(conversation_id) do
    Repo.get!(ConversationSecurityState, conversation_id)
    |> extract_snapshot()
    |> deserialize_group_state()  # ← Calls NIF to deserialize
  end

  @doc """
  Save durable MLS group state to database.
  """
  def persist(conversation_id, group_state) do
    snapshot = serialize_group_state(group_state)  # ← Calls NIF
    Repo.insert_or_update!(%ConversationSecurityState{
      conversation_id: conversation_id,
      snapshot_encrypted: Vault.encrypt(snapshot),
      # ...
    })
  end
end

# Schema: conversation_security_states table
defmodule Famichat.Chat.ConversationSecurityState do
  schema "conversation_security_states" do
    field(:conversation_id, :binary_id, primary_key: true)
    field(:snapshot_encrypted, :binary)
    field(:snapshot_mac, :string)
    field(:epoch, :integer)
    field(:pending_commit, :map)
    field(:lock_version, :integer)
  end
end
```

**Why delete**: The `conversation_security_states` table stores server-side MLS group state. In Path C, there is no server-side group state. The client stores it locally (in IndexedDB or localStorage).

**Implication**:
- Delete Elixir module: ~500 lines.
- Delete migration & schema: ~100 lines.
- Delete references in MessageService, ConversationSecurityLifecycle, etc.

**BUT: Keep the Snapshot MAC logic** (N5):
- The Snapshot MAC validates integrity of group state.
- Even if the server doesn't store group state, you can still validate client-submitted snapshots for audit logging.
- Move the MAC logic into a standalone `SnapshotMac` module (already exists; no change).

---

### Tier 3: Refactor (Change, but Keep)

These modules need refactoring to stop calling the NIF group ops, but the overall structure stays.

#### Refactor: Crypto.MLS Adapter

```elixir
# backend/lib/famichat/crypto/mls.ex
defmodule Famichat.Crypto.MLS do
  # KEEP: These are still useful
  def nif_health, do: call_0(:nif_health)
  def nif_version, do: call_0(:nif_version)

  # DELETE: These are no longer used
  # def create_group(params), do: call_1(:create_group, params)
  # def mls_add(params), do: call_1(:mls_add, params)
  # def mls_remove(params), do: call_1(:mls_remove, params)
  # def mls_commit(params), do: call_1(:mls_commit, params)
  # def merge_staged_commit(params), do: call_1(:merge_staged_commit, params)

  # KEEP: Server-side validation (optional, for defense-in-depth)
  def validate_application_message(ciphertext) do
    # Server receives encrypted message from client; validate format
    call_1(:validate_application_message, %{ciphertext: ciphertext})
  end
end
```

**Action**: Delete 6 function definitions. Keep the call_adapter pattern; it's solid.

**Lines deleted**: ~50.

---

#### Refactor: MessageService

```elixir
# backend/lib/famichat/chat/message_service.ex
defmodule Famichat.Chat.MessageService do
  @doc """
  Send a message (encrypted client-side in SPA; server relays ciphertext).
  """
  def send_message(user, conversation, %{"body" => ciphertext} = params) do
    with :ok <- validate_ciphertext_format(ciphertext),  # ← NEW: validate client-side encrypted format
         {:ok, validated_params} <- validate_encryption_metadata(params),  # ← EXISTING (S2)
         message <- build_message(user, conversation, validated_params),
         {:ok, persisted} <- Repo.insert(message),
         # N5: Sign snapshot if provided (optional, for audit)
         :ok <- maybe_sign_snapshot(conversation, params["snapshot"]),
         # S1: Ensure device is active before broadcast
         {:ok, socket_user} <- ensure_socket_device_active(user),
         :ok <- broadcast_message(socket_user, conversation, persisted)
    do
      {:ok, persisted}
    rescue
      # S3: Narrow rescues
      error in [RuntimeError, ArgumentError] ->
        Logger.error("Message send failed: #{inspect(error)}")
        {:error, :message_send_failed}
    end
  end

  defp validate_ciphertext_format(ciphertext) do
    # NEW: Validate that client-side encryption is present
    if is_binary(ciphertext) and byte_size(ciphertext) > 0 do
      :ok
    else
      {:error, :missing_ciphertext}
    end
  end
end
```

**Changes**:
- Delete: `MLS.create_application_message()` call (client now encrypts).
- Keep: Encryption metadata validation (S2 whitelist).
- Keep: Device active check (S1).
- Add: `validate_ciphertext_format/1` to ensure client encrypted.
- Add: Optional snapshot signing (N5 audit trail).

**Lines changed**: ~100 (net: ~50 removed, ~50 added).

---

#### Refactor: Deprecate ConversationSecurityLifecycle

```elixir
# OPTION 1: Mark as deprecated
defmodule Famichat.Chat.ConversationSecurityLifecycle do
  @deprecated "Server no longer manages MLS group state (Path C). Client handles encryption."
  def stage_pending_commit(conversation_id, operation, attrs) do
    {:error, :deprecated, %{reason: "Use client-side MLS in SPA"}}
  end
end

# OPTION 2: Delete entirely
# Remove backend/lib/famichat/chat/conversation_security_lifecycle.ex
# Remove backend/test/famichat/chat/conversation_security_lifecycle_test.exs
```

**Recommendation**: Delete entirely. The module is no longer used; keeping it around is confusing.

**Lines deleted**: ~500 (module) + ~400 (tests).

---

### Tier 4: Expand (New Usage)

In Path C, you'll need **new server-side functions** for client-side validation and audit logging.

#### NEW: Server-Side Payload Validation

```rust
// backend/infra/mls_nif/src/lib.rs
// NEW functions for client-side E2EE

fn nif_validate_group_add_proposal(proposal_bytes: &[u8]) -> Result<Payload, MlsError> {
    // Client submits: "Add device X to group Y"
    // Server validates the proposal format (without decrypting)
    // Returns: {status: "valid"} or {error: "..."}
}

fn nif_validate_commit(commit_bytes: &[u8]) -> Result<Payload, MlsError> {
    // Client submits a commit message
    // Server validates the format and structure
    // Server does NOT deserialize group state (it doesn't have it)
    // Server checks: valid ciphersuite, valid epoch range, etc.
}

fn nif_validate_application_message(msg_bytes: &[u8]) -> Result<Payload, MlsError> {
    // Client submits encrypted message
    // Server validates format: is it a valid MLS ApplicationMessage?
    // Server checks: is the ciphertext valid hex/base64?
}
```

**Why add**: Defense in depth. Server validates client payloads before storing, catching malformed messages early.

**Lines added**: ~200.

---

#### NEW: Server-Side Audit Logging (Optional)

```elixir
# backend/lib/famichat/chat/message_service.ex

defp maybe_sign_snapshot(conversation, snapshot_map) when is_map(snapshot_map) do
  with {:ok, plaintext} <- serialize_snapshot_for_audit(snapshot_map),
       {:ok, mac} <- SnapshotMac.sign(plaintext) do
    # Log for audit trail: "Client submitted group state with this MAC at this time"
    Repo.insert!(%ConversationSecurityAuditLog{
      conversation_id: conversation.id,
      event_type: "client_snapshot_submitted",
      snapshot_mac: mac,
      timestamp: DateTime.utc_now()
    })

    :ok
  end
end

defp maybe_sign_snapshot(_conversation, _), do: :ok
```

**Why add**: Compliance & forensics. If an admin is subpoenaed and claims they never accessed group state, the audit log can prove which snapshots were submitted when. Even though the server can't decrypt, having the snapshot MAC proves the client state existed.

**Lines added**: ~100.

---

## Migration Checklist

### Phase 1: Prepare (Week 1–2)

- [ ] Create a new branch `refactor/path-c-nif-salvage`.
- [ ] Spike openmls-wasm: does it compile? Can you build WASM bindings?
- [ ] If openmls-wasm doesn't exist, fork OpenMLS and add WASM support (~1 week).

### Phase 2: Delete Dead Code (Week 2–3)

- [ ] Delete `nif_create_group`, `nif_mls_add`, `nif_mls_remove`, `nif_mls_commit`, `nif_mls_update`, `nif_merge_staged_commit` from lib.rs.
- [ ] Delete `struct GroupSession`, `struct MemberSession`, `static GROUP_SESSIONS` from lib.rs.
- [ ] Delete `conversation_security_lifecycle.ex` and its tests.
- [ ] Delete or deprecate `ConversationSecurityStateStore` (or reduce to snapshot MAC logic only).
- [ ] Update `Crypto.MLS` adapter to remove deleted functions.
- [ ] Verify tests still pass (some will be deleted; Rust tests should still be 17/17).

### Phase 3: Refactor MessageService (Week 3–4)

- [ ] Remove `MLS.create_application_message()` call.
- [ ] Add `validate_ciphertext_format/1`.
- [ ] Add optional snapshot signing (N5 audit trail).
- [ ] Keep S1 (device active check), S2 (metadata whitelist), S3 (narrow rescues).
- [ ] Test with SPA sending ciphertext.

### Phase 4: Add Server-Side Validation (Week 4–5, optional)

- [ ] Implement `nif_validate_group_add_proposal`, `nif_validate_commit`, `nif_validate_application_message` in Rust.
- [ ] Add optional server-side payload validation before persisting.

### Phase 5: Audit Logging (Week 5–6, optional)

- [ ] Implement `ConversationSecurityAuditLog` schema & migrations.
- [ ] Hook snapshot MAC signing into message pipeline.
- [ ] Add compliance report endpoints.

### Phase 6: Testing (Week 6–8)

- [ ] Update existing tests: remove ConversationSecurityLifecycle tests; keep all Track A security gate tests.
- [ ] Add new E2E tests: SPA sends ciphertext → server validates → server stores → SPA decrypts locally.
- [ ] Load testing: can server handle 500+ messages/conversation? WASM decrypt performance?
- [ ] Multi-device scenario tests: device A sends, device B receives and decrypts.

---

## Code Reuse Metrics

| Category | Lines | Status |
|----------|-------|--------|
| **Keep (no change)** | ~1,700 | ErrorCode, snapshot MAC, validation utils, test harness |
| **Delete (group ops)** | ~1,000 | GROUP_SESSIONS, stage/merge/commit functions |
| **Refactor (small changes)** | ~300 | MessageService, Crypto.MLS adapter |
| **Deprecate (stub or remove)** | ~500 | ConversationSecurityLifecycle, ConversationSecurityStateStore |
| **Add (new server-side validation)** | ~300 | nif_validate_*, audit logging (optional) |
| **Total NIF after migration** | ~1,700 | Smaller, faster, focused on validation + audit |

**Salvage rate: 70%** (1,700 KEEP / 2,400 KEEP+REFACTOR out of 2,723 original).

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Deleting ConversationSecurityLifecycle breaks something | Run full test suite before and after deletion; keep git history for bisect. |
| Removing GROUP_SESSIONS causes panic on server startup | Verify no code path tries to lazily initialize GROUP_SESSIONS. Use grep to find all references. |
| Snapshot MAC verification fails in audit logging | Test snapshot MAC sign/verify with synthetic data before deploying. |
| Server-side validation logic doesn't match client-side | Client and server use different crypto libraries (openmls-wasm vs. OpenMLS). Validate format (structure) only; don't decrypt. |

---

## Future Extensions (Q2+)

Once Path C is live:

1. **Zero-knowledge proofs** (research, future): Client submits ZK proof that they can decrypt a message. Server checks proof without decryption.
2. **Key rotation policy**: Client rotates per-device keys monthly. Server validates rotation via audit log.
3. **Deterministic group state validation**: Client submits group state hash. Server validates against expected state (without decrypting).

---

## Summary

**Path C NIF salvage is straightforward**:
- **Keep**: Error codes, snapshot MAC, validation, tests, hardening patterns.
- **Delete**: Group state ops (stage/merge/commit), GROUP_SESSIONS, ConversationSecurityLifecycle.
- **Refactor**: MessageService, Crypto.MLS adapter (small changes).
- **Add**: Server-side validation, audit logging (optional).

**Result**: Smaller (1,700 lines), faster (no group state serialization), more focused NIF (validation only). Plus 70% code salvage vs. 0% if you'd thrown away the entire thing.

---

**Ready to start Phase 1 (openmls-wasm spike)?**
