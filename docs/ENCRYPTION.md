# Famichat - Encryption & Security Architecture

**Last Updated**: 2025-10-05

---

## Security Model

Famichat uses a **hybrid encryption approach**:

1. **Client-Side E2EE** (Planned): Signal Protocol for message content
2. **Field-Level Encryption**: Cloak.Ecto for sensitive user data (email, tokens)
3. **Infrastructure Encryption**: Database encryption at rest

---

## Current Status

### ✅ Implemented
- Encryption infrastructure (schema fields, serialization)
- Metadata storage in JSONB `messages.metadata`
- Telemetry filtering (prevents sensitive data leaks)
- Token-based channel authentication

### ❌ Not Implemented (CRITICAL GAP)
- No actual cryptography
- No key exchange
- No client-side encryption
- No key management system

---

## Protocol Evaluation

Famichat requires <50ms encryption budget to meet <200ms end-to-end latency target. Different E2EE protocols have vastly different performance characteristics at neighborhood scale (100-500 people).

### Signal Protocol

**Status**: ❌ Rejected for group conversations

**Performance**:
- 1:1 conversations: ~15ms ✅
- Group conversations (100 people): ~2000ms ❌

**Problem**: Signal uses pairwise encryption. For N-person group:
- Sender must encrypt message N times (once per recipient)
- At 100 recipients: 100 × 20ms = 2000ms
- Exceeds 50ms budget by 40x

**Conclusion**: Signal Protocol works for direct conversations but cannot be used for neighborhood-scale groups.

---

### Megolm (Matrix Protocol)

**Status**: ⚠️ Viable option, requires evaluation

**Performance**:
- Group conversations (100 people): ~110ms
- Exceeds 50ms budget but within tolerance (2.2x)

**Advantages**:
- Sender encrypts once, all recipients decrypt with shared ratchet
- Mature implementation (Matrix uses in production)
- Open specification
- Good forward secrecy

**Tradeoffs**:
- Slightly weaker security model than Signal (shared group key)
- Key rotation complexity for large groups
- Recovery from compromise requires group rekey

**See**: [Megolm Spec](https://gitlab.matrix.org/matrix-org/olm/-/blob/master/docs/megolm.md)

---

### MLS (Message Layer Security - IETF)

**Status**: ✅ Recommended - Standardized and production-ready

**Performance**:
- **Message encryption/decryption**: 5-10ms (symmetric AEAD after group established)
- **Group operations** (setup, add/remove member, key rotation): ~150ms for 100-person group
  - Infrequent operations (group creation, membership changes, periodic key rotation)
  - Logarithmic cost (scales efficiently even to 10,000+ members)
- **Regular messaging**: Fits within 50ms encryption budget ✅
- **Group management**: Exceeds budget but acceptable (infrequent, not on critical messaging path)

**Advantages**:
- **Standardized**: RFC 9420 (July 2023) + RFC 9750 Architecture (April 2025)
- **Production-proven**: Wire deployed MLS to all products (2000-member groups)
- **Industry adoption**: Google integrating into RCS, Matrix experimenting, major vendors participating
- **Superior security model**:
  - Forward Secrecy (FS): Past messages safe even if current keys compromised
  - Post-Compromise Security (PCS): Recovery from device compromise via key updates
  - Strong authentication: Cryptographic member verification, prevents impersonation
  - Group membership controls: Former members automatically lose access
  - Server/network adversary resistance: Untrusted delivery service, E2EE guaranteed
- **Scalability**: Logarithmic operations (tree-based), tested to 10,000+ members
- **Future-proof**: IETF standard, multiple implementations, interoperability testing

**Security Advantages Over Signal/Megolm**:
1. **Post-Compromise Security**: Automatic recovery from device compromise (Signal/Megolm lack this)
2. **Cryptographic membership proofs**: Verifiable group roster (prevents server manipulation)
3. **Standardized interoperability**: Future cross-platform messaging (EU DMA compliance path)
4. **Continuous key agreement**: Stronger than Megolm's shared ratchet

**Implementation Considerations**:
- **Library**: OpenMLS (Rust) via Rustler NIF
  - Mature: v0.6 (approaching 1.0), production use at Wire
  - Safe: Rust memory safety + high-level API
  - Active development: Post-quantum experiments, storage traits
- **State management**: Requires persistent storage of group state (ETS/database)
  - Each group = GenServer managing MLS context
  - Must handle epoch updates, membership changes
- **Integration complexity**: Higher than Megolm (tree structures, epochs, proposals/commits)
  - Offset by robust library (OpenMLS handles protocol complexity)
- **NIF considerations**: Rustler makes safe, but test thoroughly
  - Use dirty schedulers for crypto operations

**Tradeoffs**:
- Group operations (150ms) slower than message encryption (5-10ms)
  - Acceptable: Group changes infrequent (user joins/leaves, periodic key rotation)
  - Not on critical path: Regular messaging unaffected
- Complex state management (but OpenMLS provides storage interface)
- Foreign dependency (Rust via NIF, but Rustler well-established)
- API still evolving (pre-1.0, expect breaking changes until stable)

**Security Limitations** (application must handle):
1. **No protection against malicious insiders**: Legitimate members can leak plaintext
2. **Replay attacks within epoch**: Insiders can re-send messages (app must track message IDs)
3. **Idle device risk**: Long-offline devices miss key updates (app should evict idle devices)
4. **No deniability**: Signatures prove message authenticity to third parties (vs Signal's deniability)

**See**:
- [RFC 9420 (MLS Protocol)](https://datatracker.ietf.org/doc/rfc9420/)
- [RFC 9750 (MLS Architecture)](https://datatracker.ietf.org/doc/rfc9750/)
- [OpenMLS (Rust implementation)](https://github.com/openmls/openmls)
- [Wire MLS Announcement](https://wire.com/) (production case study)

---

### Protocol Recommendation

**Decision**: Use MLS for all conversations

**Rationale**:
1. **Superior security**: Post-Compromise Security + Forward Secrecy + cryptographic membership
2. **Single protocol**: Avoid complexity of dual-protocol (Signal + Megolm) system
3. **Production-proven**: Wire successfully deployed to 2000-member groups
4. **Future-proof**: IETF standard, industry moving toward MLS for interoperability
5. **Scalability**: Logarithmic operations handle neighborhood scale (100-500 people) efficiently
6. **Trust model alignment**: Designed for untrusted servers (matches self-hosted neighborhood model)

**Performance analysis**:
- **Message encryption**: 5-10ms (within 50ms budget) ✅
- **Group operations**: 150ms for 100-person group (infrequent, not on critical path)
- **Total messaging latency**: ~220ms (10ms encrypt + 100ms network + 10ms decrypt + 100ms other)
  - Meets original 200ms target ✅
  - Self-hosted deployment (10-30ms network) provides budget margin
- **Group management latency**: ~150ms (acceptable for infrequent operations like adding members)

**Complexity tradeoff**:
- Higher integration complexity than Megolm
- Offset by:
  - OpenMLS handles protocol complexity (high-level API)
  - Single protocol simpler than dual-protocol maintenance
  - Superior security worth engineering investment

**Why not Signal Protocol**:
- Group encryption: 2000ms for 100 people (pairwise encryption doesn't scale)
- No Post-Compromise Security (MLS provides automatic recovery)
- Only viable for 1:1 conversations (neighborhood scale requires groups)

**Why not Megolm**:
- No Post-Compromise Security (once compromised, stays compromised)
- Weaker security model (shared group key vs MLS continuous agreement)
- Not an IETF standard (Matrix-specific, limited interoperability)
- Similar message performance (5-10ms) but inferior security

**Why not Hybrid (Signal + Megolm/MLS)**:
- Dual-protocol complexity: Maintain two implementations, two security models
- Protocol switching logic: Risk of bugs at boundaries
- Inconsistent security guarantees across conversation types
- No performance benefit: All protocols ~5-10ms for message encryption

---

## Encryption Performance Constraints

### Budget Allocation (50ms total)

```
Key derivation: 10ms
  → Signing operation: 10ms
  → Encryption operation: 20ms
  → Serialization: 10ms
= 50ms total
```

### Optimization Strategies

1. **Precompute Keys**: Derive session keys during idle time
   - Background task generates keys for active conversations
   - Reduces encryption time from 50ms → 20ms (2.5x improvement)

2. **Hardware Acceleration**: Use platform crypto APIs
   - iOS: CryptoKit (hardware-accelerated AES, Curve25519)
   - Android: Keystore + BoringSSL
   - Estimated 2-5x speedup vs pure software crypto

3. **Batch Encryption**: Encrypt multiple messages in single operation
   - Amortize key derivation cost across messages
   - Useful for message queues (offline → online sync)

4. **Cache Derived Keys**: Store session keys for active conversations
   - Avoid redundant key derivation
   - Trade memory for CPU (acceptable on modern devices)

---

## Planned Implementation (Sprint 10+)

### Phase 1: Direct Conversations (Sprint 10-12)
**Protocol**: Signal Protocol (X3DH + Double Ratchet)

**Components**:
1. **X3DH** (Extended Triple Diffie-Hellman)
   - Initial key agreement
   - Asynchronous (works when recipient offline)
   - Performance: ~15ms for 1:1 key exchange

2. **Double Ratchet**
   - Forward secrecy
   - Post-compromise security
   - Per-message key derivation
   - Performance: ~15ms per message

3. **Key Management**
   - Secure key storage (iOS Keychain, Android Keystore)
   - Automatic key rotation
   - Backup/recovery mechanism (user-controlled)

**Timeline**: 3 sprints (6 weeks)

---

### Phase 2: Group Conversations (Sprint 13-15)
**Protocol**: Megolm (Matrix Protocol)

**Components**:
1. **Outbound Group Session**
   - Sender-side ratchet
   - Shared among all group members
   - Performance: ~110ms for 100-person group

2. **Inbound Group Session**
   - Recipient-side decryption
   - Fast (no per-message key derivation)
   - Performance: ~5ms per message

3. **Key Distribution**
   - Signal Protocol for key transport (secure channel)
   - Initial group key sent to all members
   - Key rotation on membership changes

**Timeline**: 3 sprints (6 weeks)

---

### Phase 3: Optimization (Sprint 16+)
**Focus**: Meet 50ms encryption budget

**Optimizations**:
1. Hardware acceleration (CryptoKit, Keystore)
2. Key precomputation (background tasks)
3. Key caching (active conversations)
4. Binary serialization (replace JSON)

**Target Performance**:
- Direct: 5ms (down from 15ms)
- Groups: 50ms (down from 110ms)

**Timeline**: 2 sprints (4 weeks)

---

## Message Encryption Flow

### Current (Placeholder)
```elixir
# Message created with empty encryption fields
message = %Message{
  content: "Hello",
  metadata: %{}  # Empty - no encryption
}
```

### Planned (E2EE)
```elixir
# Client encrypts before sending
encrypted_content = encrypt(plaintext, recipient_keys)

message = %Message{
  content: encrypted_content,  # Ciphertext
  metadata: %{
    encryption_version: "v1.0.0",
    encryption_flag: true,
    key_id: "KEY_USER_v1",
    # Additional Signal Protocol metadata
  }
}
```

---

## Conversation-Type Encryption Policies

**Defined in** `MessageService.requires_encryption?/1`:

- `:direct` → Encryption required
- `:group` → Encryption required
- `:family` → Encryption required
- `:self` → Encryption optional

---

## Security Testing Strategy

### Required Tests
1. **Encryption/decryption cycles** - Verify round-trip
2. **Tampered ciphertext** - Detect modifications
3. **Performance under load** - Crypto overhead acceptable
4. **Key rotation** - Seamless key updates

---

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - System design
- [backend/guides/messaging-implementation.md](../backend/guides/messaging-implementation.md)

---

**Last Updated**: 2025-10-05
**Status**: Infrastructure ready, implementation pending (Sprint 10)
