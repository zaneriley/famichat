# Famichat Roadmap

**Last Updated**: 2026-02-25

## Progress Overview

**Overall**: ████████░░░░░░░░░░░░ 40% to MVP

---

## ✅ Completed Sprints

### Sprint 1-2: Foundation & Basic Messaging (Jan 2025) ✓
**Outcome**: Developers can spin up the application and send basic text messages

**Deliverables**:
- ✅ Docker environment with Phoenix & Postgres
- ✅ "Hello World" Phoenix page
- ✅ Message schema & migration
- ✅ `send_message/3` function in MessageService
- ✅ Basic message validation (sender_id, conversation_id, content)
- ✅ Unit tests for message sending

**Key Files**:
- [Message schema](../../backend/lib/famichat/chat/message.ex)
- [MessageService](../../backend/lib/famichat/chat/message_service.ex)

---

### Sprint 3: Direct Conversation Creation (Jan 2025) ✓
**Outcome**: Users can create direct conversations with family-membership validation

**Deliverables**:
- ✅ Conversation schema & migration
- ✅ conversation_users join table (now conversation_participants)
- ✅ `create_direct_conversation/2` in ConversationService
- ✅ Duplicate conversation handling (via direct_key)
- ✅ Family membership validation (shared family required)
- ✅ Unit tests for conversation creation

**Key Features**:
- Direct conversation deduplication (SHA256 direct_key)
- Transaction-based creation
- Business rule: users must share a family

**Key Files**:
- [Conversation schema](../../backend/lib/famichat/chat/conversation.ex)
- [ConversationService](../../backend/lib/famichat/chat/conversation_service.ex)

---

### Sprint 4: Message Retrieval & Conversation Listing (Feb 2025) ✓
**Outcome**: API can retrieve messages and list user conversations

**Deliverables**:
- ✅ `get_conversation_messages/2` with pagination
- ✅ Messages ordered chronologically
- ✅ `list_user_conversations/1` for user's direct conversations
- ✅ Preloading of associations (users, participants)
- ✅ Unit tests for all scenarios (success, empty, not found)

**Key Features**:
- Pagination support (limit/offset, max 100 per page)
- Distinct conversation results
- Proper error handling

**Key Files**:
- [MessageService](../../backend/lib/famichat/chat/message_service.ex) (lines 40-100)
- [ConversationService](../../backend/lib/famichat/chat/conversation_service.ex) (lines 263-290)

---

### Sprint 5: Self-Messaging Support (Feb 2025) ✓
**Outcome**: Users can send messages to themselves (personal notepad)

**Deliverables**:
- ✅ Conversation type `:self` in schema
- ✅ `create_self_conversation/1` function
- ✅ Self-message validation (exactly 1 participant)
- ✅ Separate listing for self-conversations
- ✅ Unit tests for self-messaging

**Key Features**:
- Self-conversations for note-taking
- Clear separation from direct conversations
- Type-specific validation

**Key Files**:
- [Conversation schema](../../backend/lib/famichat/chat/conversation.ex) (type field)
- [ConversationService](../../backend/lib/famichat/chat/conversation_service.ex) (self-conversation functions)

---

### Sprint 6: Telemetry Instrumentation & Encryption Foundation (Mar 2025) ✓
**Outcome**: Performance monitoring infrastructure & encryption hooks ready

**Deliverables**:
- ✅ `:telemetry.span/3` wrapping for critical operations
- ✅ Performance budget tracking (200ms default)
- ✅ Event naming convention: `[:famichat, :context, :action]`
- ✅ Sensitive data filtering (encryption metadata)
- ✅ Encryption message serialization/deserialization hooks
- ✅ `requires_encryption?/1` policy function
- ✅ Telemetry documentation

**Key Features**:
- All service operations instrumented
- Encryption infrastructure ready (no crypto yet)
- Performance budget violations logged

**Key Files**:
- [Telemetry Guide](../../backend/guides/telemetry.md)
- [MessageService](../../backend/lib/famichat/chat/message_service.ex) (serialization functions)

---

## 🚧 Current Sprint

### Sprint 7: Real-Time Messaging Integration (Oct 2025) - Closeout
📍 **See [CURRENT-SPRINT.md](CURRENT-SPRINT.md) for detailed tasks**

**Duration**: Oct 1 - Oct 15, 2025
**Status**: 🟡 Implementation landing is on track; repo-wide lint/static debt follow-through remains

**Goal**: Integrate real-time messaging via Phoenix Channels with encryption-aware infrastructure

**Completed**:
- ✅ Phoenix Channel module with token auth
- ✅ Type-immutable conversation schema
- ✅ Conversation hiding/unhiding functionality
- ✅ Comprehensive channel tests (42KB test file!)
- ✅ Encryption telemetry validation (Story 7.1.4)
- ✅ Accounts context refactor (Story 7.9) — passkey-first onboarding, device trust, single token model
- ✅ Username fingerprint migration + single-use invite acceptance (registration JWT handshake)

**In Progress**:
- 🔄 Group role management edge case tests
- 🔄 Story 7.4.2 secure CLI broadcast endpoint follow-through (implementation landed; repo-wide gate debt cleanup pending)
- 🔄 Story 7.2/7.3 final verification, runbook, and documentation consolidation

**Not Started**:
- ❌ Story 7.4.1 dummy UI route / LiveView test harness

**Key Deliverables**:
- Phoenix Channels configured ✓
- Channel authorization ✓ (implemented; regression coverage follow-through ongoing)
- Encryption telemetry assertions ✓ (Story 7.1.4 complete)
- **Accounts context** ✅ shipped (Story 7.9)

**Blockers**:
1. Auth client integration docs outstanding (Story 7.3)
2. Test coverage not measured

**Key Files**:
- [MessageChannel](../../backend/lib/famichat_web/channels/message_channel.ex)
- [Channel Tests](../../backend/test/famichat_web/channels/message_channel_test.exs)

---

## 📅 Upcoming Sprints

### Sprint 8: LiveView Messaging UI & Authentication (Planned)
**Goal**: Build functional LiveView messaging interface with authentication

**Key Deliverables**:
- LiveView messaging UI (conversation list, message view)
- LiveView Hooks for real-time channel integration
- Session management and authentication UX wiring on top of shipped Accounts APIs
- User registration/login pages backed by the existing Accounts context
- Integration tests (LiveView ↔ channels)
- One canonical end-to-end operator runbook and verification flow (`auth -> subscribe -> send -> receive`)

**Dependencies**:
- Sprint 7 closeout (runbook/docs consolidation + role edge-case test follow-through)
- Story 7.9 follow-up HTTP/LiveView surfacing work (core Accounts context already shipped)

**Estimated Duration**: 2 weeks
**Priority**: **HIGH** - needed to demonstrate product value and enable dogfooding

**Outcome**: End-to-end messaging demo via web browser with authentication (login → send message → see real-time updates)

---

### Sprint 9: MLS E2EE Implementation (Planned)
**Goal**: Implement server-side MLS encryption via Rust NIF (OpenMLS)
**Contract Reference**: [9.0-mls-rust-nif-contract-deep-dive.md](9.0-mls-rust-nif-contract-deep-dive.md)
**TDD Plan Reference**: [9.1-mls-contract-tdd-plan.md](9.1-mls-contract-tdd-plan.md)
**Monorepo Placement**: backend infrastructure adapter at `backend/infra/mls_nif` (`/native` reserved for future app clients)

**Key Deliverables**:
- **Week 1-2**: Rust NIF Setup
  - Add Rustler + OpenMLS dependency set
  - Create backend-scoped NIF crate at `backend/infra/mls_nif`
  - Multi-stage Docker build (Rust toolchain)
  - Elixir NIF wrapper for MLS operations
  - Basic encryption/decryption tests
- **Week 2-3**: Key Management
  - MLS key package + credential lifecycle implementation
  - Database schema for MLS group state, epochs, and message metadata
  - User registration: Generate identity keys
  - Cloak.Ecto vault for key encryption at rest
- **Week 3**: Message Encryption Integration
  - Wire `send_message/1` to encrypt via NIF before storing
  - Wire `get_conversation_messages/2` to decrypt after retrieval
  - Update LiveView to render decrypted content
  - Integration tests (encrypted message flow)

**Dependencies**:
- Sprint 8 (LiveView UI + authentication must exist)
- Crypto library: OpenMLS (Rust) via Rustler NIF (ADR 010)

**Estimated Duration**: 3 weeks
**Priority**: **CRITICAL** - Must dogfood with encryption from day 1

**Outcome**: Messages encrypted/decrypted server-side using MLS. Ready for Layer 0 dogfooding.

**Current State**:
- ✅ Encryption metadata infrastructure exists (serialization, telemetry)
- ❌ No actual cryptographic implementation yet (messages stored in plaintext)

---

### Sprint 10: Layer 0 Dogfooding & Design System (Planned)
**Goal**: Validate encrypted messaging + add white-label theming

**Key Deliverables**:
- **Layer 0 Validation** (you, solo, 1 week):
  - Send encrypted messages to self
  - Verify encryption performance (<200ms)
  - Test self-hosted deployment
  - Document issues/UX friction
- **Design System** (1 week):
  - Tailwind CSS design tokens (colors, fonts, spacing)
  - Theme switching in LiveView components
  - Basic white-label customization (logo, family name)
  - Theme configuration tests

**Dependencies**:
- Sprint 9 (MLS E2EE must be working)
- Sprint 8 (LiveView UI + authentication)

**Estimated Duration**: 2 weeks
**Priority**: **HIGH** - First real dogfooding with encryption

**Outcome**:
- Validated encrypted messaging works end-to-end
- Families can customize app appearance
- Ready for Layer 1 (you + wife)

---

### Sprint 11: Code Quality & Documentation Refinement (Planned)
**Goal**: All modules refined, tests pass, documentation complete

**Key Deliverables**:
- Fix any remaining failing tests
- Enhanced error handling with structured logging
- Refactor inline documentation (@doc annotations)
- Update unified documentation
- Code review and acceptance criteria validation
- Test coverage ≥ 80%

**Dependencies**:
- All previous sprints complete

**Estimated Duration**: 1 week
**Priority**: MEDIUM

**Outcome**: Production-ready code quality

---

### Sprint 12: Onboarding & End-to-End Testing (Planned)
**Goal**: Polished onboarding workflow and complete system testing

**Key Deliverables**:
- Onboarding screen design (LiveView)
- Account creation flow refinement
- Profile setup (avatar, name, family)
- User testing feedback collection
- End-to-end system tests (Docker → backend → LiveView)

**Dependencies**:
- Sprint 8 (LiveView UI)
- Sprint 10 (design system)

**Note**: "Phone bump" detection (Nearby Interaction) deferred to native app (Layer 4+)

**Estimated Duration**: 1 week
**Priority**: MEDIUM

**Outcome**: Smooth user onboarding experience

---

### Sprint 13: Final Polish & Release Readiness (Planned)
**Goal**: Product stabilized, monitored, and fully documented for production

**Key Deliverables**:
- Comprehensive end-to-end tests
- Production Docker configuration
- HTTPS/TLS setup
- Monitoring integration (Prometheus/Grafana)
- Error tracking (Sentry or Rollbar)
- Database backup strategy
- Final change log and release notes
- Team code review and sign-off

**Dependencies**:
- All previous sprints complete

**Estimated Duration**: 1 week
**Priority**: **HIGH** - required for production deployment

**Outcome**: Production-ready deployment

---

## 🎯 Milestones

### MVP (Minimum Viable Product)
**Target**: After Sprint 13
**Status**: 40% complete

**Must-Have Features**:
- ✅ Text messaging (send/retrieve)
- ✅ Conversations (direct, self, group)
- ✅ Real-time updates (channels)
- ✅ Encryption metadata infrastructure (serialization, telemetry)
- ✅ User authentication foundation (Story 7.9 shipped; UX integration follow-through continues)
- 🔄 LiveView UI (messaging interface in progress)
- ❌ E2E encryption (MLS/OpenMLS - Sprint 9)
- ❌ Production deployment

**Definition of MVP**:
- User can register/login
- User can send/receive text messages in real-time
- User can create direct conversations
- User can message themselves (notes)
- Messages are encrypted end-to-end
- App can be deployed to production
- Basic onboarding flow works

**Estimated Completion**: Sprint 13 (if all sprints go as planned)

---

### Alpha Release
**Target**: TBD (after MVP + initial testing)
**Status**: Not yet planned

**Additional Features Needed**:
- User authentication working ✅ (from MVP)
- Basic error handling & logging
- Limited user testing (internal team + close friends/family)
- Known bugs documented
- No production support yet

---

### Beta Release
**Target**: TBD (after Alpha + improvements)
**Status**: Not yet planned

**Additional Features Needed**:
- Media uploads (photos, videos)
- Message status tracking (delivered, read)
- Push notifications
- Wider user testing (multiple families)
- Production monitoring active
- Bug fixes from Alpha

---

## 📊 Sprint Velocity & Metrics

### Historical Velocity
- **Sprint 1-2**: 5 stories completed (combined sprint)
- **Sprint 3**: 5 stories completed
- **Sprint 4**: 5 stories completed
- **Sprint 5**: 5 stories completed
- **Sprint 6**: 5 stories completed
- **Sprint 7**: closeout in progress (core channel/auth/7.4.2 and 7.9 complete; docs and verification follow-through open)

**Average Velocity**: ~5 stories per sprint (1 point each)

### Quality Metrics
- **Test Coverage**: Unknown (run `mix coveralls` post-Accounts refactor)
- **Tests Passing**: ✅ 155/155 (Accounts + channel suites green)
- **Security**: No new vulnerabilities (Sobelow) ✅
- **Performance**: All ops under 200ms budget ✅

---

## 🚨 Risks & Dependencies

### High-Risk Items
1. **Authentication Refactor Follow-ups** (Story 7.9)
   - **Impact**: Legacy columns removal + HTTP endpoints still pending, but core flows green
   - **Mitigation**: Ship cleanup migration, surface invite/magic/OTP endpoints, monitor regression tests

2. **Encryption Complexity**
   - **Impact**: May take longer than 3 weeks (moved to Sprint 9, extended from 2 to 3 weeks)
   - **Mitigation**: MLS-first direction accepted (ADR 010) with performance guardrails + dependency update discipline
   - **Current State**: Encryption metadata infrastructure ready, but no crypto implementation yet

3. **Native App Decision Point**
   - **Impact**: Layer 4 (Autonomy & Safety) may require native mobile app
   - **Mitigation**: Defer until Layer 3 validates LiveView UX (Sprints 8-10)

### Dependencies
- **Sprint 8 depends on**: Sprint 7 closeout (operator runbook + docs + targeted role-edge coverage)
- **Sprint 9 depends on**: Sprint 8 completion (authentication + LiveView UI)
- **Sprint 10 depends on**: Sprint 9 completion (E2EE must work for dogfooding)
- **Sprint 13 depends on**: All previous sprints (production readiness)

---

## 🔗 Related Documentation

- **Current Status**: See [STATUS.md](STATUS.md) for comprehensive implementation status
- **Current Sprint**: See [CURRENT-SPRINT.md](CURRENT-SPRINT.md) for Sprint 7 details
- **Architecture**: See [../ARCHITECTURE.md](../ARCHITECTURE.md) for system design
- **Encryption Direction**: See [../decisions/010-mls-first-for-neighborhood-scale.md](../decisions/010-mls-first-for-neighborhood-scale.md)
- **Vision**: See [../VISION.md](../VISION.md) for product goals

---

## 📝 Change Log

### 2026-02-25
- Updated E2EE direction from Signal-first to MLS-first (ADR 010)
- Reframed Sprint 9 deliverables around OpenMLS integration and MLS state lifecycle
- Updated Sprint 10 dependency wording to require MLS readiness

### 2025-10-05
- Updated Sprint 7 status (30% complete)
- Identified critical blocker (Story 7.9 - Accounts context)
- Created comprehensive roadmap document

### 2025-03-15
- Completed Sprint 6 (Telemetry & Encryption Foundation)
- Began Sprint 7 (Real-Time Messaging Integration)

### 2025-02-28
- Completed Sprint 5 (Self-Messaging Support)

### 2025-02-15
- Completed Sprint 4 (Message Retrieval & Conversation Listing)

### 2025-01-31
- Completed Sprint 3 (Direct Conversation Creation)

### 2025-01-15
- Completed Sprint 1-2 (Foundation & Basic Messaging)

---

**Last Updated**: 2026-02-25
**Next Review**: 2026-03-04
**Sprint Cadence**: 2 weeks per sprint
