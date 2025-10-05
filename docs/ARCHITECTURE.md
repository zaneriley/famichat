# Famichat - System Architecture

**Last Updated**: 2025-10-05

See [STATUS.md](../STATUS.md) for current implementation details.

---

## System Overview

Famichat is a Phoenix/Elixir backend with Flutter client, designed for self-hosted family communication.

```
┌─────────────────┐     WebSocket/HTTP      ┌──────────────────┐
│ Flutter Client  │ <──────────────────────> │ Phoenix Backend  │
│  (iOS/Web)      │                          │  (Elixir)        │
└─────────────────┘                          └──────────────────┘
                                                      │
                                        ┌─────────────┴──────────────┐
                                        │                            │
                                 ┌──────▼───────┐          ┌────────▼────────┐
                                 │  PostgreSQL  │          │  Object Storage │
                                 │  (Metadata)  │          │  (S3/MinIO)     │
                                 └──────────────┘          └─────────────────┘
```

---

## Backend Architecture (Phoenix/Elixir)

### Application Structure
**Location**: `backend/lib/famichat/`

**Core Contexts**:
- `Chat` - Messaging and conversations
  - `MessageService` - Send/retrieve messages
  - `ConversationService` - Create/manage conversations
  - `ConversationVisibilityService` - Hide/unhide conversations
- `Accounts` - User authentication (NOT YET IMPLEMENTED)

### Key Design Decisions

#### 1. Conversation Type Boundaries
**Decision**: Immutable conversation types (direct, self, group, family)

**Rationale**:
- Clear user mental models
- Simplified authorization
- Prevents privacy issues from type changes

**See**: [decisions/001-conversation-types.md](decisions/001-conversation-types.md)

---

#### 2. Telemetry Strategy
**Decision**: All critical operations wrapped in `:telemetry.span/3`

**Performance Budget**: 200ms default
**Event Naming**: `[:famichat, :context, :action]`

**See**: [backend/guides/telemetry.md](../backend/guides/telemetry.md)

---

#### 3. Encryption Approach
**Decision**: Hybrid encryption (E2EE + field-level + infrastructure)

**Components**:
- Client-side E2EE (Signal Protocol - planned)
- Field-level (Cloak.Ecto for sensitive data)
- Database encryption at rest

**See**: [ENCRYPTION.md](ENCRYPTION.md)

---

### Database Schema

**Current Migrations**: 9 applied

**Core Tables**:
- `users` - User accounts (with family_id, role)
- `families` - Household grouping
- `conversations` - Multi-type conversations (direct, self, group, family)
- `messages` - Message content with metadata
- `conversation_participants` - Join table (users ↔ conversations)
- `group_conversation_privileges` - Role tracking (admin/member)

**Key Fields**:
- `conversations.direct_key` - SHA256 hash for deduplication
- `conversations.hidden_by_users` - Array of user IDs (soft delete)
- `messages.metadata` - JSONB for encryption data

---

### Real-Time Communication

**Phoenix Channels**:
- Topic format: `message:<type>:<conversation_id>`
- Token-based authentication (Phoenix.Token)
- Performance budget: 200ms
- Telemetry on all operations

**Implementation**: [backend/lib/famichat_web/channels/message_channel.ex](../backend/lib/famichat_web/channels/message_channel.ex)

---

## Frontend Architecture (Flutter)

**Status**: Proof-of-concept only (5% complete)

**Current**:
- Basic HTTP client
- Config loading from JSON
- Simple Material Design UI

**Needed**:
- WebSocket client (phoenix_socket package)
- State management (Provider or Bloc)
- Message UI components
- Offline storage

---

## Infrastructure

### Development
- Docker Compose
- Hot reload via volume mounts
- `./run` script for commands

### Production (Planned)
- Docker with production config
- HTTPS/TLS
- Database backups
- Monitoring (Prometheus/Grafana)
- Error tracking (Sentry)

---

## Security Architecture

See [ENCRYPTION.md](ENCRYPTION.md) for detailed security design.

**Current**:
- Token-based channel authentication ✅
- Family-based authorization ✅
- Encryption infrastructure ready ⚠️ (no crypto yet)

**Planned**:
- E2EE with Signal Protocol
- Key management system
- Device trust verification

---

## Performance Architecture

Performance is a critical constraint that informs all architectural decisions.

**Hard Requirements**:
- Sender → Receiver latency: <200ms (industry standard for "instant")
- Typing → Display latency: <10ms (perception threshold)
- Encryption: <50ms (limits protocol choices)
- Network operations: <100ms (self-hosted advantage)

**Budget Breakdown (Sender → Receiver)**:
```
Client capture (10ms)
  → Client encrypt (50ms)
  → Network send (50ms)
  → Server process (20ms)
  → Network receive (50ms)
  → Client decrypt (10ms)
  → Client display (10ms)
= 200ms total
```

**Architectural Implications**:
1. **Optimistic UI**: Display immediately, sync asynchronously
2. **Binary Protocol**: Avoid JSON serialization overhead (10-20ms saved)
3. **Persistent WebSockets**: Eliminate connection handshake from critical path
4. **Self-Hosted Deployment**: Neighborhood-local server = 1-30ms network latency (vs 50-150ms cloud)
5. **Encryption Protocol Constraint**: Signal Protocol rejected for groups (2000ms), evaluating Megolm (110ms) or MLS (150ms)

**Monitoring**:
- Telemetry on all critical operations (`:telemetry.span/3`)
- P50/P95/P99 latency tracking
- Automated alerts on budget violations
- Performance regression tests in CI

**See**: [PERFORMANCE.md](PERFORMANCE.md) for detailed performance architecture.

---

## Deployment Model

**Primary Model**: Self-hosted by neighborhoods

**Scale**: 100-500 people per instance
- Smaller than "city" (too large, impersonal)
- Larger than "family" (needs multi-family communication)
- "Neighborhood" = natural social boundary

**Deployment Architecture**:
```
┌─────────────────────────────────────────────────────────────┐
│                      Neighborhood Instance                   │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │  Family A  │  │  Family B  │  │  Family C  │  (10-50    │
│  │ (5 users)  │  │ (8 users)  │  │ (12 users) │   families)│
│  └────────────┘  └────────────┘  └────────────┘            │
│                                                              │
│  Single Admin (neighborhood organizer)                      │
│  Self-hosted server (Docker + PostgreSQL + S3/MinIO)       │
│  No federation (initially)                                  │
└─────────────────────────────────────────────────────────────┘
```

**Why Self-Hosting**:
1. **Data Ownership**: No centralized provider, community controls data
2. **Privacy**: Admin cannot read E2E encrypted messages
3. **Performance**: Local server enables <30ms network latency (vs 50-150ms centralized)
4. **Control**: Neighborhood self-governance, custom features
5. **Alignment**: Community-operated, not profit-driven

**Requirements**:
- Docker & Docker Compose
- PostgreSQL 16
- Object storage (S3/MinIO or local filesystem)
- TURN/STUN servers (for WebRTC video calls)
- SSL/TLS certificates (Let's Encrypt)

**Not Planned** (Initially):
- SaaS/managed hosting
- Multi-tenancy
- Centralized infrastructure
- Federation between instances (deferred for future consideration)

---

## Related Documentation

- [VISION.md](VISION.md) - Product vision & goals
- [ENCRYPTION.md](ENCRYPTION.md) - Security architecture
- [API-DESIGN.md](API-DESIGN.md) - API patterns
- [backend/guides/](../backend/guides/) - Implementation guides

---

**Last Updated**: 2025-10-05
