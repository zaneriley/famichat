# Famichat - Encryption & Security Architecture

**Last Updated**: 2025-10-05

---

## Security Model

Famichat uses a **hybrid encryption approach**:

1. **Server-Side E2EE**: Signal Protocol for message content (backend Rust NIF + libsignal-client)
2. **Field-Level Encryption**: Cloak.Ecto for sensitive user data (email, tokens, keys)
3. **Infrastructure Encryption**: Database encryption at rest

**Trust Model**: Self-hosted = you control the backend. Server has decryption keys but you own the server (similar to Signal's sealed sender trust model).

---

## Current Status (End of Sprint 7)

### ✅ Implemented - Encryption Metadata Infrastructure
- Encryption metadata storage in JSONB `messages.metadata` field
- `serialize_message/1` - Stores encryption metadata from params
- `deserialize_message/1` - Retrieves encryption metadata
- `requires_encryption?/1` - Policy enforcement (all conversation types require encryption)
- Telemetry tracking for encryption status (enabled/disabled/missing)
- Telemetry filtering (prevents sensitive data leaks)
- Token-based channel authentication
- **Tests**: [decryption_test.exs](../backend/test/famichat/messages/decryption_test.exs) validates metadata flow

### ❌ Not Implemented - Actual Cryptography
- ⚠️ **CRITICAL**: **Messages currently stored in plaintext**
- No libsignal-client library (Rust crate)
- No Rustler NIF integration
- No X3DH key exchange implementation
- No Double Ratchet encryption/decryption
- No key management system (identity keys, prekeys, sessions)
- No Cloak.Ecto vault for key encryption at rest
- `decrypt_message/1` is a **placeholder stub** (no actual decryption logic)

### 🔄 Planned Implementation

**Sprint 9 (3 weeks)**: Signal Protocol via Server-Side Rust NIF
- Week 1-2: Rustler + libsignal-client setup, basic encryption tests
- Week 2-3: X3DH key exchange, database schema for keys, Cloak.Ecto vault
- Week 3: Wire up message encryption/decryption, integration tests

**Sprint 10 (2 weeks)**: Layer 0 Dogfooding with Encryption Enabled

---

## Protocol Choice: Signal Protocol

**Decision**: Use Signal Protocol for all end-to-end encrypted messaging.

**Why Signal?**
- **Right-sized for families**: Optimized for 2-6 person households (primary use case)
- **Battle-tested**: WhatsApp (2B+ users), Signal, Facebook Messenger
- **Performance**: 30-90ms for family groups (well within 200ms budget)
- **Deniability**: Messages use MACs (not signatures), better for family trust dynamics
- **Mature ecosystem**: libsignal-client actively maintained by Signal Foundation

**Alternatives Evaluated** (see [ADR 006](decisions/006-signal-protocol-for-e2ee.md)):
- ❌ **MLS**: Overkill for small groups (2-6 people), tree overhead unnecessary
- ❌ **Megolm**: No Post-Compromise Security, Matrix-specific (vendor lock-in)
- ❌ **No E2EE**: Impossible to retrofit later, user expectation for secure messaging

---

## Signal Protocol Architecture

### Components

**1. X3DH (Extended Triple Diffie-Hellman)**
- Asynchronous key agreement (works when recipient offline)
- Initial session establishment between users
- Uses identity keys + ephemeral prekeys
- Performance: ~15ms for 1:1 key exchange

**2. Double Ratchet**
- Forward secrecy (past messages safe if keys compromised)
- Post-compromise security (future messages safe after key rotation)
- Automatic per-message key derivation
- Performance: ~15ms per message encryption/decryption

**3. Pairwise Encryption for Groups**
- Each group message encrypted separately for each recipient
- N-person group = N separate encryptions
- Performance scales linearly: O(n)
  - 2 people: 30ms
  - 6 people: 90ms
  - 30 people: 450ms (Layer 5 upper bound)

### Performance Characteristics

**Family Scale (Layers 1-4):**
```
2 people (Layer 1 Dyad):           15ms × 2 = 30ms   ✅
4 people (Layer 2 Triad):          15ms × 4 = 60ms   ✅
6 people (Layer 3 Extended):       15ms × 6 = 90ms   ✅
```

**Inter-Family Scale (Layer 5, if needed):**
```
20 people (4 families):            15ms × 20 = 300ms  ⚠️ Borderline
30 people (5 families):            15ms × 30 = 450ms  ⚠️ Upper limit
```

**Conclusion**: Signal performs excellently for family messaging (primary use case). Layer 5 may need evaluation if groups regularly exceed 30 people.

---

## Implementation Plan (Sprint 9 - 3 Weeks)

### Phase 1: Rust NIF + libsignal-client (Week 1-2)

**Approach**: Server-side encryption via Rust NIF (not client-side JavaScript)

**Goal**: Integrate libsignal-client into Elixir via Rustler NIF

**Tasks**:
1. Add Rust toolchain to Docker (multi-stage build)
2. Create Rustler NIF wrapper
3. Add libsignal-client dependency
4. Implement error handling + telemetry
5. Test basic encrypt/decrypt functions

**Deliverable**: Can call Signal functions from Elixir

```elixir
# lib/famichat/crypto/signal.ex
defmodule Famichat.Crypto.Signal do
  use Rustler, otp_app: :famichat, crate: "signal_nif"

  def generate_identity_key(_user_id), do: :erlang.nif_error(:nif_not_loaded)
  def generate_prekeys(_user_id, _count), do: :erlang.nif_error(:nif_not_loaded)
  def create_session(_sender_id, _recipient_prekey), do: :erlang.nif_error(:nif_not_loaded)
  def encrypt(_session_id, _plaintext), do: :erlang.nif_error(:nif_not_loaded)
  def decrypt(_session_id, _ciphertext), do: :erlang.nif_error(:nif_not_loaded)
end
```

---

### Phase 2: Key Management (Week 2-3)

**Goal**: Users have Signal identity keys and can establish sessions

**Database Schema**:
```sql
-- User identity keys (long-term)
CREATE TABLE signal_identity_keys (
  user_id UUID PRIMARY KEY,
  public_key BYTEA NOT NULL,
  private_key_encrypted BYTEA NOT NULL,  -- Encrypted with user password
  created_at TIMESTAMP NOT NULL
);

-- Prekeys (one-time use for session establishment)
CREATE TABLE signal_prekeys (
  id SERIAL PRIMARY KEY,
  user_id UUID NOT NULL,
  prekey_id INTEGER NOT NULL,
  public_key BYTEA NOT NULL,
  private_key_encrypted BYTEA NOT NULL,
  used BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL,
  UNIQUE(user_id, prekey_id)
);

-- Active sessions (pairwise between users)
CREATE TABLE signal_sessions (
  id UUID PRIMARY KEY,
  local_user_id UUID NOT NULL,
  remote_user_id UUID NOT NULL,
  session_state BYTEA NOT NULL,  -- Serialized Double Ratchet state
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(local_user_id, remote_user_id)
);
```

**Tasks**:
1. Create Cloak.Ecto vault for key encryption at rest
2. Generate identity keys on user signup (encrypted with Cloak)
3. Generate 100 prekeys per user (replenish when <20 remain)
4. Implement X3DH session establishment (server-side NIF call)
5. Store session state (Double Ratchet state, encrypted at rest)
6. Handle session updates (ratchet forward on each message)

**Deliverable**: Users can establish encrypted sessions (keys stored encrypted in database)

---

### Phase 3: Message Encryption Integration (Week 3)

**Goal**: Messages encrypted end-to-end using Signal Protocol

**Updated Message Schema**:
```elixir
schema "messages" do
  field :content, :binary  # Encrypted ciphertext
  field :encrypted, :boolean, default: true

  # Encryption metadata (separate table per ADR 005)
  has_one :encryption, MessageEncryption

  belongs_to :sender, User
  belongs_to :conversation, Conversation

  timestamps()
end
```

**Encryption Flow**:
```elixir
# 1:1 Conversation
def create_message(sender_id, recipient_id, plaintext) do
  with {:ok, session} <- get_or_create_session(sender_id, recipient_id),
       {:ok, ciphertext} <- Crypto.Signal.encrypt(session.id, plaintext) do
    %Message{
      sender_id: sender_id,
      content: ciphertext,
      encrypted: true
    }
    |> Repo.insert()
  end
end

# Group Conversation (family of 6 people)
def create_group_message(sender_id, recipient_ids, plaintext) do
  # Pairwise encryption for each recipient
  Enum.map(recipient_ids, fn recipient_id ->
    create_message(sender_id, recipient_id, plaintext)
  end)
end
```

**Tasks**:
1. Integrate Signal encryption into MessageService
2. Handle group messages (pairwise encryption)
3. Update Double Ratchet state after each message
4. Handle decryption errors gracefully

**Deliverable**: End-to-end encrypted messaging works

---

### Phase 4: UI Integration (Week 5)

**Goal**: LiveView displays encrypted messages transparently

**Key Derivation**:
```elixir
# User logs in with password
# Derive master key from password (Argon2)
# Decrypt private Signal keys from database
# Store decrypted keys in encrypted session cookie

def login(email, password) do
  with {:ok, user} <- Accounts.get_by_email(email),
       {:ok, master_key} <- derive_master_key(password, user.salt),
       {:ok, identity_key} <- decrypt_identity_key(user, master_key) do

    session_data = %{
      user_id: user.id,
      identity_key: identity_key  # Encrypted in session cookie
    }

    {:ok, session_data}
  end
end
```

**LiveView Integration**:
```elixir
def handle_event("send_message", %{"content" => plaintext}, socket) do
  sender_id = socket.assigns.current_user.id
  recipient_id = socket.assigns.conversation.other_user_id

  case Chat.create_encrypted_message(sender_id, recipient_id, plaintext) do
    {:ok, encrypted_message} ->
      # Decrypt for display (sender can decrypt own message)
      {:ok, decrypted} = decrypt_message(sender_id, encrypted_message)
      {:noreply, assign(socket, messages: [decrypted | socket.assigns.messages])}
  end
end

def handle_info({:new_message, encrypted_message}, socket) do
  # Real-time message received
  case decrypt_message(socket.assigns.current_user.id, encrypted_message) do
    {:ok, decrypted} ->
      {:noreply, update(socket, :messages, &[decrypted | &1])}
    {:error, :cannot_decrypt} ->
      # Session missing or corrupted
      {:noreply, put_flash(socket, :error, "Could not decrypt message")}
  end
end
```

**Tasks**:
1. Key derivation from user password
2. Encrypted session storage (keys in cookie)
3. Transparent encryption/decryption in LiveView
4. Error handling (session missing, decryption failures)
5. Real-time updates with encrypted messages

**Deliverable**: Full encrypted messaging via LiveView

---

## Security Properties

### Forward Secrecy
**Guarantee**: Past messages remain secure even if current keys are compromised.

**How**: Double Ratchet generates new message keys for every message exchange. Old keys deleted after use.

**Example**: If attacker steals device on Monday, they cannot decrypt messages from Sunday (keys already deleted).

---

### Post-Compromise Security
**Guarantee**: Future messages become secure again after key rotation.

**How**: Double Ratchet automatically rotates keys on every message. Compromised session heals after next round-trip.

**Example**: If attacker steals device on Monday, Tuesday's messages are still secure (new keys generated).

---

### Deniability
**Guarantee**: Messages cannot be cryptographically proven to third parties.

**How**: Signal uses MACs (Message Authentication Codes), not digital signatures. Anyone with the shared key could have forged the message.

**Why This Matters for Families**: Teen can say "I didn't send that" (plausible deniability). Parent can't prove "you said X" with cryptographic evidence. Better for family trust dynamics.

**Contrast with MLS**: MLS uses signatures (non-repudiation). Messages can be proven in conflicts. May harm family trust.

---

## Encryption Metadata Storage

Per [ADR 005](decisions/005-encryption-metadata-schema.md), encryption metadata stored in separate table for indexing performance.

```sql
CREATE TABLE message_encryption (
  message_id UUID PRIMARY KEY,
  encrypted BOOLEAN NOT NULL,
  protocol VARCHAR NOT NULL DEFAULT 'signal',
  version VARCHAR NOT NULL,
  session_id UUID,  -- References signal_sessions
  sender_device_id VARCHAR,
  metadata JSONB DEFAULT '{}'  -- Protocol-specific extras
);

-- Indexes for common queries
CREATE INDEX idx_encryption_session ON message_encryption(session_id);
CREATE INDEX idx_encryption_protocol ON message_encryption(protocol);
```

---

## Conversation-Type Encryption Policies

**Defined in** `MessageService.requires_encryption?/1`:

- `:direct` → Encryption required
- `:group` → Encryption required (pairwise for each member)
- `:family` → Encryption required (pairwise for each member)
- `:self` → Encryption optional (can use symmetric encryption instead)

---

## Error Handling

### NIF Safety
**Problem**: Rust panics crash the entire BEAM VM.

**Solution**: Panic handlers and error boundaries.

```rust
#[rustler::nif(schedule = "DirtyCpu")]
fn encrypt(session_id: String, plaintext: String) -> Result<Vec<u8>, String> {
    std::panic::catch_unwind(|| {
        // Signal encryption logic
        signal_encrypt_internal(session_id, plaintext)
    })
    .map_err(|_| "Signal encryption panic".to_string())?
}
```

### Decryption Failures
**Causes**:
- Session missing (new device, no session established)
- Session corrupted (database issue)
- Message tampered with (detected by AEAD)
- Session out of sync (missed messages)

**Handling**:
```elixir
case decrypt_message(user_id, encrypted_message) do
  {:ok, plaintext} ->
    # Display message
    plaintext

  {:error, :session_not_found} ->
    # Establish new session
    establish_session(user_id, message.sender_id)
    retry_decrypt(user_id, encrypted_message)

  {:error, :out_of_sync} ->
    # Request missing messages to catch up ratchet
    request_missing_messages(conversation_id)

  {:error, :tampered} ->
    # AEAD verification failed, message altered
    log_security_event(:message_tampered, message.id)
    "[Message could not be decrypted]"
end
```

---

## Performance Monitoring

### Telemetry Events

```elixir
:telemetry.span(
  [:famichat, :crypto, :encrypt],
  %{user_id: user_id, recipient_id: recipient_id},
  fn ->
    result = Crypto.Signal.encrypt(session_id, plaintext)
    {result, %{message_size: byte_size(plaintext)}}
  end
)
```

**Metrics Tracked**:
- Encryption latency (P50, P95, P99)
- Decryption latency
- Session establishment time
- NIF call failures
- Decryption error rate

**Alerts**:
- Encryption latency >100ms (performance regression)
- Decryption error rate >1% (session sync issues)
- NIF crashes (panic in Rust code)

---

## Security Testing Strategy

### Required Tests

1. **Encryption/decryption round-trip**
   ```elixir
   test "message encrypts and decrypts correctly" do
     plaintext = "Hello, World!"
     {:ok, ciphertext} = encrypt(sender, recipient, plaintext)
     {:ok, decrypted} = decrypt(recipient, ciphertext)
     assert decrypted == plaintext
   end
   ```

2. **Tampered ciphertext detection**
   ```elixir
   test "tampered message fails to decrypt" do
     {:ok, ciphertext} = encrypt(sender, recipient, "Hello")
     tampered = corrupt_byte(ciphertext, 10)
     assert {:error, :tampered} = decrypt(recipient, tampered)
   end
   ```

3. **Forward secrecy**
   ```elixir
   test "old messages cannot be decrypted after key rotation" do
     {:ok, msg1} = encrypt_and_store(sender, recipient, "Message 1")
     {:ok, msg2} = encrypt_and_store(sender, recipient, "Message 2")

     # Compromise session after msg2
     compromised_session = steal_session_keys()

     # msg2 decryptable with compromised keys
     {:ok, _} = decrypt_with_compromised_keys(msg2, compromised_session)

     # msg1 NOT decryptable (keys already rotated away)
     {:error, :key_not_found} = decrypt_with_compromised_keys(msg1, compromised_session)
   end
   ```

4. **Performance under load**
   ```elixir
   test "encryption performance acceptable for 6-person family" do
     recipients = create_users(6)
     plaintext = "Family group message"

     {time_us, _} = :timer.tc(fn ->
       Enum.each(recipients, fn recipient ->
         encrypt(sender, recipient, plaintext)
       end)
     end)

     time_ms = time_us / 1000
     assert time_ms < 100  # 6 people should encrypt in <100ms
   end
   ```

---

## Open Questions

### Q1: Multi-Device Support
**Question**: How do users access messages from multiple devices (phone + tablet + web)?

**Options**:
- **Session Protocol** (Signal's multi-device extension)
  - Requires additional complexity (device linking, message fanout)
  - Need to encrypt for all user devices, not just recipient's devices

- **Manual device linking**
  - Primary device approves new devices
  - QR code scan (similar to WhatsApp Web)

- **Defer to post-MVP**
  - Single device first, add multi-device if users request

**Decision**: Defer until Layer 2-3 validation. Solve when dogfooding reveals need.

---

### Q2: Key Backup & Recovery
**Question**: What if user loses device? How to recover message history?

**Options**:
- **Encrypted cloud backup** (user-controlled passphrase)
  - User generates backup passphrase
  - Keys encrypted with passphrase, stored on server
  - Risk: Weak passphrase = compromised keys

- **Social recovery** (Shamir secret sharing)
  - Key split among trusted family members
  - Requires 3-of-5 family members to recover
  - Complex UX, social engineering risk

- **No backup** (lost device = lost history)
  - Simplest, most secure
  - Poor UX, users frustrated by data loss

**Decision**: Defer until Layer 1 validation. Test which approach users prefer when dogfooding.

---

### Q3: Layer 5 Performance
**Question**: Will Signal scale to 30-person inter-family channels?

**Performance Analysis**:
- 30 people = 450ms encryption time
- Exceeds 200ms budget but < 500ms "slow" threshold
- Infrequent use (inter-family coordination, not daily chat)

**Options if performance becomes issue**:
- **Accept 450ms**: Still usable for infrequent coordination
- **Hybrid approach**: Signal for families, MLS for large channels only
- **Full MLS migration**: Months of work, only if Layer 5 becomes primary use case

**Decision**: Test in Layer 5, pivot if needed. Don't optimize for problem we don't have yet.

---

## Migration Path (If Needed)

**If Layer 5 grows beyond 30 people and performance unacceptable:**

### Option A: Accept Higher Latency
- 450ms still < 500ms "slow" threshold
- Inter-family coordination is infrequent (weekly carpools, not daily chat)
- Users may tolerate slightly higher latency for these use cases

### Option B: Hybrid Protocol
- **Signal for families** (Layers 1-4, 2-6 people)
- **MLS for inter-family** (Layer 5, 20-30 people)
- Complex but possible migration
- Requires maintaining two crypto implementations

### Option C: Full MLS Migration
- Replace Signal with MLS for all conversations
- Requires re-implementing key management
- Months of work
- Only if Layer 5 becomes primary use case (unlikely given product vision)

**Recommendation**: Start with Signal, re-evaluate after Layer 5 testing. Don't prematurely optimize.

---

## Related Documentation

- **ADR 002**: [Hybrid Encryption Strategy](decisions/002-encryption-approach.md)
- **ADR 005**: [Encryption Metadata Schema](decisions/005-encryption-metadata-schema.md)
- **ADR 006**: [Signal Protocol for E2EE](decisions/006-signal-protocol-for-e2ee.md) - Full protocol evaluation
- **ARCHITECTURE.md**: [System Architecture](ARCHITECTURE.md)
- **PERFORMANCE.md**: [Performance Budgets](PERFORMANCE.md)

---

**Last Updated**: 2025-10-05
**Status**: Signal Protocol chosen, implementation starts Sprint 8
**Next Review**: After Layer 5 implementation (if inter-family channels grow >30 people)
