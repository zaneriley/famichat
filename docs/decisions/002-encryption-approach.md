# ADR 002: Hybrid Encryption Strategy

**Date**: 2025-03-10
**Status**: Accepted

---

## Context

Need to decide encryption strategy balancing security and implementation complexity.

## Decision

Use **hybrid encryption approach**:
1. Client-side E2EE (Signal Protocol)
2. Field-level encryption (Cloak.Ecto)
3. Database encryption at rest

## Rationale

- **E2EE**: Zero-knowledge for message content (privacy)
- **Field-level**: Protects sensitive user data (email, tokens) while allowing queries
- **Infrastructure**: Defense-in-depth for data at rest

## Implementation

Sprint 10 will implement Signal Protocol:
- X3DH for key exchange
- Double Ratchet for forward secrecy
- Metadata in `messages.metadata` JSONB field

## Consequences

### Positive
- Strong privacy guarantees
- Industry-standard protocol (Signal)
- Layered security (defense-in-depth)

### Negative
- Complexity (key management, rotation)
- Performance overhead
- Cannot search encrypted messages server-side

---

**Related**: [ENCRYPTION.md](../ENCRYPTION.md)
