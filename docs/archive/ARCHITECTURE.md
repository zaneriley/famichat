# Famichat - System Architecture

**Last Updated**: 2026-02-25

See [sprints/STATUS.md](sprints/STATUS.md) for current implementation details.
See [ia-lexicon.md](ia-lexicon.md) for canonical terminology and ownership language.

---

## System Overview

Famichat is a Phoenix/Elixir backend with Phoenix LiveView frontend, designed for self-hosted family communication.

```
┌─────────────────┐     WebSocket/HTTP      ┌──────────────────┐
│ Phoenix LiveView│ <──────────────────────> │ Phoenix Backend  │
│  (Web Browser)  │                          │  (Elixir)        │
└─────────────────┘                          └──────────────────┘
                                                      │
                                        ┌─────────────┴──────────────┐
                                        │                            │
                                 ┌──────▼───────┐          ┌────────▼────────┐
                                 │  PostgreSQL  │          │  Object Storage │
                                 │  (Metadata)  │          │  (S3/MinIO)     │
                                 └──────────────┘          └─────────────────┘
```

**Note**: Native mobile app deferred until Layer 4 (Autonomy & Safety features requiring background geolocation). Current focus is dogfooding with LiveView for Layers 0-3.

---

## Backend Architecture (Phoenix/Elixir)

### Application Structure
**Location**: `backend/lib/famichat/`

**Core Contexts**:
- `Chat` - Messaging and conversations
  - `MessageService` - Send/retrieve messages
  - `ConversationService` - Create/manage conversations
  - `ConversationVisibilityService` - Hide/unhide conversations
  - Planned Sprint 9 hardening boundary: `ConversationSecurityStateStore` (durable conversation security state)
- `Accounts` - User authentication, invites, passkeys, and device trust (invite completion issues a short-lived passkey register token; passkey challenges only issued after exchanging that token or from trusted sessions)

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
**Decision**: Hybrid encryption (MLS + field-level + infrastructure)

**Trust model**: The server is the trust anchor. Messages are encrypted at
rest (Cloak/AES-256) and in transit (TLS). MLS (OpenMLS) provides forward
secrecy and post-compromise security. In the current LiveView architecture
the server decrypts messages for rendering — the server operator can read
message content in principle. Full client-side decryption is a future
milestone requiring native clients.

**Components**:
- Server-side MLS via OpenMLS (ADR 010); server performs decryption in
  current architecture
- Monorepo placement for MLS adapter: `backend/infra/mls_nif` (top-level
  `/native` stays reserved for future native app clients)
- Field-level (Cloak.Ecto for sensitive data)
- Database encryption at rest

**See**:
- [ENCRYPTION.md](ENCRYPTION.md)
- [decisions/010-mls-first-for-neighborhood-scale.md](decisions/010-mls-first-for-neighborhood-scale.md)

---

#### 4. Conversation Security State Ownership Boundary
**Decision**: Durable conversation security state is owned by `Famichat.Chat`; crypto modules are adapter-only.

**Rationale**:
- Keeps persistence ownership in the chat domain where message orchestration lives
- Avoids leaking database ownership into NIF/crypto adapter layers
- Preserves one canonical backend path for API, CLI, LiveView, and agent-driven testing

**Current Durable Shape**:
- Dedicated table: `conversation_security_states`
- Chat-owned schema/store boundary modules:
  - `Famichat.Chat.ConversationSecurityState`
  - `Famichat.Chat.ConversationSecurityStateStore`
- Chat-owned policy boundary module:
  - `Famichat.Chat.ConversationSecurityPolicy` (requirement-decision policy; protocol remains implementation data)
  - `Famichat.Chat.ConversationSecurityKeyPackagePolicy` (current client-inventory lifecycle policy implementation; planned rename target: `Famichat.Chat.ConversationSecurityClientInventoryPolicy`)
- Protocol remains a data attribute (current default: MLS), not a storage/module naming prefix

**Compatibility Read Path**:
- Legacy encrypted envelope in `conversations.metadata.mls.session_snapshot_encrypted` is still read for migration and converted into the dedicated store on access

**See**:
- [ia-lexicon.md](ia-lexicon.md)
- [ia-boundary-guardrails.md](ia-boundary-guardrails.md)
- [sprints/STATUS.md](sprints/STATUS.md)

---

### Database Schema

**Current Migrations**: See `backend/priv/repo/migrations` (active schema evolution; avoid fixed-count drift in this doc)

**Core Tables**:
- `users` - Account records (encrypted email, status, timestamps)
- `family_memberships` - User ↔ family join table with role tracking (admin/member)
- `families` - Household grouping
- `conversations` - Multi-type conversations (direct, self, group, family)
- `messages` - Message content with metadata
- `conversation_participants` - Join table (users ↔ conversations)
- `group_conversation_privileges` - Group admin/member privileges per conversation
- `user_tokens` - Context-scoped hashed tokens (invite, magic link, pairing, etc.)
- `user_devices` - Device trust + refresh token rotation (30 day window)
- `passkeys` - Stored WebAuthn credentials (registration/assertion wired through Wax challenge exchange); server only accepts attestation/assertion requests tied to signed challenge records (no direct credential registration)

**Key Fields / Notes**:
- `users.email` uses `EncryptedBinary` (Cloak) with deterministic `email_fingerprint` for uniqueness
- `conversations.direct_key` - SHA256 hash for deduplication
- `conversations.hidden_by_users` - Array of user IDs (soft delete)
- `messages.metadata` - JSONB for encryption metadata and MLS delivery context
- `conversation_security_states` - Durable encrypted conversation security state with optimistic `lock_version`
- `conversations.metadata.mls.session_snapshot_encrypted` - Compatibility-only legacy read path for migration
- Accounts refactor delivered (passkey-first onboarding, single token model). Legacy `users.family_id/role` columns removed in follow-up migration.

---

### Real-Time Communication

**Phoenix Channels**:
- Topic format: `message:<type>:<conversation_id>`
- Access tokens issued by `Famichat.Auth.Sessions.start_session/3` (with policy-aware `:remember` option) verified in `UserSocket.connect/3`
- Tests green (join/broadcast/ack telemetry enforced)
- Performance budget: 200ms
- Telemetry on all operations (join/broadcast/ack spans, encryption metadata scrubbed)

**Implementation**: [backend/lib/famichat_web/channels/message_channel.ex](../backend/lib/famichat_web/channels/message_channel.ex)

---

## Frontend Architecture (Phoenix LiveView)

**Status**: In progress (40% complete)

**Current**:
- LiveView setup and configuration ✅
- Test LiveView pages ✅
- LiveView Hooks for channel integration ✅
- Theme switching components ✅
- Core component library ✅

**In Progress** (Sprint 8):
- Authentication UI (login/registration)
- Messaging interface (conversation list, message view)
- Real-time channel integration via LiveView Hooks

**Note**: Native mobile app (Flutter/iOS/Android) deferred until Layer 4 (Autonomy & Safety features). Current focus is dogfooding with LiveView for Layers 0-3.

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

**Current** (Sprint 9 hardening track):
- Token-based channel authentication ✅
- Family-based authorization ✅
- OpenMLS-backed encryption/decryption vertical slice ✅
- Fail-closed runtime gating for MLS operations ✅
- ⚠️ Durable MLS lifecycle/state-store hardening still in progress

**Planned** (Sprint 9 - 3 weeks):
- Server-side MLS E2EE (Rust NIF + OpenMLS)
- MLS key package lifecycle + group state/epoch management
- Dedicated durable conversation security state store with optimistic locking
- Trust model: Self-hosted backend = you control the server; MLS provides
  forward secrecy and post-compromise security; server decrypts for
  LiveView rendering in current architecture (see Trust Model in VISION.md)

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
LiveView captures message (10ms)
  → Server encrypts via MLS NIF path (steady-state app-message target <=50ms)
  → Store encrypted in database (10ms)
  → Broadcast to recipients (20ms)
  → Network send (50ms)
  → Recipient LiveView receives (10ms)
  → Server decrypts via MLS NIF path (steady-state app-message target <=30ms)
  → LiveView renders (10ms)

= target <=200ms for steady-state app-message flow; commit/update/remove paths tracked with separate SLOs
```

**Architectural Implications**:
1. **Optimistic UI**: Display immediately, sync asynchronously
2. **Binary Protocol**: Avoid JSON serialization overhead (10-20ms saved)
3. **Persistent WebSockets**: Eliminate connection handshake from critical path
4. **Self-Hosted Deployment**: Neighborhood-local server = 1-30ms network latency (vs 50-150ms cloud)
5. **Encryption Protocol Constraint**: MLS app-message path can be efficient, but commit/update/remove latency is sensitive to churn and tree health; enforce guardrails + telemetry by default

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
2. **Privacy**: Self-hosted operator controls infrastructure; MLS provides
   forward secrecy and post-compromise security; server decrypts for
   LiveView rendering in current architecture
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

**Last Updated**: 2026-02-25
