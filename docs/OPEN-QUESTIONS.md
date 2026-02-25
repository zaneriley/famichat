# Famichat - Open Questions

**Last Updated**: 2026-02-25

This document tracks architectural and product decisions that require discussion before implementation.

---

## Critical Questions (Need Resolution by Sprint 10)

### Q1: Encryption Protocol Choice

**Status**: ✅ **RESOLVED: MLS-first (OpenMLS)**

**Final Decision**: Use MLS/OpenMLS as the primary E2EE direction.

**Rationale**:
- Product trajectory now includes inter-family and neighborhood-scale coordination.
- MLS is standardized (RFC 9420) with architecture guidance (RFC 9750).
- GSMA RCS E2EE specifications now define MLS-based interoperability.
- Strategic fit is stronger for long-term group messaging than maintaining a small-group-only protocol direction.

**Implementation**:
- OpenMLS (Rust) via Rustler NIF
- MLS key package + group state + epoch/commit lifecycle
- Server-side encryption/decryption integration into messaging flow
- Timeline: Sprint 9-10

**Operational Caveat**:
- OpenMLS requires active dependency hygiene and prompt security updates.

**See**:
- [ADR 010](decisions/010-mls-first-for-neighborhood-scale.md) for decision rationale and references
- [ADR 006](decisions/006-signal-protocol-for-e2ee.md) for superseded Signal-first analysis

---

### Q2: Encryption Budget Flexibility

**Status**: ✅ **RESOLVED: MLS-first with explicit performance guardrails**

**Updated Context**: MLS app-message flow can meet user-facing latency goals, while commit/update/remove operations are sensitive to churn and tree health. Performance policy now distinguishes steady-state messaging from membership-change operations.

**Revised Budget Breakdown**:
```
Client capture (10ms)
  → Encrypt/decrypt via MLS path (steady-state app-message target <=50ms)
  → Network send (50ms)
  → Server process (20ms)
  → Network receive (50ms)
  → Client display (10ms)
= target <=200ms steady-state user path
```

**Group Operations** (infrequent, not on critical messaging path):
```
Group setup/membership change:
  → Commit/update/remove latency varies with churn and tree health
  → Must be monitored separately from app-message latency
  → Guardrails required for group size + change frequency
```

**Conclusion**:
- **Primary path**: MLS/OpenMLS (per ADR 010)
- **Policy**: Separate SLOs for steady-state app messages vs group commit/update operations
- **Action**: Instrument p50/p95/p99 for both paths before broad dogfooding

**User Decision Needed**: None - protocol direction is locked to MLS-first.

**Timeline**: Resolved (MLS-first accepted with operational guardrails)

**See**: [ENCRYPTION.md](ENCRYPTION.md) and [ADR 010](decisions/010-mls-first-for-neighborhood-scale.md)

---

## Important Questions (Need Resolution by Sprint 15)

### Q3: Neighborhood Federation Model

**Context**: Initial design is single-neighborhood instances (no federation). Future may require cross-neighborhood communication.

**Options**:

1. **No Federation** (Current Plan)
   - Each neighborhood is isolated
   - Simplest implementation
   - Lowest latency (no inter-server communication)

2. **Optional Federation** (Future Feature)
   - Neighborhoods can link together
   - Enables cross-neighborhood messaging
   - Adds complexity: trust model, routing, latency

3. **Built-In Federation** (Matrix-Style)
   - All neighborhoods federate by default
   - Maximum connectivity
   - Significant complexity: protocol design, server discovery, trust chains

**Question**: Should we design for federation from the start, or defer indefinitely?

**Implications**:
- **No Federation**: Simpler, faster development, but limits future growth
- **Optional Federation**: Moderate complexity, enables future expansion
- **Built-In Federation**: High complexity, delays MVP, but most flexible

**Decision Needed**: By Sprint 15 (before production deployment)

**See**: [VISION.md](VISION.md#deployment-model)

---

### Q4: Key Recovery & Backup UX

**Context**: E2EE requires secure key management. If user loses device, they lose message history (unless backed up).

**Options**:

1. **No Key Backup** (Highest Security)
   - Keys stored only on device
   - Lost device = lost history
   - Simplest implementation

2. **Cloud Key Backup** (User-Controlled)
   - User generates backup passphrase
   - Keys encrypted with passphrase, stored on server
   - User can recover keys with passphrase
   - Risk: Weak passphrase = compromised keys

3. **Social Key Recovery** (Signal-Style)
   - User designates trusted contacts
   - Key split among contacts (Shamir Secret Sharing)
   - Requires 3-of-5 contacts to recover
   - Complex UX, social engineering risk

**Question**: What key recovery mechanism should we support?

**User Impact**: High. Wrong choice = frustrated users or security vulnerability.

**Decision Needed**: By Sprint 12 (E2EE key management implementation)

**See**: [ENCRYPTION.md](ENCRYPTION.md#planned-implementation)

---

### Q4b: Passkey Nudging & Trusted Window Renewal

**Context**: Plan Section 10 calls for marking an `enrollment_required_since` timestamp when a user logs in via magic link without an enrolled passkey. This state now ships (Oct 13, 2025) and clears once an active passkey exists. The Wax-backed implementation now emits WebAuthn `publicKey` payloads plus an opaque handle (legacy `{challenge, challenge_token}` payload removed). Refresh-session handling still keeps the trusted device window as a fixed 30-day expiry (it does not extend when the user refreshes tokens).

**Open Questions**:
- Should trusted devices roll their `trusted_until` forward on each refresh, or expire exactly 30 days after the user opted in?
- What is the timeline for swapping to Wax-generated `PublicKeyCredentialCreationOptions`/`PublicKeyCredentialRequestOptions`, and how will we deliver deterministic fixtures for tests?

**Decision Needed**: Before shipping the passwordless fallback UX in Sprint 8.

**See**: Sprint 7 follow-ups in `docs/sprints/STATUS.md`.

---

### Q5: Token Architecture for Device Revocation

**Context**: Current Phoenix.Token expires in 24 hours but cannot be revoked. Need refresh token rotation for device management.

**Question**: Should we implement custom token rotation or use existing library (Guardian, Pow)?

**Options**:

1. **Custom Token Rotation**
   - Full control over implementation
   - Simpler (no library dependencies)
   - Risk: Security bugs in custom crypto

2. **Guardian Library**
   - Battle-tested, widely used
   - Adds dependency
   - May be overkill for use case

3. **Pow Library**
   - Designed for Phoenix
   - Includes user management (may not want)
   - Heavy dependency

**Decision Needed**: By Sprint 9 (Story 7.9 auth implementation)

**See**: Status report security vulnerabilities section

---

## Design Questions (Need Resolution by Sprint 20)

### Q6: "Cozy" Product Differentiation

**Context**: Vision includes "cozy, customizable UX" inspired by Animal Crossing. Need to define what "cozy" means in practice.

**Questions**:
1. What specific features make the app feel "cozy"?
   - Ambient tracing (shared canvas)?
   - Phone bumping (physical gesture to add contacts)?
   - Status updates ("Thinking of You" vs "Online/Offline")?
   - Weather widgets (location-based)?
   - Custom family branding (logo, colors)?

2. How do we balance "cozy" with performance requirements?
   - Animations add latency
   - Rich UI consumes battery
   - Custom features add complexity

3. What's the MVP for "cozy" vs future enhancement?
   - MVP: Basic theming (colors, logo)?
   - Future: Ambient features (tracing, bumping)?

**Decision Needed**: By Sprint 20 (UI/UX implementation phase)

**See**: [VISION.md](VISION.md#user-experience--design-principles)

---

### Q7: White-Label Customization Scope

**Context**: Platform is white-label (each neighborhood can customize). Need to define boundaries.

**Questions**:
1. What can neighborhoods customize?
   - Branding only (logo, colors, name)?
   - Features (enable/disable video calls, letters, etc.)?
   - Custom features (family-specific functionality)?

2. Who manages customization?
   - Neighborhood admin via web UI?
   - Requires developer (code changes)?
   - Plugin system (future)?

3. How do we maintain updates across customized instances?
   - Docker image updates
   - Database migrations
   - Feature flag management

**Decision Needed**: By Sprint 15 (before production deployment)

**See**: [VISION.md](VISION.md#white-label--turnkey-considerations)

---

## Technical Questions (Lower Priority)

### Q8: Database Encryption Metadata Schema

**Context**: Current design stores encryption metadata in JSONB `messages.metadata`. This prevents indexing (performance issue).

**Options**:

1. **Keep JSONB** (Current)
   - Flexible schema
   - Cannot index (slow queries)
   - Simpler implementation

2. **Separate Encryption Table**
   - `message_encryption` table with indexed fields
   - Faster queries (indexed key_id, version, etc.)
   - More complex schema

**Question**: Move to separate table or optimize JSONB queries?

**Decision Needed**: By Sprint 11 (E2EE implementation)

**See**: ADR proposal in conversation summary

---

### Q9: Group Membership Updates (Conversation Uniqueness)

**Context**: Current design enforces unique conversations via `direct_key` (SHA256 of sorted participant IDs). What happens when group membership changes?

**Options**:

1. **Update Existing Conversation**
   - Modify `participants` array
   - Recompute `direct_key`? (breaks uniqueness constraint)
   - Message history preserved

2. **Create New Conversation**
   - Leave old conversation (read-only)
   - Create new conversation with updated members
   - Message history split across conversations

3. **Immutable Membership**
   - Cannot add/remove members
   - Must create new group
   - Simplest, most restrictive

**Question**: How to handle group membership changes?

**Decision Needed**: By Sprint 10 (group conversation features)

**See**: [VISION.md](VISION.md#open-questions)

---

### Q10: Conversation Computed Keys & Encryption

**Context**: `direct_key` uses SHA256 of participant IDs. How does this integrate with E2EE key management?

**Question**: Should `direct_key` be derived from cryptographic keys or remain separate?

**Options**:

1. **Separate Keys** (Current)
   - `direct_key` = SHA256(participant_ids) - for uniqueness
   - Encryption keys = derived from Signal/Megolm protocol
   - Simpler separation of concerns

2. **Unified Keys**
   - `direct_key` = derived from encryption keys
   - Ensures conversation uniqueness tied to encryption
   - More complex key derivation

**Decision Needed**: By Sprint 11 (E2EE implementation)

**See**: [VISION.md](VISION.md#open-questions)

---

## Decision Process

### How to Resolve Questions

1. **Research**: Gather technical data, benchmark performance, review security implications
2. **Prototype**: Build proof-of-concept for high-risk decisions (encryption protocol, federation)
3. **Discuss**: Review options with stakeholders (user, security expert, performance expert)
4. **Document**: Record decision in appropriate ADR (Architecture Decision Record)
5. **Update Docs**: Reflect decision in VISION.md, ARCHITECTURE.md, ROADMAP.md

### Decision Timeline

| Question | Priority | Deadline | Status | Owner |
|----------|----------|----------|--------|-------|
| Q1: Encryption Protocol | Critical | Sprint 9 | ✅ **MLS-first (ADR 010)** | User |
| Q2: Encryption Budget | Critical | Sprint 9 | ✅ **Resolved: Meets 200ms budget** | N/A |
| Q5: Token Architecture | High | Sprint 9 | Developer |
| Q8: Encryption Metadata Schema | High | Sprint 11 | Developer |
| Q9: Group Membership Updates | High | Sprint 10 | User + Developer |
| Q3: Federation Model | Medium | Sprint 15 | User |
| Q4: Key Recovery UX | Medium | Sprint 12 | User |
| Q6: "Cozy" Definition | Medium | Sprint 20 | User |
| Q7: White-Label Scope | Medium | Sprint 15 | User |
| Q10: Computed Keys | Low | Sprint 11 | Developer |

---

## Related Documentation

- [VISION.md](VISION.md) - Product vision and goals
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [ENCRYPTION.md](ENCRYPTION.md) - Security architecture
- [PERFORMANCE.md](PERFORMANCE.md) - Performance budgets
- [decisions/](decisions/) - Architecture Decision Records (ADRs)

---

**Last Updated**: 2026-02-25
**Version**: 1.1
**Status**: Living document - updated as questions are resolved
