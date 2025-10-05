# ADR 002: Hybrid Encryption Strategy

**Date**: 2025-03-10
**Status**: Accepted (Updated 2025-10-05)
**Updated By**: ADR 006 (Signal Protocol evaluation vs alternatives)

---

## Context

Need to decide encryption strategy balancing security and implementation complexity for self-hosted family messaging.

## Decision

Use **hybrid encryption approach**:
1. **Client-side E2EE** (Signal Protocol) - for message content
2. **Field-level encryption** (Cloak.Ecto) - for sensitive user data
3. **Database encryption at rest** - for defense-in-depth

## Rationale

### Why E2EE (vs database encryption only)?
- Zero-knowledge guarantee (admin cannot read messages)
- Forward secrecy (past messages safe if server compromised)
- User expectation (modern messaging apps have E2EE)
- Impossible to retrofit later (must build in from Day 1)

### Why Signal Protocol (vs MLS or Megolm)?
- Right-sized for families (2-6 people per household)
- Battle-tested (WhatsApp, Signal, 2B+ users)
- Deniability (better for family trust dynamics)
- Performance: 30-90ms for families (vs MLS 150ms)

**See ADR 006 for full Signal vs MLS vs Megolm evaluation**

### Why Field-Level Encryption?
- Protects sensitive user data (email, tokens) while allowing queries
- Complements E2EE (different threat model)

### Why Database Encryption at Rest?
- Defense-in-depth for infrastructure layer
- Protects backups, snapshots
- Standard security practice

## Implementation

**Sprint 8-12:** Signal Protocol E2EE
- Rust NIF wrapper for libsignal-client
- X3DH for asynchronous key exchange
- Double Ratchet for forward secrecy + post-compromise security
- Pairwise encryption for group messages

**Timeline:** 5 weeks
- Week 1-2: Rust toolchain + libsignal integration
- Week 3: Key management (identity keys, prekeys, sessions)
- Week 4: Message encryption/decryption
- Week 5: LiveView UI integration

## Consequences

### Positive
- ✅ Strong privacy guarantees (zero-knowledge)
- ✅ Industry-standard protocol (proven at billions-of-users scale)
- ✅ Layered security (E2EE + field-level + infrastructure)
- ✅ Deniability (better for family trust)
- ✅ Performance acceptable (30-90ms for families)

### Negative
- ❌ Complexity (key management, session state, rotation)
- ❌ Performance overhead (encryption latency)
- ❌ Cannot search encrypted messages server-side
- ❌ Rust dependency (adds build complexity)
- ❌ Key recovery challenges (lost device = lost keys, need backup strategy)

### Risks & Mitigations

**Risk:** Layer 5 (inter-family, 20-30 people) may exceed performance budget (450ms)
**Mitigation:** Acceptable latency for infrequent coordination, or pivot to hybrid (Signal for families, MLS for large channels)

**Risk:** Rust NIF crashes BEAM VM
**Mitigation:** Panic handlers, error boundaries, telemetry, dirty schedulers

**Risk:** Key management complexity causes user friction
**Mitigation:** Defer multi-device and key backup to post-MVP, focus on single-device first

---

## Related Documentation

- **ADR 006**: [Signal Protocol for E2EE](006-signal-protocol-for-e2ee.md) - Full protocol evaluation
- **ADR 005**: [Encryption Metadata Schema](005-encryption-metadata-schema.md) - Key storage design
- **ENCRYPTION.md**: [Security Architecture](../ENCRYPTION.md) - Implementation details

---

**Last Updated**: 2025-10-05 (Updated rationale with ADR 006 evaluation)
**Next Review**: After Layer 5 implementation
