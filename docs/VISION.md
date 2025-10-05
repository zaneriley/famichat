# Famichat - Product Vision

**Last Updated**: 2025-10-05

---

## Mission Statement

Famichat is a self-hosted, white-label communication platform designed specifically for families. It provides a secure and private digital space for families to stay connected through asynchronous messaging, occasional video calls, and unique "cozy" features inspired by games like Animal Crossing.

**Core Philosophy**: A non-capitalist app that's more about connection than constant updates - relaxed, intimate, and intentional communication.

---

## Product Goals

### Primary Goals
1. **Privacy & Security**: Top priority. End-to-end encryption, self-hosted control over data
2. **Performance**: Fast, responsive messaging (<200ms sender→recipient, <10ms typing latency)
3. **Neighborhood-Centric**: Designed for neighborhood-scale communication (100-500 people)
4. **Cozy Connection**: Ambient, asynchronous features that foster warmth without pressure

### Secondary Goals
1. **Bilingual Support**: Enable families spanning multiple languages (e.g., Japanese/English)
2. **Cross-Platform**: iOS app (primary), web client (secondary)
3. **Customizable Features**: Bespoke features tailored to each neighborhood's unique needs
4. **Searchable History**: Robust search for past conversations, media, and shared content

---

## Performance Requirements

**Rationale**: Security mechanisms add latency. E2EE encryption, key derivation, and signing operations take time. For users to trust the system, it must feel reliable and responsive. Slow systems feel broken, which undermines trust in security.

**Hard Requirements**:
- Sender → Receiver latency: <200ms (total time from user types to recipient sees)
- Typing → Display latency: <10ms (perceived responsiveness)

**Constraint Implications**:
- Encryption protocol must encrypt in <50ms (limits protocol choices)
- Network operations budgeted at 100ms (self-hosted deployment enables this)
- UI must use optimistic updates (show immediately, sync async)

**Why These Numbers**:
- 200ms: Industry threshold for "instant" (WhatsApp, Telegram target this)
- 10ms: Perception threshold (below this, feels instantaneous)
- Self-hosted deployment enables low network latency vs centralized services

**Measurement**:
- Telemetry on all critical paths
- P50/P95/P99 latency tracking
- Automated alerts on budget violations

**See**: [Performance Architecture](PERFORMANCE.md)

---

## Deployment Model

**Primary Model**: Self-hosted by neighborhoods

**Scale**: ~100-500 people per instance
- Smaller than "city" (too large, impersonal)
- Larger than "family" (needs multi-family communication)
- "Neighborhood" = natural social boundary

**Architecture**:
- One Famichat instance per neighborhood
- Single admin (neighborhood organizer)
- All families on that instance trust the admin's server
- No federation between instances (initially)

**Why Self-Hosting**:
- Data ownership: No centralized provider
- Privacy: Admin can't read E2E encrypted messages
- Performance: Local server = <50ms network latency
- Control: Neighborhood self-governance
- Alignment: Community-operated, not profit-driven

**Not Planned**:
- SaaS/managed hosting
- Multi-tenancy
- Centralized infrastructure

**Future Consideration**: Federation between neighborhood instances (deferred)

---

## Target Users

### Primary Users
**Neighborhoods**:
- 100-500 people in geographic proximity
- Multiple families wanting to communicate
- Need for secure, private group communication
- Want alternatives to mainstream social media
- Value control over their data

**Families Within Neighborhoods**:
- Nuclear families (parents and children)
- Extended families (grandparents, siblings, nieces, nephews)
- Geographically distributed (e.g., Missouri ↔ Tokyo)
- Different language preferences

### User Roles
1. **Admin**: Neighborhood organizer, manages server, controls settings
2. **Member**: Standard neighborhood member, can send messages and participate
3. **Family Admin**: Manages family-specific groups within neighborhood

---

## Use Cases

### Core Use Cases

#### 1. Personal Note-Taking (Self-Messages)
**User Story**: "As a user, I want to send messages to myself so that I can use the app as a personal notepad."

**Features**:
- ✅ Self-conversation type
- Text messages only (for now)
- Private, persistent storage
- No sharing options (by design)

---

#### 2. Direct Family Communication
**User Story**: "As a user, I want to send private messages to another family member, but only if we share a common family."

**Features**:
- ✅ Direct conversations (1:1)
- ✅ Family-membership validation (must share ≥1 family)
- ✅ Real-time delivery via channels
- End-to-end encryption (planned)
- Message status (sent, delivered, read) - partial

**Business Rules**:
- Users can ONLY message others if they share at least one family
- Returns `{:error, :no_shared_family}` otherwise
- Prevents cross-family communication (privacy)

---

#### 3. Group Conversations
**User Story**: "As a family admin, I want to create group chats for subsets of the family (e.g., 'Kids', 'Planning Committee')."

**Features**:
- ✅ Group conversation type (3+ users)
- ✅ Role-based permissions (admin vs member)
- ✅ Admin can add/remove members
- ✅ At least one admin required (prevents orphaned groups)
- Name and metadata customization

---

#### 4. Family-Wide Announcements
**User Story**: "As a family admin, I want to create a family-wide chat that includes all family members."

**Features**:
- ⚠️ Family conversation type (defined but not implemented)
- Auto-membership for all family members
- Admin-only posting (optional)
- Important announcements, events, shared calendar

---

#### 5. Asynchronous "Letters"
**User Story**: "As a user, I want to send thoughtful, letter-style messages that feel more intentional than quick texts."

**Features** (Planned):
- Special message type (`:letter`)
- Longer-form content
- Optional subject line
- Visual "letter" styling in UI
- Emphasizes slow, thoughtful communication

---

#### 6. Real-Time Video Calls
**User Story**: "As a user, I want to make video calls to family members for face-to-face time."

**Features** (Planned):
- WebRTC integration
- TURN/STUN server support
- Call history
- Quick call button from conversation view
- ~15% of usage (secondary to async messaging)

---

#### 7. Shared Family Space
**User Story**: "As a family member, I want to see shared calendars, photo albums, and other cozy community features."

**Features** (Planned):
- Shared family calendar (events, birthdays)
- Photo albums (curated collections)
- Location-specific info (weather in Missouri & Tokyo)
- Memory lane (past moments, anniversaries)

---

#### 8. Searchable Content
**User Story**: "As a user, I want to search past conversations and media so I can find important information later."

**Features** (Planned):
- Full-text message search
- Filter by sender, date, media type
- Search across conversations
- Media search (photos, videos)

---

### Advanced Use Cases (Future)

#### 9. "Cozy" Ambient Features
Inspired by Animal Crossing - features that foster connection without pressure:

**Phone Bumping / Finger Touching**:
- Physical gesture to merge families or add contacts
- iOS Nearby Interaction framework
- Vibration feedback on successful connection
- Fun, frictionless onboarding

**Ambient Tracing**:
- Shared canvas/sketchbook (daily or weekly)
- Draw across another person's visible area
- Ephemeral art that disappears after time period
- Playful, low-pressure interaction

**Status Updates ("Thinking of You")**:
- Simple status field ("Gardening", "Drinking coffee")
- No pressure to be "online" or "available"
- Ambient awareness without obligation

---

## Cultural & Family-Specific Needs

### Bilingual Support
**Challenge**: Families spanning multiple languages (e.g., Japanese ↔ English)

**Requirements**:
- UI translation support (i18n)
- Easy language switching per user
- Support for right-to-left languages (future)
- Locale-specific date/time formatting

**Implementation**:
- Flutter localization (per-user preference)
- Backend locale support in LiveView
- Easy addition of new languages (community contribution)

---

### Location-Specific Information
**Challenge**: Families distributed across time zones and locations

**Features** (Planned):
- Location-based weather (e.g., Missouri & Tokyo)
- Time zone awareness (show local time for each user)
- Location-based holidays and events
- Cultural calendar support (e.g., Japanese holidays)

---

### Family Traditions & Customization
**Challenge**: Every family is unique

**Features**:
- Customizable app branding (logo, colors, family name)
- Feature toggles (enable/disable specific features)
- Custom fields (family-specific data)
- Bespoke features (via white-label platform)

**Examples**:
- "Riley Family Home" with custom crest logo
- Japanese/English dual-language support
- Missouri & Tokyo weather widgets
- Family recipe collection (custom feature)

---

## White-Label & Turnkey Considerations

### Customization Capabilities

#### Branding
- **Logo**: Upload custom family icon/crest
- **Colors**: Primary, secondary, accent colors
- **Name**: Family name displayed throughout app
- **Theme**: Light/dark mode, custom themes

**Implementation**:
- Backend theme configuration endpoint
- Flutter theme system integration
- Per-family theme storage in database

---

#### Features
- **Enable/Disable**: Toggle specific features per family
- **Language Options**: Add new language support
- **Custom Features**: Build family-specific functionality

**Examples**:
- Family A: Enables video calls, disables letters
- Family B: Japanese + English, Missouri/Tokyo weather
- Family C: Custom recipe collection feature

---

#### Privacy & Security
- **Self-Hosted**: Full control over data and infrastructure
- **End-to-End Encryption**: Messages encrypted client-side
- **Passcodes**: Optional passcode protection
- **Data Export**: Families can export their data

---

### Deployment & Maintenance

**Self-Hosting Requirements**:
- Docker & Docker Compose
- PostgreSQL database
- Object storage (S3, MinIO, or local)
- TURN/STUN servers (for video calls)
- SSL/TLS certificates (for HTTPS)

**Maintenance Considerations**:
- Automated updates (Docker image updates)
- Database backups (automated)
- Monitoring & alerting (optional)
- Security patches (timely updates)

**Ease of Deployment**:
- One-command setup (`docker-compose up`)
- Environment variable configuration
- Migration scripts (automated)
- Documentation for non-technical users

---

## Communication Modes

### Asynchronous Communication (Primary - 85% of usage)
**"Letters"**: Thoughtful, longer-form messages
- Emphasis on slow, intentional communication
- Subject lines and formatting
- Visual "letter" styling
- No pressure to respond immediately

**Text Messages**: Quick updates and conversations
- Standard chat interface
- Real-time delivery
- Read receipts (optional)
- Typing indicators (optional)

---

### Real-Time Communication (Secondary - 15% of usage)
**Video Calls**: Face-to-face connection
- WebRTC-based
- Call history
- Screen sharing (future)
- Group calls (future)

**Voice Messages**: Quick audio notes
- Record and send
- Playback controls
- Transcription (future)

---

## User Experience & Design Principles

### Family-Centric Design
**Principles**:
1. **Warmth over Efficiency**: Prioritize emotional connection
2. **Intention over Distraction**: Encourage thoughtful communication
3. **Privacy over Convenience**: Security first, even if it's harder
4. **Simplicity over Features**: Only what families actually need

**Visual Identity**:
- Warm, inviting color palette
- Soft edges, rounded corners
- Family-specific imagery (photos, icons)
- Playful but not childish

---

### Information Architecture
**Bottom Tab Navigation**:
1. **Letters** (Default): Inbox with letter-style messages
2. **Calls**: Call history and quick call access
3. **Family Space**: Shared calendar, albums, cozy features
4. **Search**: Find past content
5. **Profile**: User & family settings

**Detailed IA**: See [design/information-architecture.md](design/information-architecture.md)

---

### Onboarding Experience
**Goals**:
1. Make account creation easy and fun
2. Guide users through key features
3. Emphasize privacy and security benefits
4. Create emotional connection to the app

**Flow**:
1. Account creation (username, email, password)
2. Profile setup (avatar, display name)
3. Family creation or invitation
4. Feature tour (optional)
5. Send first message (guided)

**Innovative Features**:
- **Phone Bumping**: Physical gesture to add family members
- **Nearby Interaction**: iOS framework for proximity detection
- **Vibration Feedback**: Confirm successful connection

**Detailed Onboarding**: See [design/onboarding-flows.md](design/onboarding-flows.md)

---

## Technical Considerations

### Security (Top Priority)
**Requirements**:
- End-to-end encryption (Signal Protocol)
- Self-hosted deployment (user controls data)
- Passcode protection (optional)
- Secure key management
- Regular security audits

**Architecture**:
- Client-side encryption (messages, media)
- Field-level encryption (sensitive user data)
- Database encryption at rest
- TLS for all connections

**Detailed Security**: See [ENCRYPTION.md](ENCRYPTION.md)

---

### Reliability
**Requirements**:
- 99.9% uptime target (self-hosted)
- Performance budget: 200ms for messaging operations
- Offline support (local storage, sync later)
- Graceful degradation

**Monitoring**:
- Telemetry for all critical operations
- Performance budget tracking
- Error tracking (Sentry or similar)
- Uptime monitoring

---

### Scalability
**Considerations**:
- Platform supports multiple families (white-label)
- Each family self-hosts their own instance
- Shared codebase, separate deployments
- Easy deployment and scaling

**Architecture**:
- Docker containerization
- Horizontal scaling (multiple backend instances)
- Database connection pooling
- CDN for static assets (optional)

---

### Maintenance
**Developer Time**:
- Ongoing development (new features)
- Bug fixes and security patches
- Community support (if open-source)
- Documentation updates

**User Time**:
- Minimal maintenance (automated updates)
- Docker image updates (simple)
- Database backups (automated)
- Monitoring (optional)

---

## Differentiation from Existing Solutions

### vs. Social Media (Facebook, Instagram)
❌ **Social Media**:
- Algorithmic feeds
- Advertising
- Data harvesting
- Constant updates pressure
- Public or semi-public

✅ **Famichat**:
- Chronological, intentional
- No ads, no monetization
- User controls data
- Slow, thoughtful communication
- Completely private

---

### vs. Mainstream Chat Apps (WhatsApp, Signal, Telegram)
❌ **Chat Apps**:
- Not family-specific
- No white-label customization
- Limited ambient features
- Not self-hosted (except Signal)

✅ **Famichat**:
- Designed for families
- Fully customizable (branding, features)
- Cozy, ambient connection features
- Self-hosted (full control)

---

### vs. Family Apps (FamilyWall, Cozi)
❌ **Family Apps**:
- Centralized (vendor lock-in)
- Limited customization
- Privacy concerns
- No end-to-end encryption

✅ **Famichat**:
- Self-hosted (no vendor)
- Fully white-labeled
- Privacy-first (E2EE)
- Open-source potential

---

## Success Metrics

### MVP Success Criteria
- [ ] User can register and login
- [ ] User can send/receive text messages in real-time
- [ ] User can create direct conversations
- [ ] User can message themselves (notes)
- [ ] Messages are encrypted end-to-end
- [ ] App can be deployed to production
- [ ] Basic onboarding flow works

### User Satisfaction Metrics (Future)
- Daily active users (per family)
- Messages sent per day
- Average response time
- Feature usage (calls vs messages vs family space)
- User retention (monthly active users)
- Net Promoter Score (NPS)

### Technical Metrics
- ✅ Test coverage ≥ 80%
- ✅ Performance budget adherence (200ms)
- ✅ Zero security vulnerabilities
- Uptime ≥ 99.9%
- Message delivery rate ≥ 99%

---

## Future Vision (Post-MVP)

### Phase 1: Enhanced Communication (6 months)
- Media messages (photos, videos, files)
- Voice messages
- Message editing and deletion
- Message reactions
- Threading/replies

### Phase 2: Family Features (12 months)
- Shared family calendar
- Photo albums (curated collections)
- Shared lists (shopping, to-do)
- Family events and milestones
- Memory lane (anniversaries)

### Phase 3: Cozy Features (18 months)
- Ambient tracing (shared canvas)
- Phone bumping onboarding
- Status updates ("Thinking of You")
- Weather widgets (location-based)
- Custom family features (plugin system)

### Phase 4: Community & Open Source (24 months)
- Open-source release
- Community contributions
- Plugin marketplace
- Multi-family hosting support
- Professional hosting service (optional)

---

## Open Questions

### Requiring Discussion:
1. **Group Membership Updates**: Should membership changes create a new conversation or update existing?
2. **Conversation Uniqueness**: Alternative mechanisms for enforcing uniqueness with dynamic participants?
3. **Computed Keys**: How to integrate with encryption/key management as product scales?
4. **White-Label Hosting**: Should we offer professional hosting service for non-technical families?
5. **Open Source**: When/how to open-source the platform?

### Resolved Questions:
- ✅ **Self-Messaging**: Decided to allow (personal notepad use case)
- ✅ **Family Validation**: Must share ≥1 family for inter-user conversations
- ✅ **Conversation Types**: Immutable after creation (see [decisions/001-conversation-types.md](decisions/001-conversation-types.md))

---

## Related Documentation

- **Current Status**: [STATUS.md](../STATUS.md) - Implementation progress
- **Roadmap**: [ROADMAP.md](../ROADMAP.md) - Sprint timeline
- **Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md) - Technical design
- **Encryption**: [ENCRYPTION.md](ENCRYPTION.md) - Security architecture
- **Design**: [design/](design/) - UI/UX specifications

---

**Last Updated**: 2025-10-05
**Version**: 1.4
**Status**: Living document - updated as vision evolves
