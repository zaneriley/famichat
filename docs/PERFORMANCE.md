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
| **Encryption** | <10ms | MLS uses symmetric AEAD for messages (5-10ms). Group operations (150ms) are infrequent, not on critical path. |
| **Network Operations** | <100ms | Self-hosted deployment advantage. Neighborhood-local server reduces latency vs centralized cloud. |
| **UI Rendering** | <16ms | 60fps target. Ensures smooth animations and transitions. |

**Total Budget Breakdown (Sender → Receiver)**:
```
User types character
  → Client captures (10ms)
  → Client encrypts (10ms)   # MLS symmetric AEAD
  → Network send (50ms)
  → Server processes (20ms)
  → Network receive (50ms)
  → Client decrypts (10ms)   # MLS symmetric AEAD
  → Client displays (10ms)
= 160ms total (40ms under budget) ✅
```

**Group Operations** (infrequent, not on critical messaging path):
```
Group membership change (add/remove member):
  → Tree operations (150ms for 100-person group)
  → Logarithmic scaling (efficient even at 10,000+ members)
  → Acceptable: User joins/leaves happen occasionally
  → Not blocking: Regular messaging continues unaffected
```

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

**Current Decision**: Deferred pending encryption protocol selection.

**Options**:
- **Character streaming**: Lower perceived latency (<10ms typing feedback), higher encryption overhead
- **Word batching**: Lower overhead, higher perceived latency (wait for word completion)

**Constraint**: Encryption budget (50ms) may require batching for performance.

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

### Protocol Selection: MLS (IETF Standard)

**Decision**: Use MLS for all conversations (both 1:1 and groups)

**Performance Characteristics**:

| Operation | Time | Frequency | Impact |
|-----------|------|-----------|--------|
| **Message encryption** | 5-10ms | Every message | ✅ Within 10ms budget |
| **Message decryption** | 5-10ms | Every message | ✅ Within 10ms budget |
| **Group setup** | 150ms (100 people) | Once per group | ✅ Infrequent, acceptable |
| **Add/remove member** | 150ms (100 people) | Occasional | ✅ Infrequent, acceptable |
| **Key rotation** | 150ms (100 people) | Periodic (weekly/monthly) | ✅ Infrequent, acceptable |

**Why MLS Works**:
1. **Message encryption uses symmetric AEAD**: After group is established, messages encrypted with shared group key
   - AES-GCM or ChaCha20-Poly1305 (5-10ms)
   - No per-recipient encryption (unlike Signal's pairwise approach)
2. **Group operations are infrequent**: 150ms tree operations only on membership changes
   - Not on critical messaging path
   - Logarithmic scaling (efficient even at 10,000+ members)
3. **Meets original 200ms budget**: 10ms encrypt + 100ms network + 10ms decrypt = 120ms core path

**Rejected Alternatives**:
- **Signal Protocol**: 2000ms for 100-person groups (pairwise encryption doesn't scale)
- **Megolm**: No Post-Compromise Security, not standardized (Matrix-specific)

**See**: [ENCRYPTION.md](ENCRYPTION.md#protocol-recommendation) for detailed protocol comparison

---

### MLS Performance Budget

**Message Encryption** (critical path):
```
Symmetric AEAD encryption: 5-10ms
  → AES-GCM or ChaCha20-Poly1305
  → Single encryption for all recipients
  → Well within 10ms budget ✅
```

**Group Operations** (off critical path):
```
Tree-based key agreement: 150ms (100 people)
  → Logarithmic operations (log₂(100) ≈ 7 tree levels)
  → Compute new group key
  → Distribute to all members
  → Infrequent: Only on membership changes
```

**Optimization Strategies**:
1. **Precompute keys**: Derive session keys during idle time
2. **Hardware acceleration**: Use native crypto libraries (iOS CryptoKit, Android Keystore)
3. **Batching**: Encrypt multiple messages in single operation (if protocol allows)
4. **Caching**: Cache derived keys for active conversations

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

### 3. Encryption Protocol Limitations

**Tradeoff**: Cannot use Signal Protocol for groups (too slow). Requires Megolm, MLS, or custom protocol.

**Rationale**: 50ms encryption budget is hard constraint. Signal Protocol takes 2000ms for 100-person groups.

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
- Batch encryption for message queues

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
