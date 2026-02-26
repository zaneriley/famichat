# Famichat - Comprehensive Status Report

**Last Updated**: 2026-02-26
**Sprint**: 9 (MLS E2EE Implementation)
**Overall Progress**: 40% to MVP

Terminology authority: [../ia-lexicon.md](../ia-lexicon.md)
Boundary guardrails: [../ia-boundary-guardrails.md](../ia-boundary-guardrails.md)
Sprint 9 P0 done-state checklist: [9.3-mls-definition-of-done.md](9.3-mls-definition-of-done.md)

---

## 📊 Executive Summary

### Health Indicators
- 🟢 **Backend Core**: 75% complete - Messaging solid, Accounts passkey/session flows green ✅, and OpenMLS-backed NIF vertical slice now working in tests
- 🟡 **Frontend (LiveView)**: 40% complete - Messaging UI in progress
- 🟡 **Infrastructure**: 50% complete - Dev ready, prod missing
- 🟡 **Documentation**: 80% complete - Architecture/roadmap refreshed for Accounts changes

### Priority Lens (Current)
- **P0**: Backend MLS/E2EE correctness + fail-closed guarantees + operational gates
- **P1**: LiveView messaging UX on top of the same backend/channel contracts

### Critical Blockers
1. 🚨 **MLS Not Yet Production-Hard** - crypto vertical slice exists, but durability/lifecycle hardening is incomplete
   - ✅ OpenMLS-backed NIF integration is active for core `create_group -> encrypt -> process_incoming`
   - ✅ MessageService fail-closed runtime health gating is implemented
   - ✅ NIF session snapshot export/restore contract is implemented (runtime state blobs)
   - ✅ Dedicated conversation security state persistence is active in `conversation_security_states` via `Famichat.Chat.ConversationSecurityStateStore`
   - ✅ Legacy metadata envelopes are read for compatibility and migrated into the dedicated store on access
   - ✅ Replay-idempotency cache export is now bounded (max 256 entries)
   - ✅ Adversarial contract tests now cover malformed ciphertext, cross-group misuse, replay rejection, out-of-order lifecycle sequencing, tampered pending metadata, epoch regression attempts, partial snapshot payload tampering, and concurrent stage/merge race outcomes
   - ✅ Optimistic lock-version conflict handling is active (`:stale_state` mapped fail-closed to `:storage_inconsistent`)
   - ✅ Lifecycle orchestrator exists (`ConversationSecurityLifecycle`: stage/merge/clear pending commit with optimistic locking)
   - ✅ Send path now fails closed while pending commits are unresolved (`:pending_proposals`)
   - ✅ Durable client inventory policy is active in `conversation_security_client_inventories` via `Famichat.Chat.ConversationSecurityClientInventoryStore` + `Famichat.Chat.ConversationSecurityClientInventoryPolicy` (create/consume/replenish threshold; canonical boundary naming is in use during implementation rename)
   - ✅ Client inventory rotation policy is active (trigger-based stale rotation + scheduled batch rotation API)
   - ✅ Key-lifecycle telemetry for client inventory operations is active with aggregate-only metadata
   - ⚠️ Commit/update/add/remove lifecycle hardening on top of dedicated state storage remains incomplete (deeper payload/epoch semantics)
   - ⚠️ Remaining key lifecycle hardening (rejoin persistence + revocation strategy) is not complete
2. ⚠️ **Operational Confidence Gaps** - quality visibility is incomplete
   - Live messaging QA is now productized with first-class commands and artifacted matrix output:
     - `cd backend && ./run qa:messaging:preflight`
     - `cd backend && ./run qa:messaging:fast`
     - `cd backend && ./run qa:messaging:deep`
     - artifacts: `.tmp/_qa_messaging/<RUN_ID>/`
   - Canonical-flow coverage capture is now available via deep loop artifact (`canonical_flow_coverage.txt`)
   - Repo-wide lint/static baseline debt is still unresolved
   - Canonical flow timing is now captured per run (`canonical_flow_timing.txt`)
   - Remaining gap: CI required-check wiring (PR fast loop + nightly deep loop)

---

## ✅ Implementation Status

### Core Backend (60% Complete)

#### Messaging System ✅ DONE
**Location**: `backend/lib/famichat/chat/message_service.ex`

**Implemented Features**:
- ✅ **send_message/1** - Pipeline-based message creation ([line 146](../../backend/lib/famichat/chat/message_service.ex#L146))
  - Validates sender/conversation existence
  - Processes encryption metadata
  - Persists to database
  - Emits telemetry events
  - **Tests**: [message_service_test.exs](../../backend/test/famichat/chat/message_service_test.exs) ✓ Passing

- ✅ **get_conversation_messages/2** - Paginated retrieval ([line 40](../../backend/lib/famichat/chat/message_service.ex#L40))
  - Supports limit (max 100) and offset
  - Ordered by insertion time (chronological)
  - Preloads sender & conversation associations
  - **Tests**: ✓ All scenarios covered (success, empty, not found)

- ✅ **Encryption + MLS Integration** (Vertical Slice Working, Hardening Ongoing)
  - `serialize_message/1` ([line 283](../../backend/lib/famichat/chat/message_service.ex#L283)) - Stores encryption metadata in message.metadata field
  - `deserialize_message/1` ([line 408](../../backend/lib/famichat/chat/message_service.ex#L408)) - Extracts encryption data
  - `encrypt_with_mls_if_required/1` ([line 546](../../backend/lib/famichat/chat/message_service.ex#L546)) - Calls MLS adapter and stores ciphertext when required
  - `decrypt_messages_if_required/1` ([line 596](../../backend/lib/famichat/chat/message_service.ex#L596)) - Decrypts via MLS adapter when required
  - `ensure_mls_runtime_ready/0` ([line 733](../../backend/lib/famichat/chat/message_service.ex#L733)) - Fail-closed runtime health gate
  - MLS conversation security state persists in dedicated `conversation_security_states` storage with optimistic locking
  - Legacy metadata envelope is compatibility-read only and migrates to dedicated storage on access
  - Pending commit lifecycle orchestration is implemented in `ConversationSecurityLifecycle` and enforced on send-path app messages
  - Stage/merge paths now reject tampered lifecycle payloads (invalid operation, stale/regressive epochs, or partial snapshot fragments) with explicit fail-closed errors
  - Replay-idempotency cache is capped to reduce state growth pressure
  - `requires_encryption?/1` ([line 266](../../backend/lib/famichat/chat/message_service.ex#L266)) - Compatibility API for conversation security policy decisions
  - **Tests**:
    - [message_service_mls_contract_test.exs](../../backend/test/famichat/chat/message_service_mls_contract_test.exs)
    - [nif_adapter_test.exs](../../backend/test/famichat/crypto/mls/nif_adapter_test.exs)
    - [telemetry_contract_test.exs](../../backend/test/famichat/crypto/mls/telemetry_contract_test.exs)
  - **Status**: ✅ Real OpenMLS vertical slice implemented, ⚠️ production durability/lifecycle work still pending

**Evidence**:
```bash
cd backend && ./run mix test test/famichat/chat/message_service_test.exs
# Result: All tests passing ✓
```

**Message Schema**:
- Types supported: `:text`, `:voice`, `:video`, `:image`, `:file`, `:poke`, `:reaction`, `:gif`
- Statuses: `:sent` (implemented), `:delivered` (not implemented), `:read` (not implemented)
- Encryption metadata stored in JSONB `metadata` field

---

#### Conversation System ✅ MOSTLY DONE
**Location**: `backend/lib/famichat/chat/conversation_service.ex`

**Direct Conversations** ✅:
- ✅ **create_direct_conversation/2** ([line 123](../../backend/lib/famichat/chat/conversation_service.ex#L123))
  - Validates both users exist and share same family
  - Computes unique `direct_key` using SHA256(sorted_user_ids + family_id + salt)
  - Transaction-based with conflict prevention
  - Returns existing conversation if found (deduplication)
  - Full telemetry instrumentation
  - **Tests**: [conversation_service_test.exs](../../backend/test/famichat/chat/conversation_service_test.exs) ✓ 18KB of tests

- ✅ **list_user_conversations/1** ([line 263](../../backend/lib/famichat/chat/conversation_service.ex#L263))
  - Returns all direct conversations for a user
  - Preloads participant users
  - Distinct results (no duplicates)
  - **Tests**: ✓ Covers users with/without conversations

**Self Conversations** ✅:
- ✅ Fully implemented (mentioned in done.md, verified in code)
- Users can message themselves for note-taking
- Separate listing function available

**Group Conversations** ✅:
- ✅ **create_group_conversation/4** ([line 318](../../backend/lib/famichat/chat/conversation_service.ex#L318))
  - Auto-assigns creator as admin
  - Validates family membership
  - Requires group name in metadata
  - Uses transactions for atomicity

- ✅ **Role Management**:
  - `assign_admin/3` ([line 397](../../backend/lib/famichat/chat/conversation_service.ex#L397))
  - `assign_member/3` ([line 465](../../backend/lib/famichat/chat/conversation_service.ex#L465)) - Prevents last admin removal
  - `remove_privilege/3` ([line 631](../../backend/lib/famichat/chat/conversation_service.ex#L631))
  - `admin?/2` ([line 570](../../backend/lib/famichat/chat/conversation_service.ex#L570)) - Check admin status
  - **Schema**: [group_conversation_privileges.ex](../../backend/lib/famichat/chat/group_conversation_privileges.ex)
  - **Tests**: [group_conversation_privileges_test.exs](../../backend/test/famichat/chat/group_conversation_privileges_test.exs) ✓

**Family Conversations** ⚠️:
- ⚠️ Type defined in schema but no creation function
- Conversation type `:family` exists but not implemented

**Visibility Management** ✅:
- ✅ **hide_conversation/2** - Add user to hidden_by_users array
- ✅ **unhide_conversation/2** - Remove user from hidden_by_users array
- ✅ **list_visible_conversations/2** - Filter out hidden conversations
- **Service**: [conversation_visibility_service.ex](../../backend/lib/famichat/chat/conversation_visibility_service.ex)
- **Tests**: [conversation_visibility_service_test.exs](../../backend/test/famichat/chat/conversation_visibility_service_test.exs) ✓

---

#### Real-Time Channels ✅ IMPLEMENTED
**Location**: `backend/lib/famichat_web/channels/message_channel.ex`

**Features**:
- ✅ Topic format: `message:<type>:<id>` (e.g., `message:direct:uuid`)
- ✅ Socket auth delegated to `Famichat.Auth.Sessions.verify_access_token/1`
- ✅ `join/3` callback with authorization checks
- ✅ `handle_in("new_msg", ...)` for message handling
- ✅ Encryption-aware payload support (preserves metadata)
- ✅ **Telemetry events**:
  - `[:famichat, :message_channel, :join]`
  - `[:famichat, :message_channel, :broadcast]`
  - `[:famichat, :message_channel, :ack]`
- ✅ Performance budget: 200ms default
- ✅ Sensitive metadata filtering (encryption fields excluded from telemetry)

**Documentation**:
- ✅ Excellent inline docs with connection examples ([lines 1-90](../../backend/lib/famichat_web/channels/message_channel.ex#L1-L90))
- ✅ Mobile background handling notes (iOS ~30s, Android Doze mode)

**Tests**:
- ✅ Green: [message_channel_test.exs](../../backend/test/famichat_web/channels/message_channel_test.exs) now mints access tokens via Accounts helpers (join/broadcast/ack telemetry asserted)

---

### Data Model (100% Schema, 90% Logic)

**Database Migrations**: 11 applied
1. ✅ `20250125021514_create_users.exs` - Base user schema
2. ✅ `20250125040001_create_families.exs` - Family grouping
3. ✅ `20250125122459_create_conversations.exs` - Conversation schema with types
4. ✅ `20250125241524_create_messages.exs` - Message schema
5. ✅ `20250125370000_add_role_to_users.exs` - User roles (admin/member)
6. ✅ `20250126000000_add_email_to_users.exs` - Email field
7. ✅ `20250226123807_create_group_conversation_privileges.exs` - Role tracking
8. ✅ `20250427123456_add_direct_key_to_conversations.exs` - Deduplication
9. ✅ `20250427123457_add_hidden_by_users_to_conversations.exs` - Visibility
10. ✅ `20251005090000_accounts_phase_one.exs` - Family memberships, user_tokens, user_devices, passkeys, email encryption backfill
11. ✅ `20251012090000_drop_legacy_user_family_fields.exs` - Removed `users.family_id/role` columns + indexes

**Schemas**:
- ✅ **Accounts.User** ([accounts/user.ex](../../backend/lib/famichat/accounts/user.ex)) - Encrypted email, status enum, Cloak-backed email fingerprint
- ✅ **Accounts.FamilyMembership** ([accounts/family_membership.ex](../../backend/lib/famichat/accounts/family_membership.ex)) - User ↔ family (role enum)
- ✅ **Accounts.UserToken** ([accounts/user_token.ex](../../backend/lib/famichat/accounts/user_token.ex)) - Single hashed-token table (invite/magic/pair/reset)
- ✅ **Accounts.UserDevice** ([accounts/user_device.ex](../../backend/lib/famichat/accounts/user_device.ex)) - Refresh rotation, trust window, revocation
- ✅ **Accounts.Passkey** ([accounts/passkey.ex](../../backend/lib/famichat/accounts/passkey.ex)) - WebAuthn credential storage, sign_count tracking, enable/disable
- ✅ **Accounts.Token / RateLimiter** ([accounts/token.ex](../../backend/lib/famichat/accounts/token.ex)) - Issuance + rate limits
- ✅ **Username normalization** (`backend/priv/repo/migrations/20251014090000_add_username_fingerprint_to_users.exs`) - Case-preserving display with deterministic fingerprint lookups, collision auto-suffixing
- ✅ **Invite acceptance flow** (`Accounts.accept_invite/1` + `AuthController.accept_invite/2`) - One-use consumption with 10 min registration JWT handshake
- ✅ **Family** ([chat/family.ex](../../backend/lib/famichat/chat/family.ex)) - Household grouping
- ✅ **Conversation** ([chat/conversation.ex](../../backend/lib/famichat/chat/conversation.ex)):
  - Types: `:direct`, `:self`, `:group`, `:family`
  - Immutable type (enforced via separate create/update changesets)
  - `direct_key` for uniqueness (SHA256 hash)
  - `hidden_by_users` array for per-user soft-delete
- ✅ **Message** ([chat/message.ex](../../backend/lib/famichat/chat/message.ex)):
  - Types: 8 types (only :text actively used)
  - Statuses: 3 statuses (only :sent implemented)
  - `metadata` JSONB field for encryption data
- ✅ **ConversationParticipant** ([chat/conversation_participant.ex](../../backend/lib/famichat/chat/conversation_participant.ex)) - Join table
- ✅ **GroupConversationPrivileges** ([chat/group_conversation_privileges.ex](../../backend/lib/famichat/chat/group_conversation_privileges.ex)):
  - Roles: `:admin`, `:member`
  - Tracks who granted the privilege
  - Prevents last admin removal

**Type Boundaries**:
- ✅ Immutable after creation (separate changesets enforce this)
- ✅ Direct: Exactly 2 users, unique via `direct_key` (SHA256 hash) + validated family membership
- ✅ Self: Single user conversations
- ✅ Group: 3+ users, admin/member roles tracked
- ⚠️ Family: Type defined but no creation function

---

### Telemetry & Monitoring ✅ COMPREHENSIVE

**Infrastructure**:
- ✅ All service layer operations wrapped in `:telemetry.span/3`
- ✅ Performance budget tracking (200ms default, configurable)
- ✅ Sensitive data filtering (encryption metadata excluded)
- ✅ Error telemetry with structured metadata

**Events Emitted**:
- Message operations:
  - `[:famichat, :message, :sent]`
  - `[:famichat, :message, :serialized]`
  - `[:famichat, :message, :deserialized]`
  - `[:famichat, :message, :decryption_error]`
- Conversation operations:
  - `[:famichat, :conversation_service, :create_direct_conversation]`
  - `[:famichat, :conversation_service, :list_user_conversations]`
  - `[:famichat, :conversation_service, :assign_admin]`
  - `[:famichat, :conversation_service, :assign_member]`
- Channel operations:
  - `[:famichat, :message_channel, :join]`
  - `[:famichat, :message_channel, :broadcast]`
  - `[:famichat, :message_channel, :ack]`

**Guides**:
- ✅ [telemetry.md](../../backend/guides/telemetry.md) - Comprehensive documentation
- Performance budgets explained
- Event naming conventions
- Sensitive data handling

---

### Testing Infrastructure ✅ STRONG COVERAGE

**Test Files**: 20 test files
- ✅ [conversation_service_test.exs](../../backend/test/famichat/chat/conversation_service_test.exs) - 18KB
- ✅ [message_channel_test.exs](../../backend/test/famichat_web/channels/message_channel_test.exs) - 42KB (extensive!)
- ✅ [conversation_visibility_service_test.exs](../../backend/test/famichat/chat/conversation_visibility_service_test.exs)
- ✅ [group_conversation_privileges_test.exs](../../backend/test/famichat/chat/group_conversation_privileges_test.exs)
- ✅ [message_service_test.exs](../../backend/test/famichat/chat/message_service_test.exs)
- ✅ [conversation_changeset_test.exs](../../backend/test/famichat/chat/conversation_changeset_test.exs)
- ✅ [conversation_test.exs](../../backend/test/famichat/chat/conversation_test.exs)
- ✅ [message_channel_test.exs](../../backend/test/famichat_web/channels/message_channel_test.exs) - access token + telemetry coverage

**Test Infrastructure**:
- ✅ ExMachina for factories
- ✅ Mox for mocking
- ✅ ExCoveralls for coverage (not yet run)
- ✅ Telemetry.Test for event assertions

**Test Quality**:
- ✅ Comprehensive scenarios (happy path, edge cases, errors)
- ✅ Telemetry verification in critical paths (channels, services)
- ✅ Performance budget checks in some tests
- ⚠️ Coverage metrics unknown (run `mix coveralls` next)

---

### Development Tooling ✅ PRODUCTION-GRADE

**Docker Environment**:
- ✅ Docker Compose with profiles (`postgres`, `web`, `assets`)
- ✅ Development volume mounts (hot reload)
- ✅ `./run` script for container commands
- ✅ Environment variables via `.env` file

**Code Quality Tools**:
- ✅ **Credo** (linting) - Passing
- ✅ **Dialyzer** (static analysis) - Passing
- ✅ **Sobelow** (security) - Passing
- ✅ **Formatter** with `.formatter.exs` - Configured
- ✅ **Lefthook** git hooks:
  - Pre-commit: Starts Docker, waits for services, formats staged files
  - Pre-push: Runs checks (format, lint, tests)

**CI/CD**:
- ✅ GitHub Actions workflow (`.github/workflows/`)
- ✅ Coveralls integration (configured but not actively used)
- ✅ Security scanning

---

### API Endpoints ✅ BASIC

**REST Endpoints**:
- ✅ `GET /api/v1/hello` ([hello_controller.ex:4](../../backend/lib/famichat_web/controllers/hello_controller.ex#L4)) - Health check
- ✅ `POST /api/test/broadcast` - Canonical secure CLI broadcast verification endpoint (auth required, membership enforced, canonical payload contract)
- ✅ `POST /api/test/test_events` - Compatibility alias to canonical endpoint with deprecation/sunset headers
- ✅ `GET /up` - Health check endpoint
- ✅ `GET /up/databases` - Database health check

**LiveView** (Dev/Test only):
- ✅ `/admin/message-test` ([message_test_live.ex](../../backend/lib/famichat_web/live/message_test_live.ex)) - Message testing UI
- ✅ `/admin/tailwind-test` ([tailwind_test_live.ex](../../backend/lib/famichat_web/live/tailwind_test_live.ex)) - UI component testing
- ✅ `/admin/dashboard` - Phoenix LiveDashboard

**WebSocket**:
- ✅ `/socket` - Phoenix Channel endpoint
- ✅ Topic pattern: `message:<type>:<conversation_id>`

---

### Phoenix LiveView UI 🔄 IN PROGRESS

**Current State**:
- ✅ LiveView setup and configuration
- ✅ Test LiveView pages ([message_test_live.ex](../../backend/lib/famichat_web/live/message_test_live.ex))
- ✅ LiveView Hooks ([message_channel_hook.js](../../backend/assets/js/hooks/message_channel_hook.js))
- ✅ Theme switching components ([theme_switcher.ex](../../backend/lib/famichat_web/components/theme_switcher.ex))
- ✅ Core components library ([core_components.ex](../../backend/lib/famichat_web/components/core_components.ex))

**In Progress** (Sprint 8):
- 🔄 Authentication UI (login/registration pages)
- 🔄 Messaging interface (conversation list, message view)
- 🔄 Real-time channel integration via LiveView Hooks

**Missing**:
- ❌ Full messaging UI (conversation management)
- ❌ User authentication flows
- ❌ Production-ready styling
- ❌ Offline support / PWA features (future)

**Status**: Core infrastructure exists, building out messaging UI in Sprint 8

**Note**: Native mobile app (Flutter/iOS/Android) deferred until Layer 4 (Autonomy & Safety features). Current focus is dogfooding with LiveView web UI.

---

## 🚧 In Progress (Sprint 7 Closeout)

### Completed Core Stories
- ✅ **7.1.1-7.1.2**: Phoenix Channel module with comprehensive tests
- ✅ **7.1.3**: Channel routing and authorization integration landed
- ✅ **7.1.4**: Encryption telemetry validation (join/broadcast assertions with sensitive metadata filtering)
- ✅ **7.4.2**: Secure canonical CLI broadcast workflow (`/api/test/broadcast`) with `200/401/403/422` contract coverage and no-broadcast guarantees on non-200 paths
- ✅ **7.9**: Accounts context refactor (single-table token model, passkey-first onboarding, device trust, recovery)
- ✅ **7.10.1**: Type-immutable conversation schema (separate changesets)
- ✅ **7.10.8**: Conversation `hidden_by_users` field added
- ✅ **7.10.9**: Conversation hiding/unhiding functionality

### Active Stories

#### Story 7.10.5-6: Group Role Management Tests ✅
- **Status**: Schema, core behavior, and adversarial edge-case coverage are complete
- **Files**:
  - Implementation: [conversation_service.ex](../../backend/lib/famichat/chat/conversation_service.ex)
  - Tests: [group_conversation_privileges_test.exs](../../backend/test/famichat/chat/group_conversation_privileges_test.exs)
  - Edge-case tests: [conversation_service_test.exs](../../backend/test/famichat/chat/conversation_service_test.exs)
- **Coverage Highlights**:
  - Last-admin invariants (demotion/removal cannot orphan group)
  - Lock-contention re-checks for stale admin grants (`assign_admin` and `assign_member`)
  - Non-admin rejection for cross-user privilege removal

#### Story 7.2: Broadcast Testing Follow-through 🔄
- **Status**: Core tests are present; final outcome-focused verification pass still open
- **Scope**: Keep assertions centered on externally observable behavior and side effects
- **Dependency**: Canonical path depends on the completed 7.1.3 and 7.4.2 foundations

#### Story 7.3: Client/Operator Documentation Consolidation 🔄
- **Status**: Canonical runbook published and locked with integration assertions
- **Runbook**: `docs/runbooks/canonical-messaging-flow.md`
- **Integration Test**: `backend/test/famichat_web/integration/canonical_messaging_flow_test.exs`

### Cross-cutting Follow-through

#### Repo-wide Gate Debt ⚠️
- **Status**: Targeted story verification is green, but repo-wide `elixir:lint` and `elixir:static-analysis` have pre-existing failures outside completed story scope
- **Tracking Doc**: [7.4.2-cli-broadcast-plan.md](7.4.2-cli-broadcast-plan.md)

---

## ❌ Not Implemented

### Critical Missing Features

#### 1. End-to-End Encryption ⚠️ VERTICAL SLICE LANDED, HARDENING REMAINS
- **Impact**: Trust posture risk remains until durability/key lifecycle are complete.
- **What Exists Now**:
  - OpenMLS Rust NIF integration is wired for core `create_group -> create_application_message -> process_incoming`.
  - MessageService send/read paths enforce fail-closed runtime gating through `nif_health`.
  - Adversarial tests cover malformed ciphertext, cross-group misuse, replay rejection, and telemetry redaction behavior.
- **What's Missing**:
  - Durable MLS group/epoch/pending-commit persistence and crash/restart recovery.
  - Remaining key lifecycle hardening (rejoin persistence + revocation strategy).
  - End-to-end client-facing flows beyond the current backend vertical slice.
- **Planned**: Sprint 9 hardening + operational rollout gates.
- **Effort**: ~2-3 weeks for durability/lifecycle hardening and adversarial matrix expansion.
- **Dependencies**: ADR 010 accepted; continue hardening in `backend/infra/mls_nif` and canonical MessageService path.

#### 3. Message Status Tracking ❌ PARTIAL
- **Impact**: Poor UX - users don't know if messages were delivered/read
- **What's Working**:
  - Schema supports `:sent`, `:delivered`, `:read`
  - All messages created with `:sent` status
- **What's Missing**:
  - No `:delivered` status update when message reaches client
  - No `:read` status update when user reads message
  - No read receipts UI
  - No acknowledgment tracking system
- **Planned**: Future sprint (after auth)
- **Effort**: ~3-5 days

#### 4. Media Messages ❌ SCHEMA READY
- **Impact**: Cannot share photos, videos, files (major feature gap)
- **Schema Supports**: `:voice`, `:video`, `:image`, `:file`
- **What's Missing**:
  - No upload handling (no endpoints)
  - No storage integration (S3/MinIO configured but unused)
  - No media URL generation
  - No thumbnail generation
  - No download endpoints
- **Planned**: Future sprint
- **Effort**: ~1 week
- **Dependencies**: Need storage decision (S3 vs MinIO vs local)

#### 5. Production Deployment ❌ NO CONFIG
- **Impact**: Cannot deploy to production
- **What's Missing**:
  - No production Docker config
  - No HTTPS/TLS setup
  - No CDN integration (for static assets)
  - No database backups
  - No monitoring (Prometheus/Grafana mentioned but not set up)
  - No logging aggregation
  - No error tracking (Sentry/Rollbar)
- **Planned**: Sprint 13 (Final Polish)
- **Effort**: ~1 week

---

## 🔁 Open Follow-ups (Post Auth Hardening)
- ✅ Add `enrollment_required_since` to `users` and sync it around magic-link flows (MAG-03 probation) — landed via 20251013094500 migration and follow-up state update
- ✅ Emit telemetry for OTP issuance to align with plan Section 10 — `Accounts.issue_otp/1` now emits `[:famichat, :auth, :otp, :issue]`
- 🔄 Decide whether trusted device windows should roll forward on refresh (currently fixed 30-day expiry)
- ✅ Document `Accounts.reissue_pairing/2` in the API surface or mark it internal-only — captured in `docs/API-DESIGN.md`
- 🔄 Add perf-budget checks for invite issuance & refresh (PERF-01/02)
- ✅ Explicit DM cross-family isolation tests (FAM-02) now live in `conversation_service_test.exs`
- ✅ Passkey payload compliance landed: challenge endpoints now emit WebAuthn `publicKey` options and opaque handles (legacy challenge-token payload removed)

#### 6. LiveView Messaging UI 🔄 IN PROGRESS
- **Impact**: Needed to dogfood the product
- **Current State**: Core LiveView infrastructure exists, messaging UI being built
- **What Exists**:
  - LiveView setup and test pages
  - LiveView Hooks for channel integration
  - Theme switching components
  - Core component library
- **What's Missing**:
  - Full messaging UI (conversation list, message thread)
  - Authentication pages (login/registration)
  - Production-ready styling
- **Planned**: Sprint 8 (LiveView Messaging UI & Authentication)
- **Effort**: ~2 weeks
- **Priority**: HIGH - needed to dogfood and validate UX
- **Note**: Native mobile app deferred until Layer 4

#### 7. Family-Wide Conversations ❌ TYPE DEFINED
- **Impact**: Cannot create family-wide chat rooms
- **What Exists**: Conversation type `:family` defined in schema
- **What's Missing**:
  - No `create_family_conversation/1` function
  - No auto-membership logic (should all family members join automatically?)
  - No family chat UI
- **Planned**: Future sprint
- **Effort**: ~2-3 days

#### 8. Advanced Features ❌ NOT PLANNED
- **Not Implemented**:
  - Message search
  - Conversation archiving (different from hiding)
  - User blocking
  - Typing indicators
  - Online/offline status
  - Message reactions (type exists but unused)
  - Voice/video calls (WebRTC mentioned but not implemented)
  - Message editing
  - Message threading/replies
  - @mentions
  - Message pinning

---

## 📈 Metrics & Technical Debt

### Code Quality Metrics
- **Test Files**: 20
- **Source Files**: 49 Elixir modules
- **Test Coverage**: ⚠️ **UNKNOWN** (not measured - need to run `mix coveralls`)
- **Linting**: ⚠️ Repo-wide baseline debt remains (Credo)
- **Security**: ✅ Targeted checks passing (Sobelow - no new vulnerabilities in recent story scope)
- **Static Analysis**: ⚠️ Repo-wide baseline debt remains (Dialyzer)
- **Lines of Code**: ~12,000 (backend only)

### Performance Metrics
- **Performance Budget**: 200ms target for steady-state app-message path; encrypted-path measurements pending MLS integration
- **Telemetry Events**: All critical paths instrumented ✅
- **Database Queries**: ⚠️ Need to verify indexes on `conversation_id`, `sender_id`
- **Response Times**: Not formally measured in production (no prod environment)

### Technical Debt (Prioritized)

#### High Priority
1. **No Test Coverage Measurement** 🚨
   - Cannot assess quality
   - Don't know which code is untested
   - **Action**: Run `mix coveralls` and set 80% target

2. **MLS Durability + Lifecycle Hardening Not Complete** 🚨
   - ✅ OpenMLS + Rustler NIF vertical slice is implemented and tested
   - ✅ Fail-closed runtime gating and adversarial baseline tests are in place
   - ✅ Durable client inventory persistence policy is implemented (create/consume/replenish threshold)
   - ❌ Durable state persistence/recovery across restarts is not complete
   - ❌ Remaining key lifecycle hardening (rejoin persistence + revocation strategy) is not complete
   - **Action**: Sprint 9 hardening track (state persistence + lifecycle + adversarial expansion)

3. **Repo-wide Lint/Static Baseline Debt** 🚨
   - Credo and Dialyzer baseline failures obscure signal for new work
   - **Action**: Triage and isolate baseline debt so new regressions are obvious

4. **No Production Deployment Config** ⚠️
   - Cannot deploy or test at scale
   - **Action**: Create prod Docker config

#### Medium Priority
1. **Integration Test Matrix Expansion**
   - Canonical auth->subscribe->send->receive flow exists, but MLS/adversarial matrix is still expanding
   - **Action**: Extend characterization tests as Sprint 9 lands

2. **Message Status Only Supports :sent**
   - UX gap
   - **Action**: Implement :delivered and :read tracking

3. **No Media Upload Handling**
   - Feature gap
   - **Action**: Design storage strategy, implement upload endpoints

4. **Performance Budgets Not Enforced**
   - Only logged, not alerted on
   - **Action**: Set up Prometheus/Grafana alerts

5. **Database Indexing Needs Verification**
   - May have performance issues at scale
   - **Action**: Review query plans, add indexes

6. **LiveView Messaging UI Incomplete**
   - Core infrastructure exists but full messaging UX is still being built
   - **Action**: Sprint 8 scope (P1, non-blocking for Sprint 9 backend MLS)

#### Low Priority
1. **No Monitoring in Production**
   - Cannot track real-world performance
   - **Action**: Set up Prometheus/Grafana

2. **No Error Tracking**
   - Cannot debug production issues
   - **Action**: Integrate Sentry or Rollbar

3. **WebRTC Not Implemented**
   - Feature mentioned in vision but not started
   - **Action**: Future sprint (after MVP)

---

## 🔗 Related Documentation

### Implementation Details
- [Messaging Implementation](../../backend/guides/messaging-implementation.md) - How messaging works (send, retrieve, types)
- [Telemetry Guide](../../backend/guides/telemetry.md) - Performance monitoring strategy
- [Project Overview](../../backend/guides/overview.md) - Architecture and conversation types

### Sprint Details
- [Current Sprint Tasks](CURRENT-SPRINT.md) - Sprint 7 detailed checklist
- [Sprint History](ROADMAP.md) - What we've completed (Sprints 1-6)

### Deep Dives
- [System Architecture](../ARCHITECTURE.md) - Overall design and component interactions
- [Encryption Strategy](../ENCRYPTION.md) - Security model and E2EE roadmap
- [ADR 010](../decisions/010-mls-first-for-neighborhood-scale.md) - MLS-first rationale, product implications, and performance guardrails
- [Sprint 9 MLS/NIF Contract Deep Dive](9.0-mls-rust-nif-contract-deep-dive.md) - MECE implementation contract and gap closure checklist
- [Sprint 9 MLS Contract TDD Plan](9.1-mls-contract-tdd-plan.md) - Failing-test-first sequencing for contract implementation
- [API Design](../API-DESIGN.md) - API principles and response formats
- [Product Vision](../VISION.md) - Goals, users, use cases

### Design & UX
- [Information Architecture](../design/information-architecture.md) - Navigation and screen layouts
- [Onboarding Flows](../design/onboarding-flows.md) - User onboarding experience

---

## 🎯 Next Steps

### Immediate (This Week)
1. ✅ Canonical runbook + integration lock landed for `auth -> subscribe -> send -> receive`.
2. ✅ Sprint 9 hardening follow-through delivered: dedicated `conversation_security_states` store with optimistic lock-version conflict handling is active.
3. ✅ Add routine timing capture around the canonical flow command for drift tracking (`qa:messaging:fast` / `qa:messaging:deep` artifacts).
4. ⚠️ Triage repo-wide `elixir:lint` / `elixir:static-analysis` baseline debt separately so completed story behavior stays trackable.
5. ✅ Measure canonical-flow coverage snapshot (`cd backend && ./run qa:messaging:deep` -> `canonical_flow_coverage.txt`).

### Short-term (Current P0 Track - Sprint 9)
1. Expand adversarial lifecycle matrix (out-of-order merge/clear, staged payload tampering, and epoch-race stress) on top of `ConversationSecurityLifecycle`.
2. Lock telemetry/metrics gates for app-message and group lifecycle operations.
3. Complete key lifecycle hardening (rejoin durability/revocation strategy).
4. Define multi-node/state-distribution strategy for deterministic restart and cross-node recovery.

### Medium-term (Sprint 8 + Sprint 10-11)
1. **Sprint 8 (P1)**: LiveView messaging UI + auth UX on top of the same backend/channel contracts.
2. **Sprint 10 (2 weeks)**: Layer 0 dogfooding with encryption + Design System.
3. **Sprint 11**: Code quality, media upload support, message status tracking.

### Long-term (Sprint 11-13)
1. Code quality improvements
2. Comprehensive documentation
3. End-to-end testing
4. Final polish & release preparation

---

## 📋 How to Use This Document

### For Daily Work
- Check **🚧 In Progress** section for active sprint stories
- Review **Critical Blockers** to understand what's blocking us
- Use **🔗 Related Documentation** to find implementation details

### For Status Updates
- Use **📊 Executive Summary** for quick health check
- Reference **✅ Implementation Status** for detailed feature breakdown
- Check **📈 Metrics & Technical Debt** for quality indicators

### For Planning
- Review **❌ Not Implemented** for feature gaps
- Check **🎯 Next Steps** for prioritized work
- Use **Technical Debt** section for improvement planning

---

**Status Legend**:
- ✅ Complete and tested
- 🔄 In progress
- ⚠️ Partial implementation
- ❌ Not started
- 🚨 Critical blocker

**Last Updated**: 2026-02-25
**Next Review**: 2026-03-04 (weekly status update)
