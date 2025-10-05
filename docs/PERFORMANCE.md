# Performance Architecture

**Last Updated**: 2025-10-05

---

## Philosophy

Performance is a security feature. Users trust systems that feel reliable and responsive. If a secure messaging app feels slow or broken, users will:
1. Doubt the security mechanisms are working correctly
2. Abandon the platform for faster alternatives (often less secure)
3. Disable security features to improve perceived speed

**Core Principle**: Security mechanisms add latency. E2EE encryption requires key derivation, signing operations, and additional network round trips. The system must architect around these constraints to deliver both security and speed.

---

## Performance Budgets

Performance budgets are hard constraints that inform all architectural decisions.

| Operation | Budget | Rationale |
|-----------|--------|-----------|
| **Sender → Receiver** | <200ms | Industry standard for "instant" messaging (WhatsApp, Telegram target this). Beyond 200ms, users perceive delay. |
| **Typing → Display** | <10ms | Perception threshold. Below 10ms feels instantaneous. Above 10ms, typing feels laggy. |
| **Encryption** | <10ms | Signal Protocol uses symmetric ratchet for individual encryptions (~15ms per recipient). Family scale (2-6 people) = 30-90ms total. |
| **Network Operations** | <100ms | Self-hosted deployment advantage. Neighborhood-local server reduces latency vs centralized cloud. |
| **UI Rendering** | <16ms | 60fps target. Ensures smooth animations and transitions. |

**Total Budget Breakdown (Sender → Receiver)**:
```
User types message
  → Client captures (10ms)
  → Client encrypts (30-90ms)  # Signal pairwise encryption for 2-6 recipients
  → Network send (50ms)
  → Server processes (20ms)
  → Network receive (50ms)
  → Client decrypts (15ms)    # Signal symmetric ratchet
  → Client displays (10ms)
= 185-325ms total for family groups
```

**Layer-Specific Performance**:
- **Layer 1 (Dyad, 2 people)**: 30ms encryption → 185ms total ✅
- **Layer 2 (Triad, 4 people)**: 60ms encryption → 215ms total ✅
- **Layer 3 (Extended, 6 people)**: 90ms encryption → 245ms total ✅
- **Layer 5 (Inter-family, 20-30 people)**: 300-450ms encryption → 545-695ms total ⚠️

**Note**: Layer 5 exceeds 200ms budget but is acceptable for infrequent cross-family coordination. If needed, can pivot to MLS for Layer 5 only.

---

## Architectural Decisions for Performance

### 1. Optimistic UI Updates

**Problem**: Waiting for server confirmation adds 100-150ms latency to typing feedback.

**Solution**: Display user's typing immediately, synchronize with server asynchronously.

**Implementation**:
- Client renders typed character within 10ms budget
- Background process handles encryption + network sync
- Roll back on failure (rare, handled gracefully)

**Tradeoff**: Risk of displaying message that fails to send (mitigated by retry logic + error UI).

---

### 2. Character Streaming vs Batching

**Problem**: Should we send each character individually or batch into words/sentences?

**Current Decision**: Message batching (send complete messages, not character-by-character).

**Rationale**:
- Signal Protocol's pairwise encryption (30-90ms for families) makes per-character streaming impractical
- Users expect complete message delivery (similar to WhatsApp, Signal)
- Optimistic UI can show typing feedback locally while encryption happens in background

**Implementation**: User types locally (instant feedback), sends complete message when pressing "Send".

---

### 3. Binary Protocol Over JSON

**Problem**: JSON serialization/parsing adds 5-15ms per message.

**Solution**: Use binary protocol (MessagePack, Protocol Buffers, or custom format).

**Implementation**:
- Phoenix Channels can transport binary
- Client/server share schema definitions
- Reduces payload size (bandwidth savings)

**Benefit**: 10-20ms saved per message + bandwidth reduction.

---

### 4. WebSocket Connection Pooling

**Problem**: Opening new WebSocket connections adds 50-100ms handshake latency.

**Solution**: Maintain persistent WebSocket connection per client.

**Implementation**:
- Phoenix Channels (already implemented)
- Client reconnects on disconnect (automatic)
- Server-side connection pooling (Cowboy handles this)

**Benefit**: Eliminates connection handshake from critical path.

---

### 5. Database Query Optimization

**Problem**: Slow queries block message delivery.

**Solution**: Database indexes + query optimization + caching.

**Implementation**:
- Indexes on `conversations.participants` (GIN index for JSONB)
- Indexes on `messages.conversation_id` and `messages.inserted_at`
- Query result caching for frequently accessed conversations
- Connection pooling (already configured)

**Monitoring**: Track query times with telemetry, alert on >20ms queries.

---

### 6. Self-Hosted Deployment Advantage

**Problem**: Centralized cloud services have inherent network latency (50-150ms to data center).

**Solution**: Self-hosted deployment in neighborhood's local network.

**Benefit**:
- Neighborhood-local server: 1-10ms network latency (LAN)
- Same geographic area: 10-30ms network latency (regional)
- Centralized cloud: 50-150ms network latency (distant data center)

**Tradeoff**: Requires neighborhood to manage infrastructure (complexity).

---

## Encryption Performance Constraints

### Protocol Selection: Signal Protocol

**Decision**: Use Signal Protocol for all conversations (family scale: 2-6 people)

**Performance Characteristics**:

| Operation | Time | Frequency | Impact |
|-----------|------|-----------|--------|
| **Message encryption (per recipient)** | ~15ms | Every message | ✅ Pairwise encryption |
| **Message decryption** | ~15ms | Every message | ✅ Symmetric ratchet |
| **Session setup (X3DH)** | 50-100ms | Once per contact | ✅ Infrequent, one-time |
| **Key rotation (Double Ratchet)** | <1ms | Every message | ✅ Automatic, negligible |

**Performance at Family Scale**:
- **2 people (Layer 1)**: 15ms × 2 = 30ms ✅
- **4 people (Layer 2)**: 15ms × 4 = 60ms ✅
- **6 people (Layer 3)**: 15ms × 6 = 90ms ✅
- **20-30 people (Layer 5)**: 15ms × 20-30 = 300-450ms ⚠️ (acceptable for infrequent inter-family coordination)

**Why Signal Protocol Works**:
1. **Right-sized for families**: Pairwise encryption performs well at 2-6 people
2. **Battle-tested**: WhatsApp (2B+ users), Signal, Facebook Messenger
3. **Deniability**: Uses MACs (not signatures), better for family trust
4. **Forward Secrecy + PCS**: Double Ratchet provides both
5. **Meets 200ms budget for Layers 1-3**: 30-90ms encryption well within budget

**Why Not MLS?**:
- MLS optimizes for large groups (100+ people) with tree-based operations
- At family scale (2-6 people), MLS tree overhead adds unnecessary complexity
- Signal's pairwise approach is simpler and performs better at this scale

**See**: [ENCRYPTION.md](ENCRYPTION.md) and [ADR 006](decisions/006-signal-protocol-for-e2ee.md) for detailed protocol evaluation

---

### Signal Protocol Performance Budget

**Message Encryption** (critical path):
```
Pairwise encryption (per recipient): ~15ms
  → Symmetric ratchet (ChaCha20-Poly1305)
  → HMAC authentication
  → Per-recipient encryption (N recipients = N × 15ms)

Family scale examples:
  → 2 people: 30ms total ✅
  → 4 people: 60ms total ✅
  → 6 people: 90ms total ✅
```

**Session Setup** (one-time, off critical path):
```
X3DH key exchange: 50-100ms
  → ECDH operations (3-4 key agreements)
  → Initial shared secret derivation
  → First message encrypted
  → Infrequent: Only when establishing new contact
```

**Optimization Strategies**:
1. **Precompute keys**: Derive session keys during idle time
2. **Hardware acceleration**: Use native crypto libraries (iOS CryptoKit, Android Keystore)
3. **Caching**: Cache active session states for frequent conversations
4. **Background encryption**: Encrypt in background thread while showing optimistic UI

---

## Measurement & Monitoring

### Telemetry Integration

**Current Implementation**: `:telemetry.span/3` with performance budgets tracked.

**Metrics Tracked**:
- Message send latency (P50, P95, P99)
- Encryption time (P50, P95, P99)
- Network round trip time (P50, P95, P99)
- Database query time (per query)
- UI render time (frame drops)

**Budget Violation Alerts**:
- Alert if P95 > budget (indicates performance regression)
- Track violations over time (trend analysis)
- Automated regression tests (fail CI if budget exceeded)

**See**: [backend/guides/telemetry.md](../backend/guides/telemetry.md) for implementation details.

---

### Performance Testing

**Load Testing**:
- Simulate 100-500 concurrent users
- Measure end-to-end latency under load
- Identify bottlenecks (database, encryption, network)

**Benchmarking**:
- Encryption protocol performance (standalone benchmarks)
- Database query performance (query plan analysis)
- Network latency (ping tests, traceroute)

**Continuous Monitoring**:
- Production telemetry (all deployments)
- Automated alerts on budget violations
- Weekly performance reports (track trends)

---

## Tradeoffs Accepted

### 1. Complexity for Speed

**Tradeoff**: Optimistic UI, binary protocols, and encryption optimization add engineering complexity.

**Rationale**: Performance is non-negotiable. Users will not adopt a slow messaging app, regardless of security benefits.

---

### 2. Self-Hosting Requirement

**Tradeoff**: Requires neighborhood to manage infrastructure (Docker, database, backups).

**Rationale**: Self-hosting enables <30ms network latency (vs 50-150ms for centralized cloud). This is 20-120ms saved from total 200ms budget.

---

### 3. Signal Protocol Scaling Limitations

**Tradeoff**: Signal Protocol's pairwise encryption doesn't scale beyond ~30 people (450ms).

**Rationale**: At family scale (2-6 people), Signal performs excellently (30-90ms). For Layer 5 inter-family coordination (20-30 people), 300-450ms is acceptable given infrequent usage. If scale exceeds 30 people, can pivot to MLS for those specific conversations.

---

### 4. No Federation (Initially)

**Tradeoff**: Neighborhoods cannot communicate across instances (initially).

**Rationale**: Federation adds network hops (latency) and complexity. Focus on single-neighborhood performance first, add federation later if needed.

---

## Future Optimizations

### Phase 1: Current Focus (Sprint 7-10)
- Establish baseline performance metrics
- Implement telemetry and monitoring
- Optimize database queries
- Select encryption protocol

### Phase 2: Encryption Optimization (Sprint 11-15)
- Hardware-accelerated crypto (iOS CryptoKit, Android Keystore)
- Key precomputation during idle time
- Background thread encryption (non-blocking UI)

### Phase 3: Advanced Optimizations (Sprint 16+)
- Edge caching for frequently accessed data
- WebAssembly crypto for web client
- Custom binary protocol (replace JSON entirely)
- Server-side message batching (reduce round trips)

---

## Related Documentation

- **Vision**: [VISION.md](VISION.md) - Performance requirements rationale
- **Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md) - System design decisions
- **Encryption**: [ENCRYPTION.md](ENCRYPTION.md) - Security architecture with protocol evaluation
- **Telemetry**: [../backend/guides/telemetry.md](../backend/guides/telemetry.md) - Performance monitoring implementation
- **Open Questions**: [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md) - Undecided architectural questions

---

**Last Updated**: 2025-10-05
**Version**: 1.0
**Status**: Living document - updated as performance strategy evolves
