# Famichat Roadmap

**Last Updated**: 2025-10-05

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
- [Message schema](backend/lib/famichat/chat/message.ex)
- [MessageService](backend/lib/famichat/chat/message_service.ex)

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
- [Conversation schema](backend/lib/famichat/chat/conversation.ex)
- [ConversationService](backend/lib/famichat/chat/conversation_service.ex)

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
- [MessageService](backend/lib/famichat/chat/message_service.ex) (lines 40-100)
- [ConversationService](backend/lib/famichat/chat/conversation_service.ex) (lines 263-290)

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
- [Conversation schema](backend/lib/famichat/chat/conversation.ex) (type field)
- [ConversationService](backend/lib/famichat/chat/conversation_service.ex) (self-conversation functions)

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
- [Telemetry Guide](backend/guides/telemetry.md)
- [MessageService](backend/lib/famichat/chat/message_service.ex) (serialization functions)

---

## 🚧 Current Sprint

### Sprint 7: Real-Time Messaging Integration (Oct 2025) - 30%
📍 **See [CURRENT-SPRINT.md](CURRENT-SPRINT.md) for detailed tasks**

**Duration**: Oct 1 - Oct 15, 2025
**Status**: 🟡 On track with blockers

**Goal**: Integrate real-time messaging via Phoenix Channels with encryption-aware infrastructure

**Completed**:
- ✅ Phoenix Channel module with token auth
- ✅ Type-immutable conversation schema
- ✅ Conversation hiding/unhiding functionality
- ✅ Comprehensive channel tests (42KB test file!)

**In Progress**:
- 🔄 Channel routing & authorization (80%)
- 🔄 Encryption telemetry validation
- 🔄 Group role management edge case tests

**Not Started**:
- ❌ Broadcast testing (Story 7.2)
- ❌ Client integration documentation (Story 7.3)
- 🚨 **Accounts context (Story 7.9) - CRITICAL BLOCKER!**

**Key Deliverables**:
- Phoenix Channels configured ✓
- Channel authorization ⚠️ (needs testing)
- Encryption-aware serialization ⚠️ (needs tests)
- **Accounts context** ❌ (MUST START!)

**Blockers**:
1. Story 7.9 (Accounts) not started - blocks all auth work
2. Auth flow design decision needed (ADR required)
3. Test coverage not measured

**Key Files**:
- [MessageChannel](backend/lib/famichat_web/channels/message_channel.ex)
- [Channel Tests](backend/test/famichat_web/channels/message_channel_test.exs)

---

## 📅 Upcoming Sprints

### Sprint 8: Flutter Client - Messaging UI (Planned)
**Goal**: Build functional Flutter client with WebSocket integration

**Key Deliverables**:
- WebSocket client integration (phoenix_socket package)
- Basic messaging UI (conversation list, message view)
- State management (Provider or Bloc)
- Local storage for offline support
- Integration tests (client ↔ backend)

**Dependencies**:
- Sprint 7 must complete (channel authorization)
- Story 7.9 (Accounts) must be done (for auth)
- Client integration docs from Sprint 7.3

**Estimated Duration**: 2 weeks
**Priority**: **HIGH** - needed to demonstrate product value

**Outcome**: End-to-end messaging demo (send message in Flutter → see it in real-time)

---

### Sprint 9: Design System & White-Label Preparation (Planned)
**Goal**: Families can customize interface with themes and branding

**Key Deliverables**:
- Design tokens integration (colors, fonts, spacing)
- Theme switching support in Flutter
- Backend endpoint for theme configuration
- White-label customization options (logo, family name)
- Theme configuration tests

**Dependencies**:
- Sprint 8 (Flutter client must exist)

**Estimated Duration**: 1 week
**Priority**: MEDIUM

**Outcome**: Families can customize app appearance

---

### Sprint 10: E2EE Implementation (Planned)
**Goal**: Full Signal Protocol implementation with X3DH/Double Ratchet

**Key Deliverables**:
- X3DH key exchange protocol
- Double Ratchet message encryption/decryption
- Key rotation system
- Encrypted message payload handling
- Key recovery/backup mechanism
- Encryption tests (positive & negative scenarios)

**Dependencies**:
- Sprint 8 (client must support encryption)
- Crypto library selection (libsignal or pure Elixir?)

**Estimated Duration**: 2 weeks
**Priority**: **HIGH** - core security feature

**Outcome**: Messages are end-to-end encrypted using Signal Protocol

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
- Onboarding screen design (iOS and Flutter)
- Account creation flow implementation
- Profile setup (avatar, name, family)
- Experimental "phone bump" detection (Nearby Interaction)
- User testing feedback collection
- End-to-end system tests (Docker → backend → Flutter)

**Dependencies**:
- Sprint 8 (Flutter client)
- Sprint 9 (design system)

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
- 🔄 User authentication (in progress - Story 7.9)
- ❌ Flutter client (basic UI)
- ❌ E2E encryption
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
- **Sprint 7**: 4/9 stories completed (in progress)

**Average Velocity**: ~5 stories per sprint (1 point each)

### Quality Metrics
- **Test Coverage**: Unknown (need to measure)
- **Tests Passing**: 98/98 ✅
- **Security**: No vulnerabilities (Sobelow) ✅
- **Performance**: All ops under 200ms budget ✅

---

## 🚨 Risks & Dependencies

### High-Risk Items
1. **Authentication Missing** (Story 7.9)
   - **Impact**: Blocks Sprint 8 (Flutter client needs auth)
   - **Mitigation**: Must start immediately, prioritize this week

2. **Flutter Client Behind Schedule**
   - **Impact**: Cannot demonstrate product value
   - **Mitigation**: Dedicate full sprint to client (Sprint 8)

3. **Encryption Complexity**
   - **Impact**: May take longer than 1 sprint
   - **Mitigation**: Consider using existing library (libsignal) vs building from scratch

### Dependencies
- **Sprint 8 depends on**: Sprint 7 completion (especially Story 7.9 auth)
- **Sprint 10 depends on**: Sprint 8 completion (client must support encryption)
- **Sprint 13 depends on**: All previous sprints (production readiness)

---

## 🔗 Related Documentation

- **Current Status**: See [STATUS.md](STATUS.md) for comprehensive implementation status
- **Current Sprint**: See [CURRENT-SPRINT.md](CURRENT-SPRINT.md) for Sprint 7 details
- **Architecture**: See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for system design
- **Vision**: See [docs/VISION.md](docs/VISION.md) for product goals

---

## 📝 Change Log

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

**Last Updated**: 2025-10-05
**Next Review**: 2025-10-08
**Sprint Cadence**: 2 weeks per sprint
