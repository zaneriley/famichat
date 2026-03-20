# Famichat Design Spec

Consolidated from: VISION.md, NOW.md, PRODUCT-LAYERS.md, JTBD.md, design/*, decisions/*, auth-refactor-plan.md, auth-ia-ddd-refactor.md, ARCHITECTURE.md, ENCRYPTION.md, and others.
Conflicts are flagged inline with `[CONFLICT]`. Unresolved decisions are flagged with `[OPEN]`.

---

## Product Vision & Values

- Private, self-hosted messaging for families and small neighborhoods (100–500 people per instance)
- Not a social media platform — no algorithmic feeds, no engagement optimization, no advertising
- Warmth over efficiency: prioritize emotional connection over throughput
- Intention over distraction: encourage thoughtful communication, not constant updates
- Privacy over convenience: security first, even when it adds friction
- Simplicity over features: only what families actually need

### What it is NOT
- Not a SaaS or managed hosting product
- Not multi-tenant or federated (initially)
- No friend-of-friend discovery
- No "last seen" indicators
- No read receipts by default (optional only)
- No typing indicators by default (optional only)
- No engagement algorithms
- No public or semi-public network

---

## Target Users & Scale

- Scale: ~100–500 people per self-hosted deployment (community, not city)
- One operator-owned deployment serves one trusted community
- A trusted community may contain one or more families / households
- All families on a deployment trust the operator's server
- Prefer separate deployments before true shared-instance multitenancy or federation
- User roles (trust hierarchy):
  - Community admin — can revoke any device for any user in the deployment's trusted community
  - Household admin (parent/guardian) — manages family members and devices; approves pending device additions for non-admin members
  - Adult member — standard access; self-approving on device addition via passkey
  - Non-admin member (teen, child) — device enters pending state after passkey login until household admin approves; OR immediate approval via QR scan from existing trusted device
  - Low-tech user (grandparent) — seamless if passkey synced; fallback to magic link + OTP; household admin receives passive notification

## Jobs to Be Done

### P0 — Table stakes (must solve to get adoption)
- Help us synchronize our lives and manage household logistics (parents + family unit; groceries, transportation, appointments)
- Help us nurture emotional bonds and share everyday moments, even when apart (all stakeholders; easy sharing of updates, photos, support)
- Give me peace of mind about my family's safety and well-being (parents; physical safety, location sharing, digital safety)

### P1 — Family differentiators
- Respect my independence and need for trusted autonomy (teens/tweens; safety monitoring vs surveillance; privacy as sign of trust)
- Make it easy for everyone to participate, regardless of age or technical ability (extended family + young children; low barrier to onboarding; diverse communication modes)

### P2 — Retention & depth
- Help us organize our digital chaos and preserve moments that matter (family unit; messaging as family archive; privacy control)
- Help us coordinate care and distribute the burden of responsibility (parents as caregivers + extended family; centralize care coordination; make demands visible)

---

## Deployment & Self-Hosting

- Docker + Docker Compose (one-command setup: `docker-compose up`)
- PostgreSQL 16 required
- Object storage (S3, MinIO, or local)
- TURN/STUN servers (for video calls, future)
- SSL/TLS certificates required
- Environment variable configuration
- Automated migration scripts
- Automated database backups
- Required production env vars: `WEBAUTHN_ORIGIN`, `WEBAUTHN_RP_ID`, `WEBAUTHN_RP_NAME`

### Topology and Shipping Stance

- Famichat is a software project, not a hosting company
- Primary model: operator-owned, single-tenant deployment
- Single-tenant means one operator-owned trust domain per deployment, not necessarily one family per deployment
- Supported venues for that same model:
  - home-hosted hardware
  - operator-owned cloud/VPS infrastructure
- Cloud is acceptable as rented infrastructure; it is not a Famichat-controlled trust anchor
- Multi-tenant hosted SaaS is out of scope
- Famichat-managed hosting is not the product model
- Optional central conveniences may exist later (for example release mirrors or one-click deploy templates), but they must never become mandatory trust anchors
- No mandatory Famichat account, remote config service, remote feature flags, or default telemetry back to Famichat for core operation

### Trust and Scope Model

- Internal hierarchy: `deployment -> community -> family -> user -> device -> conversation`
- `community` is the umbrella trust scope for one operator-owned deployment
- A `community` may contain one or more families / households
- `family` remains the primary intimate-group noun and core entity
- `household` remains the governance/auth term for invites, roles, and recovery scope
- `instance` / `deployment` are operational terms, not social terms
- Avoid `tenant` in product and architecture language; it implies a SaaS model Famichat is explicitly not pursuing
- If a cluster no longer wants the same operator trust anchor, prefer spinning it out to a separate deployment before introducing shared-instance multitenancy
- Community admin role check for L1: any user with at least one `:admin` household membership can create families. A formal `community_admin` column on `users` is a hardening step for L3.
- Cross-deployment migration and federation are deferred runways, not current product commitments

### Delivery and Operations Model

- One clearly supported production topology at a time; do not claim broad platform support without real runbooks
- The same core application artifact should be deployable on home-hosted and operator-owned cloud infrastructure
- Releases must be versioned, signed, and accompanied by migration and rollback notes
- Operators choose when to upgrade; no forced upgrades, silent feature rollouts, or remote kill switches
- Core messaging/auth operation must not depend on Famichat-controlled infrastructure after install
- Optional conveniences must degrade to zero without breaking an already-running instance
- Backups are operator-owned responsibilities supported by the product: automated, restorable, and never treated as real unless restore has been demonstrated

### Cloud Posture

- Cloud is acceptable only when the operator owns the account, domain, and secrets
- Cloud providers may still observe metadata, traffic patterns, and infrastructure state; this is an operational tradeoff, not a product blind spot
- After Path C, cloud/VPS providers and server operators should still be unable to read message content
- Home-hosted hardware offers stronger resistance to cloud-provider subpoenas; operator-owned cloud/VPS offers easier uptime, DNS/TLS, and offsite backup
- Both venues are self-hosting; the difference is operational tradeoff, not product identity

---

## UX Principles & Design Direction

- Multi-generational design: must work for kids, adults, and grandparents
- No constant-update pressure; slow, thoughtful communication encouraged
- No "last seen" indicators; no engagement optimization

### Theming & Design System Strategy
- Goal: support intensive theming and i18n — premade themes, an API for people to build their own frontends, community-contributed languages
- Current phase: hold off on any foundational design decisions while we technical spike, prototype, and dogfood
- Keep all Phoenix throwaway views tightly coupled so they can be deleted in one move; do not invest in design system infrastructure yet
- Once we learn what we actually need from dogfooding, build a robust system that supports the full range — not one aesthetic
- [OPEN] Specific visual direction (color palette, typography, motion) is deferred until we have real usage data

### Accessibility
- Simplified UI for kids (large buttons, emojis)
- Voice messages as alternative to typing
- Read-aloud support for young kids
- Large text mode
- Help tooltips and inline guidance
- Voice input as primary mode for grandparents
- Web access and PWA install for desktop (grandparents)

---

## Navigation & Information Architecture

> **Status: exploratory — not committed.** These are good candidate ideas from early thinking but the IA has not been validated through dogfooding. Specific tab structure, labels, and hierarchy should be treated as a starting point for prototyping, not a locked design.

### Candidate Navigation Structure (exploratory)
- 5 bottom tabs: **Letters**, **Calls**, **Family Space**, **Search**, **Profile**
- Letters as the default/primary content area (message-first)
- Admin-only features: accessible via Profile → Family Settings; clearly marked, not surfaced in main UX

### Candidate Tab Ideas (exploratory)

**Letters**
- Inbox in reverse chronological order (newest first)
- Each item: sender avatar, sender name, subject or content preview, timestamp, unread indicator
- Write a Letter: always-accessible action

**Calls**
- Recent call history
- Family members list with online/recently online status

**Family Space**
- Shared calendar, photo albums
- [OPEN TENSION] How much of this gets pulled from external services (Google Calendar, Gmail, etc.) vs built from scratch? Needs dogfooding before committing to any specific feature set
- [OPEN TENSION] Where does the neighborhood/inter-family coordination fit? Local open network vs bounded family-to-family invites vs something else entirely?

**Search**
- Cross-conversation search; filters by sender, date, content type

**Profile / Settings**
- User info, notifications, language
- Admin panel: user management, theme customization, feature toggles

---

## Onboarding

- Phone bump (proximity-based via iOS Nearby Interaction) is the primary/encouraged onboarding method
- Fallback contact-add methods must be clearly available when bump fails or is unavailable
- Onboarding must include non-bump pathways throughout
- Prototype and user-test bump reliability with real families before committing
- Vibration feedback on successful phone bump connection
- One-click join via invite link (for non-tech users)
- Guided setup with minimal steps
- Passkey registration with UV flag (`flag_user_verified`) enforced
- `user_verification: "required"` in both register and assert flows
- COSE key stored as portable JSON (not `term_to_binary`)

### Family Setup Flow (fourth and fifth public entry points)
- `/:locale/families/start/:token` is the token-gated fourth public entry point for MLP (alongside `/`, `/:locale/login`, and `/:locale/invites/:token`). Community admin creates a family and generates a `:family_setup` token (72-hour TTL). The first person to redeem the setup link becomes the family's household admin. The setup link is shared privately by the community admin.
- `/:locale/families/new` is the self-service fifth public entry point. Shown as a secondary CTA ("Set up your family space") on the login page when `self_service_enabled` is `true`. Rate-limited (10 per IP per hour). Creates an isolated family and a `:family_setup` token internally (`"initiated_by" => "self"`). The first person through becomes the family's household admin.

### Invite Flow
- Household admin issues invite → invitee accepts (one-time, 72-hour JWT) → passkey registration
- `POST /auth/invites/accept` consumes invite immediately + mints registration JWT
- Invite issuable by household admin only (role enforced)

### Device Trust Paths
- **Path A (passkey login)**: Immediate approval for admin/adult members; non-admin members enter pending/read-only state until household admin approves
- **Path B (QR/existing device)**: Higher-trust path; immediately approved for any role; no pending state; no admin review required
- [OPEN] Path A pending-state schema and enforcement not yet built

---

## Core Messaging Features

### Conversation Types (immutable after creation)
- `:self` — single-user note-taking; exactly 1 participant; no sharing options
- `:direct` — 1:1 messaging; exactly 2 users; unique via SHA256(sorted_user_ids + family_id + salt); idempotent creation
- `:group` — 3+ users; role tracking (admin/member); admin privileges enforced; last-admin invariant
- `:family` — all household members auto-included; admin-optional posting; for announcements, events

### Message Types
- Text messages (MVP)
- Letters (`:letter` type): optional subject line, visual "letter" styling, emphasizes slow/thoughtful communication
- Voice messages (planned)
- Photo sharing (planned)
- Emoji reactions (planned, low-friction response)
- Message threads/replies (planned)
- Video messages (future)
- File attachments (future)

### Real-Time Delivery
- <200ms sender → receiver latency (hard requirement)
- <10ms typing → display latency (hard requirement)
- Optimistic updates (show immediately, sync async)
- Phoenix Channels topic format: `message:<type>:<conversation_id>`
- `new_msg` WS payloads include stable `message_id`
- Error payloads converge on `error.code` and `action` semantics

### Message Status
- Sent, delivered, read — partial implementation, full completion deferred

---

## Communication Modes

### Asynchronous (primary — estimated 85% of usage)
- Letters: thoughtful, longer-form with subject lines
- Text messages: quick updates with real-time delivery
- Read receipts (optional)
- Typing indicators (optional)

### Real-Time (secondary — estimated 15% of usage)
- Video calls: WebRTC-based (future)
- Voice messages: record and send, playback controls, transcription (future)
- Group calls (future)
- Screen sharing (future)

---

## Family-Specific Features (future/planned)

> **Note:** Many of these require dogfooding before committing. The scope of what to build vs integrate is an open tension — especially for anything that overlaps with calendar, email, or other tools people already use.

- Photo albums (curated collections)
- Full-text message search (filter by sender, date, media type)
- Shared lists (groceries, to-do)
- Quick polls ("Pizza or tacos tonight?")
- @mentions in group conversations
- Shared family calendar — [OPEN TENSION] build vs pull from Google Calendar / iCal?
- Memory lane (past moments, anniversaries) — [OPEN TENSION] requires storing media/data at rest; local-first persistence resolves the text/message aspect; media storage policy still open
- Location-specific info (weather in multiple locations) — low-priority idea

### Ambient / Cozy Features (backlog — not accepted)
> These are ideas from early exploration. None are committed. Do not build until dogfooding tells us what's actually wanted.
- Status updates ("Thinking of You", "Gardening", "Drinking coffee")
- No "last seen" indicator (intentional, if we build any presence at all)
- Phone bumping / finger touching (iOS Nearby Interaction)
- Ambient tracing (shared canvas/sketchbook, ephemeral art)
- Slow mode; daily highlights; weekly digest

### Location & Safety (L4+, not MVP)
- Age-based autonomy model: <10 (walled garden) / 10–13 (parent notified) / 14+ (full autonomy)
- Check-ins (one-tap "I'm here" updates)
- ETA sharing (auto-stops after transit)
- Safe zones (geofence alerts: entered/left home, school)
- Emergency SOS (broadcast live location)
- Transparency dashboard: current autonomy level, active safe zones, location sharing status — visible to both teen and parent (mutual, not unilateral)
- Teen has private 1:1 messages (parent cannot read)

### Extended Family & Care Coordination (L5+)
- Family-to-family invites (mutual trust, accept/reject)
- Limit: 3–5 families max (intentionally small)
- Shared channels: carpool, playdates, neighborhood emergencies
- NOT a public bulletin board

---

## Customization & Theming

- Goal: support the full range — premade themes, an API for third-party frontends, community-contributed i18n
- Feature toggles per household (e.g., enable video, disable certain message types)
- Per-household theme stored in database
- Community contribution model for new languages
- [OPEN] Theming API design: CSS custom properties vs full component override vs separate frontend entirely?
- [OPEN] Customization scope: branding + feature flags only vs allowing custom code/frontends?
- Strategy: don't build any of this until dogfooding reveals what operators actually need to customize

---

## Security & Trust Model

### Core Security Philosophy
- Goal: make it **impossible** to be insecure — not just guarded, not just defended, axiomatically impossible
- If we don't own or sit on data, we can't lose it or expose it — data minimization is a security primitive, not a product choice
- Data minimization applies to the server and infrastructure layer, not to the user's own device. Under E2EE (Path C), the user's local device is the canonical home for decrypted messages — MLS forward secrecy discards old epoch keys, making server ciphertext permanently undecryptable. Persistent local storage is user ownership, not data liability.
- This applies to us and to any operator: the system should make it structurally impossible for anyone (including Famichat, including the self-hoster) to do the wrong thing
- Where security and utility conflict (e.g., losing messages or media would be bad), resolve case-by-case with explicit reasoning — do not silently trade security for convenience
- Physical/cryptographic principles take priority over software-layer protections

### Local Storage Privacy Stance (decided 2026-03-19)
- Under E2EE (Path C), the user's device holds the only readable copy of past messages — MLS forward secrecy discards old epoch keys, making server ciphertext permanently undecryptable after epoch rotation
- Persistent local storage in IndexedDB is structurally required: search, conversation previews, and offline access are impossible without it
- Message bodies encrypted at rest in IndexedDB (AES-256-GCM, same wrapping key infrastructure as ADR 012)
- Instant open: app opens from local data without passphrase re-entry; optional passkey/biometric unlock is wishlist
- Server ciphertext retention: short (30 days or all-device ACK); local store is canonical
- Recovery: 12-word BIP-39 phrase for L3; social key recovery (1-2 family members) as wishlist for L4+
- Two separate IndexedDB databases: `famichat_mls_keystore` (key material, non-reconstructible) and `famichat_messages` (message cache, reconstructible from server)
- Dexie.js (~30 kB) as IndexedDB wrapper; `liveQuery()` for Svelte 5 reactivity
- Full research: `.tmp/2026-03-19-local-first-storage/round-1/consensus.md`

### Current Architecture vs Security Goal

**What the NIF actually is today (important):**
- The server doesn't just decrypt on behalf of clients — both the sender's and recipient's MLS sessions live inside the same server-side process (`GroupSession` holds two `MemberSession` structs with full private key material)
- This is a two-actor co-located model: the server is cryptographically both parties, not a passive observer
- Private keys (signing keypairs, HPKE private keys, ratchet tree secrets) are held in a server-side DashMap and persisted encrypted to PostgreSQL on each snapshot
- Server compromise = all keys exposed = all past and future messages readable; MLS's post-compromise security guarantees are voided

**Current state (dogfooding only):**
- Server performs MLS decryption for LiveView rendering; operator can read all message content
- Acceptable at L0/L1 where you are the operator — threat model does not apply to yourself
- Not acceptable before other families trust your server with their private messages

**Target state (decided — Path C):**
- SPA frontend where OpenMLS compiles to WASM and runs in the browser
- Each device holds its own MLS session independently; private keys never leave the device
- Server becomes a dumb relay: stores and forwards encrypted blobs it cannot decrypt
- Phoenix backend (`/api/v1`) serves as the relay + auth layer; LiveView handles non-content surfaces (auth, nav, settings)
- Gate: must be in place before L3 (any family other than your own trusts the server)

### E2EE Migration Plan (Path C)

**Why Path C over alternatives:**
- Path A (WASM inside LiveView): breaks multi-device — new device can't recover old messages
- Path B (native iOS/Android): right eventually, but 12–16 weeks + mobile engineers; not now
- Path D (operator trust model): not real E2EE; security theater

**The Rust NIF is not a sunk cost (~70% reusable):**
- Keep: all cryptographic logic, epoch validation, snapshot MAC, error handling, all Track A hardening, 17/17 passing tests
- Keep: serialization format, validation utilities, message cache logic
- Change deployment: remove `rustler` (NIF bindings) + `dashmap` (server-side shared state); add WASM build target with OpenMLS `js` feature flag
- Delete: two-actor `GroupSession` model, server-side group state management (~30% of code)
- OpenMLS added official WASM support (`js` feature flag, January 2026); Wire ships this pattern in production via `core-crypto`

**Multi-device key recovery ("wife gets a new phone"):**
- On first login: generate 12-word recovery phrase; user writes it down once
- On new device: enter recovery phrase → derive per-device MLS key → server adds new device to group as new member
- Old messages not automatically available on new device (acceptable for now; future: optional re-encryption)

**First step before committing:**
- Spike OpenMLS → WASM compilation with the `js` feature flag
- If it compiles cleanly and browser crypto APIs work: Path C is locked
- Timebox: days, not weeks — if blocked, reassess

### Anti-Patterns — Do Not Do These

These are either things we tried and rejected, known security anti-patterns in MLS deployments, or design directions that conflict with our core goals. Treat this as a short-circuit: if a proposal resembles one of these, stop and re-examine.

| Anti-Pattern | Why It's Wrong | What To Do Instead |
|---|---|---|
| **Server holds MLS private keys** | Server compromise = all messages readable; voids MLS's post-compromise security guarantee entirely | Keys generated on device, never transmitted; server stores only encrypted blobs |
| **Two-actor co-located MLS model** (current NIF) | Both sender + recipient sessions on same server = server IS both parties; not E2EE in any meaningful sense | Independent per-device sessions; server is a relay |
| **Operator trust as a substitute for E2EE** ("Path D") | Self-hoster can read all messages; legal subpoena hands over everything; insider threat is unlimited | Cryptographic impossibility, not policy promises |
| **Server-side LiveView decryption for rendering** | Server must decrypt to render HTML = server sees plaintext; defeats purpose of MLS | WASM client-side decryption; server sends ciphertext only |
| **Plaintext fallback on decryption failure** | Silent fallback leaks content when crypto fails; error should be loud and fatal | Fail-closed always; surface error explicitly |
| **WASM inside LiveView shell without multi-device plan** (Path A) | New device can't recover old messages; key is in browser only; device loss = permanent message loss | Recovery phrase pattern before shipping multi-device |
| **`String.to_atom` on untrusted input** | Atom table is not GC'd in BEAM; unbounded atom creation = VM crash vector | `String.to_existing_atom` or explicit whitelist |
| **Storing COSE keys as `term_to_binary`** | Not portable; breaks on BEAM version changes; not inspectable | Portable JSON encoding |
| **`:rand.uniform` for OTP/security tokens** | Not cryptographically random; predictable under some conditions | `:crypto.strong_rand_bytes/1` |
| **Persisting MLS state on every message send** | 20MB+/conversation/day of TOAST writes; snapshot thrash | Write only on epoch-advancing operations (merge_pending_commit, mls_remove) |
| **Decrypting messages before broadcast auth check** | Wasteful + exposes plaintext to revoked socket path | `ensure_socket_device_active` before any broadcast |
| **`atom_to_binary` / `binary_to_term` on NIF snapshots without validation** | Silent load failure or malicious state injection | Required key + type validation before NIF call |
| **`last_message_preview` in the server API** | Server cannot produce plaintext previews under E2EE; any server-side preview field is an active spec violation and a migration trap | Permanently prohibited from the server API; SPA maintains its own local decrypted preview cache keyed on `(conversation_id, message_seq)` |
| **Building UI before dogfooding tells you what's needed** | Wasted investment; throwaway code that becomes load-bearing | Keep Phoenix views coupled and deletable; no design system investment until L2+ |
| **Federation before L3 validation** | Premature complexity; adds attack surface before product is even validated | Defer entirely; evaluate after L5 |
| **Promoting household admin → community admin via boolean escalation** | These are structurally different axes: household admin is a family-scoped care role; community admin is a deployment-scoped ceremony/trust authority. Collapsing them into a single privilege ladder creates confused authorization and makes coercion easier (one compromised family admin escalates to community power). Phase 1 peer review flagged this explicitly. | Keep the two role axes independent. Name the community-level check `community_admin?/1` with a clear docstring about the predicate swap planned at L3. |
| **Routing all community-level rights through one household admin** | The home environment should not be assumed trustworthy for all credentialing. If neighborhood/community participation requires household admin approval, a coercive household admin can deny community agency to other adults. Relevant to L4 teen autonomy but also to adult members. | Separate household administration from adult community agency. Credentialing for community-level rights should have an independent path. |

### What Is Implemented
- MLS (OpenMLS 0.8.1): forward secrecy and post-compromise security
- Messages encrypted at rest (Cloak/AES-256) and in transit (TLS)
- Past message keys deleted after use (forward secrecy)
- Compromised epoch does not expose prior epochs (post-compromise security)
- Snapshot MAC (HMAC-SHA256) — tamper → `snapshot_integrity_failed`, fail-closed
- No plaintext fallback when encryption is required (non-negotiable)
- NIF code path does no DB/network/file IO (non-negotiable)
- Sensitive crypto metadata redacted in logs/telemetry (non-negotiable)
- One shared production path — no LLM-only or test-only runtime branches (non-negotiable)
- Keep OpenMLS on patched, non-vulnerable ranges; monthly dependency review
- High/critical crypto advisory triggers patch SLA and release gate

### Snapshot Integrity (implemented)
- Elixir-side HMAC-SHA256 snapshot MAC (`Famichat.Crypto.MLS.SnapshotMac`)
- `MLS_SNAPSHOT_HMAC_KEY` env var required
- Snapshot MAC tamper → `snapshot_integrity_failed` error (fail-closed)
- Two-phase snapshot: extract under lock (fast) → serialize outside lock (~8–18ms)

### Revocation
- Device revocation kills active session immediately and triggers MLS group removal from all conversations
- Revoked device cannot access future messages (forward secrecy preserved)
- Revocation creates tombstone message in each conversation ("Zane removed iPhone 12 from this conversation")
- [CONFLICT] `revoke_device` revokes session but does NOT currently trigger MLS group removal — device remains MLS group member until `device_id`→MLS leaf mapping is built
- Connected channel clients receive explicit `session_terminated` event; revoked devices blocked from send/read

---

## Auth & Device Management

### Device States
- `trust_state`: `:pending` | `:active` | `:revoked`
- Pending: non-admin member after passkey login; read-only until household admin approves
- Active: admin self-approving, or any role via QR path
- Revoked: explicit revocation by admin

### Session Architecture
- Access tokens: short-lived, stateless, signed (Phoenix.Token), claims: user_id, device_id, issued_at (5–15 min)
- Refresh tokens: long-lived (30 days), cryptographically random, DB-stored for revocation
- Refresh tokens rotate on every use; old token invalidated immediately
- Theft detection: reused rotated token → entire token family invalidated; user must re-authenticate
- [OPEN] Should `trusted_until` roll forward on refresh or stay fixed at 30 days?

### Unread / Ack Model
- Ack model is per-user watermark: "If you read it anywhere, it's read everywhere." Read cursors are keyed on `(user_id, conversation_id)`, not per-device.
- Read cursors are persisted to DB (not ETS or process state) so acks survive reconnect.
- Ack cursor must only advance forward: use `GREATEST(stored_seq, incoming_seq)` in the upsert SQL.

### WebAuthn (Passkeys)
- Real ECDSA signature verification via Wax library (`Wax.register/3` + `Wax.authenticate/5`)
- UV flag (`flag_user_verified`) checked on both register and assert
- `user_verification: "required"` in both flows
- COSE key stored as portable JSON (not `term_to_binary`)
- Legacy format detector for existing keys

### OTP / Magic Link
- OTP uses `:crypto.strong_rand_bytes/1` (not `:rand.uniform`)
- Brute-force rate limit enabled; returns identical 401 to wrong-code (no email enumeration)
- Magic link + OTP as fallback for low-tech/passkey-sync users

### Token Kinds (canonical)
- `:invite`, `:invite_registration`, `:pair_qr`, `:pair_admin_code`
- `:passkey_registration`, `:passkey_assertion`, `:magic_link`
- `:otp`, `:recovery`, `:access`, `:session_refresh`
- `:family_setup` — issued by community admin or self-service; 72-hour TTL; consumed on first family setup completion
- Canonical kind mapping lives in `Auth.Tokens.Policy` only; no scattered string literals

---

## Performance Requirements

- Sender → receiver: <200ms (hard requirement)
- Typing → display: <10ms (hard requirement)
- Encryption: <50ms (budget)
- Network operations: <100ms (self-hosted advantage)
- Server encrypt path: ≤50ms
- Persist + broadcast path: ≤30ms
- Steady-state message decryption: ≤30ms
- Canonical flow: 200ms per-operation (CI FAIL if exceeded)
- MLS failure rate gate: <5% (CI gate)
- Telemetry on all critical operations (`:telemetry.span/3`)
- P50/P95/P99 latency tracking required for all critical paths
- Automated alerts on budget violations
- Performance regression tests in CI

---

## Technical Architecture

### Ownership Boundaries
- `Famichat.Chat` owns durable conversation security state and policy
- `Famichat.Crypto.MLS` and `backend/infra/mls_nif` are adapters only — no persistence tables
- `Famichat.Chat.MessageService` orchestrates state load/persist through Chat-owned boundaries
- `Famichat.Auth` is the single public surface for all auth flows
- `Famichat.Accounts` is schema-only (no business logic); one file per schema, no `schemas/` subfolder

### Key Tables
- `conversation_security_states` — durable encrypted state with optimistic `lock_version`
- `user_devices` — device_id, user_id, refresh_token_hash, previous_token_hash, trust_state, trusted_until
- `passkeys` — WebAuthn credentials via Wax
- `user_tokens` — context-scoped, hashed
- `conversation_security_client_inventories` — per-conversation one-time crypto intro objects
- `conversation_summaries` — canonical inbox read model (`conversation_id PK, latest_message_seq, last_message_at, member_count`); maintained by a PostgreSQL trigger on message insert; not a materialized view
- `auth_audit_logs` — PII-free audit trail for recovery events

### MLS Lifecycle
- Epoch validation: stage epoch == current+1, merge epoch == staged epoch; strict
- Fail-closed runtime health gate (`nif_health`) enforced before encrypt/decrypt
- Transactional send: message insert rolled back if state write cannot commit
- Replay-idempotency cache bounded to max 256 entries
- Revocation sealing: active revocations sealed only on `mls_remove` merge success
- Pending commit blocks send with `conversation_security_blocked` + `:pending_proposals`
- Send returns `recovery_required` + action `recover_conversation_security_state` on unrecoverable state
- [OPEN] `device_id`→MLS leaf index mapping gap — blocks full revoke→MLS removal

### Frontend & Client Platform (ADR 012 — spike passed 2026-03-01)
- **Browser SPA**: Svelte 5 + SvelteKit 2 + Vite; OpenMLS WASM in a Web Worker handles all encrypted message surfaces
- **LiveView continues** for auth, onboarding, settings, admin panel — tightly coupled and deletable, not permanent
- **Mobile (L3–L4)**: Capacitor 7 wrapping the Svelte SPA; passkeys via `ASWebAuthenticationSession` (system browser, required for self-hosted operators); `@capacitor/secure-storage` (Keychain-backed) for refresh tokens
- **Desktop (if/when)**: Tauri (Rust process + Svelte SPA); OpenMLS links natively, no WASM overhead
- **Native iOS (L5+)**: Swift + OpenMLS Rust lib via Swift Package Manager — evaluate after L3 only if Capacitor hits hard limits
- React off the table; Flutter rejected; LiveSvelte rejected (server sees plaintext props — incompatible with E2EE)
- **Spike results**: 10/12 criteria PASS; S7 + M3 (WKWebView passkey) pending physical iOS device confirmation before L3
- **Performance**: warm-path P95 = 1.90ms (gate 50ms); bundle 481.8 kB gzip (gate 500 kB)
- Full architecture, security non-negotiables, build pipeline: `docs/decisions/012-spa-wasm-client-architecture.md`

### Active Family Context
- Active family uses hybrid persistence: session cookie (per-session tab isolation) + `last_active_family_id` nullable FK on `users` (cross-device persistence, `on_delete: :nilify_all`).
- Resolution order: (1) explicit candidate from session, (2) `last_active_family_id` from DB, (3) first membership by `inserted_at`. Single-family users always resolve silently via path 3.
- `FamilyContext.resolve/2` is the single source of truth; membership is verified at every call. The module lives under `Famichat.Accounts`.

### Ash Framework
- Optional application layer; not a full-stack replacement
- Do NOT use Ash for high-risk correctness-sensitive paths (sessions/tokens/passkeys/recovery/chat auth)
- Safer: start with net-new bounded capabilities; strangler-style migration behind stable facades for existing flows
- Prefer to use Ash to scale resources, complex logic, prefer not to write complex or manual Ecto when Ash makes it easy.

---

## API Design

- Production-first contracts `/api/v1` are the source of truth
- Test-only routes (`/api/test/*`) are harness utilities, never product contracts
- Success envelope: `{"data": {}}` with optional `meta: {}`
- Error envelope: `{"error": {"code": "...", "message": "...", "action": "...", "details": {}}}`
- `error.code` required and stable; never leak `inspect(reason)` or internal exception payloads
- HTTP status codes: 200/201 (success), 204 (idempotent delete/revoke), 400 (invalid params), 401 (auth failed), 403 (forbidden), 404 (not found), 409 (security lifecycle blocked), 413 (payload too large), 422 (semantically invalid), 429 (rate-limited with `retry-after`)
- Message pagination via cursor: `GET /api/v1/conversations/:id/messages?after=<message_seq>`; cursor is `message_seq` (per-conversation monotonic integer), not `(inserted_at, id)` composite. Returns `meta.has_more` + `meta.next_cursor`.
- Future mutation endpoints should accept `Idempotency-Key` header for safe retries
- JSON keys: snake_case; spec blobs (e.g., WebAuthn `publicKey`) nested under snake_case wrapper (`public_key_options`)
- Timestamps: RFC 3339 UTC; `created_at`, `updated_at`
- `message_seq` strictly increasing per conversation; do not assume gap-free

---

## Naming & Terminology

- **Canonical domain terms**: `conversation`, `message`, `household` (governance unit; UI copy may say "family")
- **Conversation security state**: canonical term for durable security state (not "session snapshot")
- **Household**: governance unit for invites, roles, recovery scope (not "family" in code)
- `family_memberships` table name preserved; exposed as `Accounts.HouseholdMembership @source "family_memberships"`
- `Auth.Sessions.DeviceStore` (not `Device`) — signals persistence responsibility
- `Auth.Tokens.Policy` (policy), `Auth.Tokens.Storage` (adapter)
- Token verbs: **issue → fetch → consume** (ledgered); **sign → verify** (signed)
- Session verbs: **start_session → refresh_session → revoke_device → verify_access_token → require_reauth?**
- Passkey verbs: **issue_registration_challenge → issue_assertion_challenge → fetch_*_challenge → consume_challenge → register_passkey → assert_passkey**
- Rate limit buckets: `verb.object` naming (e.g., `passkey.assertion`, `session.refresh`)
- Error atoms: `:invalid | :expired | :used | :revoked | :trust_required | :trust_expired | :reuse_detected`
- Avoid protocol-coupled store names, new `key_package`-based Chat module names, crypto-centric policy names, and `session_snapshot` as a primary term
- Telemetry root: `[:famichat, :auth, <context>, <action>]`

### String field validation convention

Every user-facing `:string` field in an Ecto schema must have `validate_length` with an explicit `:max` and a corresponding `CHECK (char_length(col) <= N)` constraint at the DB level. System-generated string fields (token hashes, protocol identifiers, snapshot MACs) are exempt from application-level validation if the DB constraint is present. Guideline defaults: 255 for general text, 100 for names/labels, 2048 for URLs.

---

## Incremental Validation Layers

### L0 — Foundation (current)
- 1 user; solo technical validation
- Hypothesis: self-hosted Phoenix + MLS/OpenMLS is viable
- Success: deploy, create account, send encrypted message, <200ms, history persists
- Kill: MLS takes >5 weeks, self-hosting too difficult, <200ms unachievable, LiveView clunky

### L1 — Dyad (next)
- 2 users: parent + spouse; encrypted 1:1 family messaging
- Hypothesis: encrypted 1:1 solves JTBD #2 (emotional bonding)
- Features needed: 1:1 messaging, browser notifications, both passkey + QR device auth, real WebAuthn JS (`navigator.credentials.create()` / `navigator.credentials.get()`), real login page, invite redemption UI, home screen opens directly to the 1:1 conversation (no conversation list), warm empty states, auto-authenticate after passkey registration
- Deferred from L1: photo sharing, message threads, letters (validate daily text use first)
- Success: daily usage, replaces SMS/WhatsApp, cozy UI, zero encryption issues
- Kill: no daily use after 2 weeks, UI feels clinical not cozy

### L2 — Triad
- 3 users + 8–12yo kid; multi-generational group messaging
- Features: family group chat, shared lists, simple calendar, polls, age-appropriate UX, voice messages
- Kill: kid doesn't engage, logistics tools unused

### L3 — Extended Family
- 4 users + grandparent; multi-generational accessibility
- Features: invite link, guided setup, voice messages primary, PWA, desktop access
- Kill: grandparent can't onboard without help

### L4 — Autonomy & Safety (parallel with L5 after L3)
- Teen (13–17); parent/teen trust balance
- Features: age-based autonomy, location check-ins, safe zones, ETA, SOS, transparency dashboard
- Kill: teen refuses (feels like surveillance)

### L5 — Trusted Network (parallel with L4 after L3)
- Family + 2–3 trusted neighbor families
- Features: family invites, shared channels, 3–5 family max
- Kill: families don't coordinate this way, network grows uncontrollably

### L6 — Differentiation (not defined yet)
- What makes this different from other apps is an open question; to be answered through dogfooding L1–L5
- Candidate ideas: theming API, ambient features, slow/thoughtful communication modes — none committed
- Kill signal: families describe it as "just another app" with nothing worth staying for


---

## Open Questions

### Security & Data
- [OPEN] Memory lane / media archival: storing media at rest conflicts with data-minimization principle; how do we let people preserve memories without us holding their data?
- [PARTIALLY RESOLVED] Key recovery UX: 12-word BIP-39 phrase for L3; social key recovery (1-2 family members) as wishlist for L4+. Cloud backup deferred.
- [OPEN] Key lifecycle revocation: device/user removal semantics incomplete
- [OPEN] Coercion resistance at the household boundary: household admin currently gates all family-level participation. For L4 (teen autonomy) and beyond, adult community agency should not require household admin approval. The home environment is not always a trustworthy credentialing context. Research references: Merino et al. (TRIP/Votegral) on in-person credentialing under coercion; Ford on separating personhood from identity.

### Product Scope
- [OPEN] Inter-family/community model inside one trusted deployment: what kinds of cross-family coordination belong here (bounded family-to-family invites, shared channels, shared spaces) without turning it into a public or semi-public local network?
- [OPEN] Family tools scope: which household logistics (calendar, tasks, etc.) do we build vs integrate with existing tools (Google Calendar, Gmail, etc.)? Needs dogfooding
- [OPEN] Ambient/cozy features: which (if any) actually matter to users? Don't build until dogfooding reveals demand
- [OPEN] Design direction: what aesthetic does dogfooding tell us people actually want? No visual direction committed until then
- [OPEN] Identity scope across families: is a user's identity global across all families in a deployment, or scoped per family? The research literature on service-scoped pseudonyms (Ford & Strauss) suggests per-space pseudonyms enable abuse resistance without a global real-name layer. This matters once multi-family participation is real. No current design addresses it.

### Governance & Admission (L5+ — not current scope)

> These questions surfaced from the Phase 1 peer review (Review 4: Governance Model
> Fit) and subsequent research into decentralized governance (Ford, Borge, Ostrom,
> Adler, Merino). None are blocking L1–L3. They are recorded here so design decisions
> at those layers do not accidentally foreclose the governance options described in
> `ia-lexicon.md` § "Research Concepts Under Consideration."

- [OPEN] Governance procedures: how are community-level decisions made? Current model is admin unilateral action only. Research suggests bicameral approaches (one-household-one-vote for participation, one-adult-one-vote or random jury for moderation/appeals, double majority for constitutional changes). No governance procedures exist today beyond "community admin decides."
- [OPEN] Admission model: should membership require sponsor endorsement from existing members, and if so, how many sponsors? Current model is admin-issued invites with no sponsorship chain. Peer review recommends `joined_via` + `sponsored_by_user_id` on membership records as cheap L5 scaffolding. Related: should there be a per-household cap on invites per cycle to prevent one large family from dominating admission?
- [OPEN] Personhood vs identity: the system currently conflates "has an account" with "is a unique person." For anti-Sybil protection at the multi-family/neighborhood boundary (L5+), these are distinct claims. Personhood ceremonies (Ford, Borge et al.) prove "one real human, counted once, recently" without requiring legal identity. Residency, trustworthiness, and personhood should not collapse into a single credential.
- [OPEN] Federation topology: the current trust hierarchy is single-deployment only. If deployments ever interoperate (L5+), what is the federation unit? Research describes a graduated model (household → block → neighborhood → broader community) with an anytrust assumption (at least one ceremony organizer per event is honest). See anti-pattern: "Federation before L3 validation."
- [OPEN] Ceremony credentialing: should community membership be renewable on a cycle (ceremony epoch), or permanent once granted? Renewable credentials provide freshness and anti-Sybil protection but add friction. Peer review suggests nullable `communities.ceremony_epoch` + `communities.signing_public_key` columns as zero-cost scaffolding.
- [OPEN] Domain ownership and trust anchoring: SPEC says "operator owns the account, domain, and secrets" but does not address DNS verification as a trust signal, whether families within a community can have distinct domain identities, or what happens to trust relationships when a domain changes hands.

### Technical
- [OPEN] Should `trusted_until` roll forward on each refresh or stay fixed at 30 days?
- [OPEN] Group membership changes: update existing conversation vs create new vs immutable membership?
- [OPEN] Family conversation public creation API — currently seed/context-only
- [OPEN] Commit/update/add/remove MLS lifecycle: deeper payload/epoch semantics hardening
- [OPEN] Federation model: no federation, optional federation, or built-in (deferred)
- [OPEN] Theming API design: CSS custom properties vs component override vs separate frontend?
- [OPEN] Customization scope: branding + feature flags only vs allowing custom frontends?
- [OPEN] Token refresh cleanup: background job cadence for expired/revoked token pruning
- [OPEN] When/how to open-source the platform

## Conflicts & Tensions Captured

- [RESOLVED] Server-side decryption vs security goal: current architecture is a known dogfooding expedient; Path C (SPA + OpenMLS WASM) is the decided fix; gate is L3 — must ship before any family other than your own trusts the server
- [RESOLVED] Data preservation vs data minimization: resolved by scoping — data minimization applies to the server (ciphertext only after Path C); user devices hold decrypted messages as the canonical readable copy; MLS forward secrecy makes server ciphertext undecryptable after epoch rotation; persistent local storage IS the archive
- [CONFLICT] `revoke_device` semantics: intent is that revocation removes device from MLS group; actual implementation revokes session only; `device_id`→MLS leaf mapping not yet built
- [CONFLICT] ADR 008 defines conversation types as "dm" and "room"; ADR 001 uses "direct, self, group, family" — API spec and domain model use different taxonomies
- [CONFLICT] "household" vs "family" terminology: governance code uses "household"; UI copy, some ADRs, and some modules still say "family"; migration in progress but not complete
