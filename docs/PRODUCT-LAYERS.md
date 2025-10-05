# Famichat - Product Layers & Incremental Roadmap

**Last Updated**: 2025-10-05

---

## Product Philosophy

**Incremental Validation**: Each layer proves a hypothesis before building the next.
**User Progression**: Parent → Parent+Kid → Parent+Kid+Grandparent
**Feature Gating**: Only add complexity when prior layer validates.

---

## Layer 0: Foundation (Sprints 8-10)

**User**: Solo parent (you)
**Goal**: Prove technical foundation works
**Hypothesis**: Self-hosted Phoenix + server-side Signal Protocol encryption is viable

### Components

```
Technical Stack:
├── Phoenix LiveView (web UI for dogfooding)
├── Signal Protocol encryption (server-side via Rustler NIF + libsignal-client)
│   └── Sprint 9 implementation (3 weeks)
├── PostgreSQL (local data)
└── Self-hosted (Docker on homelab)

Current State (End of Sprint 8):
├── ✅ Encryption metadata infrastructure (serialization, telemetry)
├── ❌ No actual cryptographic encryption yet
└── ⚠️ Messages currently stored in plaintext

Data Model:
├── Users (individual accounts)
├── Families (household grouping)
└── Messages (encrypted storage)

Features:
└── Self-messages (notes, journaling)
    - Create account via LiveView
    - Send encrypted message to self
    - Retrieve message history
    - Verify encryption works
```

### Success Criteria
- [ ] Can deploy to homelab
- [ ] Can create account via web
- [ ] Can send/receive encrypted messages
- [ ] Message history persists
- [ ] Performance <200ms round-trip

### Blockers to Next Layer
- Signal Protocol integration incomplete
- Encryption broken
- Performance unacceptable
- Self-hosting too complex

---

## Layer 1: Dyad (Sprints 11-13)

**Users**: Parent + Spouse (you + wife)
**Goal**: Prove family messaging core
**Hypothesis**: Encrypted 1:1 family messaging solves emotional bonding (JTBD #2)

### New Components

```
Data Model Additions:
└── Conversations
    ├── Type: direct (1:1 between family members)
    └── Participants: 2 family members

Features:
├── 1:1 Family Messaging
│   ├── Send message to spouse
│   ├── Receive real-time (LiveView auto-updates)
│   ├── Message history (pagination)
│   └── Typing indicators (optional, test if "cozy")
│
└── Shared Moments
    ├── Photo upload/sharing
    ├── Emoji reactions
    └── Message threads (replying to specific message)
```

### JTBD Validation

**JTBD #2: Emotional Bonding**
- Send "thinking of you" messages
- Share photos from day
- Quick check-ins ("how's your day?")

**Metrics**:
- Daily active usage (both use it daily?)
- Message frequency (replaces SMS/WhatsApp?)
- Photo sharing (natural behavior or forced?)

### Success Criteria
- [ ] Daily usage by both users (7+ days)
- [ ] Replaces existing messaging (SMS/WhatsApp abandoned)
- [ ] Photo sharing feels natural
- [ ] UI feels "cozy" (qualitative feedback)
- [ ] Zero encryption issues

### Blockers to Next Layer
- Not used daily (no habit formation)
- Reverts to SMS/WhatsApp (not compelling)
- Photos feel clunky (upload/display issues)
- UI feels cold/clinical (not cozy)

---

## Layer 2: Triad (Sprints 14-17)

**Users**: Parent + Spouse + Kid (8-12 years old)
**Goal**: Prove multi-generational family group works
**Hypothesis**: Family group messaging solves logistics coordination (JTBD #1)

### New Components

```
Data Model Additions:
└── Conversations
    ├── Type: family (group for all family members)
    └── Participants: All family members

Features:
├── Family Group Chat
│   ├── All family members see messages
│   ├── Photo sharing (family moments)
│   ├── @ mentions (direct attention)
│   └── Message reactions (low-friction participation)
│
├── Logistics Tools
│   ├── Shared lists (groceries, todos)
│   ├── Simple calendar (family events)
│   └── Quick polls ("Pizza or tacos tonight?")
│
└── Age-Appropriate UX
    ├── Simplified UI for kids (big buttons, emojis)
    ├── Voice messages (alternative to typing)
    └── Read-aloud (accessibility for young kids)
```

### JTBD Validation

**JTBD #1: Logistics Coordination**
- Grocery list shared during shopping
- After-school pickup coordination
- Weekend plans consensus

**JTBD #2: Emotional Bonding (Multi-gen)**
- Kid shares school day highlights
- Parents share encouragement
- Family celebrates moments together

**Metrics**:
- Logistics use cases (shopping lists, coordination)
- Kid engagement (active participant or passive?)
- Multi-generational interaction (everyone participates?)

### Success Criteria
- [ ] Family uses for logistics weekly
- [ ] Kid actively participates (not just parents)
- [ ] Replaces family group text/WhatsApp
- [ ] Voice messages reduce friction for kid
- [ ] Lists/polls used naturally (not forced)

### Blockers to Next Layer
- Kid doesn't engage (too complex or boring)
- Logistics tools unused (not natural workflow)
- Still using WhatsApp family group (not compelling)
- Voice messages don't work (technical issues)

---

## Layer 3: Extended Family (Sprints 18-22)

**Users**: Parent + Spouse + Kid + Grandparent
**Goal**: Prove multi-generational accessibility (JTBD #5)
**Hypothesis**: Non-tech-savvy users can adopt without friction

### New Components

```
Features:
├── Onboarding for Non-Tech Users
│   ├── Invite link (one-click join)
│   ├── Guided setup (minimal steps)
│   ├── Large text mode (accessibility)
│   └── Help tooltips (inline guidance)
│
├── Simplified Interaction Modes
│   ├── Voice messages (primary for grandparents)
│   ├── Photo sharing (one-tap camera)
│   ├── Emoji reactions (low-friction responses)
│   └── Video messages (richer than text)
│
└── Multi-Device Support
    ├── Web (desktop for grandparents)
    ├── Mobile web (phone browser)
    └── PWA install (optional, feels like app)
```

### JTBD Validation

**JTBD #5: Multi-Generational Accessibility**
- Grandparent joins without tech support
- Grandparent sends voice message independently
- Grandparent sees grandkid photos same-day

**JTBD #2: Emotional Bonding (Extended)**
- Grandparent stays connected despite distance
- Kid shares moments with grandparent directly
- Multi-generational conversations flow naturally

**Metrics**:
- Grandparent adoption (joins successfully?)
- Grandparent engagement (weekly activity?)
- Independence (needs help or self-sufficient?)
- Preferred interaction mode (voice, photos, text?)

### Success Criteria
- [ ] Grandparent joins without help call
- [ ] Grandparent sends messages weekly
- [ ] Grandparent prefers this to phone calls/email
- [ ] Voice messages used more than text
- [ ] Family abandons group SMS entirely

### Blockers to Next Layer
- Grandparent can't onboard (too complex)
- Needs constant tech support (not accessible)
- Prefers phone calls (app not compelling)
- Confused by UI (too many features/options)

---

## Layer 4: Autonomy & Safety (Sprints 23-28)

**Users**: Parent + Spouse + Teen (13-17 years old)
**Goal**: Prove parent/teen autonomy balance works
**Hypothesis**: Transparent safety features build trust (JTBD #3 + #4)

### New Components

```
Data Model Additions:
├── Users
│   ├── date_of_birth (calculate age)
│   ├── autonomy_level (walled_garden | transition | trusted)
│   └── autonomy_override (manual parent adjustment)
│
├── Safe Zones
│   ├── family_id
│   ├── name (Home, School, etc.)
│   ├── geofence (lat, lng, radius)
│   └── notify_on_enter, notify_on_exit
│
└── Location Events
    ├── check_ins (manual "I'm here" updates)
    ├── etas (share route during transit)
    └── safe_zone_events (automatic alerts)

Features:
├── Age-Based Autonomy
│   ├── <10: Walled Garden (parent approves contacts)
│   ├── 10-13: Transition (parent notified of new contacts)
│   └── 14+: Trusted (full autonomy)
│
├── Location Awareness (NOT Tracking)
│   ├── Check-ins (one-tap "I'm here")
│   ├── Share ETA (route during transit, stops auto)
│   ├── Safe Zones (geofence alerts: entered/left)
│   └── Emergency SOS (broadcast live location)
│
├── Transparency Dashboard
│   ├── Current autonomy level (visible to teen + parent)
│   ├── Active safe zones (both see same info)
│   ├── Location sharing status (mutual visibility)
│   └── Contact permissions (who can communicate)
│
└── Reciprocal Visibility
    ├── Teen sees parent check-ins too
    ├── Parent shares location equally
    └── Mutual awareness, not unilateral control
```

### JTBD Validation

**JTBD #3: Safety & Peace of Mind**
- Parent knows teen arrived at school (safe zone alert)
- Teen shares ETA on way home (proactive update)
- Emergency SOS gives parent confidence

**JTBD #4: Teen Autonomy**
- Teen has private 1:1 (parent can't read)
- Teen manages own contacts (14+)
- Teen sees what parent sees (transparency, not surveillance)

**Metrics**:
- Safe zone alerts reduce "where are you?" texts
- Check-ins used proactively (not prompted by parent)
- Teen perceives as respectful (qualitative feedback)
- Parent anxiety reduced (qualitative feedback)
- Zero Life360-style tracking backlash

### Success Criteria
- [ ] Safe zones reduce "where are you?" texts by 80%
- [ ] Teen uses check-ins proactively (not prompted)
- [ ] Teen reports feeling trusted (not surveilled)
- [ ] Parent reports peace of mind (not anxiety)
- [ ] Transparency dashboard used weekly (both parties)

### Blockers to Next Layer
- Teen refuses to use (feels like surveillance)
- Parent wants more control (transparency insufficient)
- Geofencing unreliable (technical issues)
- Battery drain unacceptable (location kills phone)

---

## Layer 5: Trusted Network (Sprints 29-35)

**Users**: Your family + 2-3 trusted families (neighbors, close friends)
**Goal**: Prove family-to-family coordination works
**Hypothesis**: Limited trusted network solves coordination (JTBD #1 extended)

### New Components

```
Data Model Additions:
├── Family Connections
│   ├── family_id (your family)
│   ├── connected_family_id (trusted family)
│   ├── invited_by (admin who sent invite)
│   └── accepted_at
│
└── Conversations
    └── Type: network (shared channel between 2-3 families)

Features:
├── Family Invites
│   ├── Admin invites another family (mutual trust)
│   ├── Accept/reject invite
│   └── Limit: 3-5 families max (intentionally small)
│
├── Shared Channels
│   ├── Carpool coordination (logistics)
│   ├── Playdates (kid social coordination)
│   └── Neighborhood emergencies (mutual aid)
│
└── Bounded Scope
    ├── NOT a public bulletin board
    ├── NOT open neighborhood directory
    └── Curated, trusted relationships only
```

### JTBD Validation

**JTBD #1: Logistics Coordination (Extended)**
- Carpool: "Can you pick up my kid today?"
- Playdates: "Kids want to hang out Saturday?"
- Emergencies: "We're out of town, can you check on house?"

**Metrics**:
- Inter-family coordination events (weekly?)
- Replaces phone calls/texts to neighbors
- Families use for logistics vs social chat
- Network size stays small (3-5 families, not growth)

### Success Criteria
- [ ] Used for carpool coordination weekly
- [ ] Replaces phone calls to neighbors for logistics
- [ ] Network stays small (3-5 families, no growth pressure)
- [ ] No feature creep (no "add friend of friend")
- [ ] Families report stronger community ties

### Blockers to Next Layer
- Families don't coordinate this way (phone calls preferred)
- Network grows uncontrollably (privacy concerns)
- Feature creep (requests for friend-of-friend, public posts)
- Boundaries blur (work friends invited, not just neighbors)

---

## Layer 6: Cozy Differentiation (Sprints 36+)

**Users**: All previous layers validated
**Goal**: Prove "cozy" features create unique experience
**Hypothesis**: Slow, thoughtful features build deeper connections

### New Components

```
Features:
├── Slow Messaging
│   ├── Letters (artificial delay based on intent)
│   ├── "Arrives in 3 days" (simulates postal mail)
│   └── Anticipation vs instant gratification
│
├── Family Customization
│   ├── Custom themes (colors, fonts)
│   ├── Family logo/avatar
│   ├── Shared family "space" (Animal Crossing vibe)
│   └── Decorate together (collaborative customization)
│
├── Thoughtful Interactions
│   ├── No read receipts (reduce anxiety)
│   ├── No typing indicators (no urgency pressure)
│   ├── No "last seen" (no always-on expectation)
│   └── Optional "slow mode" (batched notifications)
│
└── Moments vs Messages
    ├── Daily highlights (curated moments, not chat stream)
    ├── Weekly family digest (reflection, not real-time)
    └── Memory preservation (archive, not ephemeral)
```

### JTBD Validation

**"Cozy" = Anti-Capitalist Digital Space**
- No engagement algorithms (no FOMO)
- No read receipts creating anxiety
- Slow features encourage thoughtfulness
- Customization fosters family identity

**Metrics**:
- Families use slow features voluntarily (not ignored)
- Customization creates unique family identity
- Users report lower anxiety vs WhatsApp/Slack
- Families describe it as "our space" (ownership)

### Success Criteria
- [ ] Slow features used (not skipped for instant)
- [ ] Families customize their space
- [ ] Users describe as "less stressful" than other apps
- [ ] Retention driven by "cozy" feel (not features)

---

## Dependency Graph

```
Layer 0: Foundation
    ↓ (technical validation)
Layer 1: Dyad (Parent + Spouse)
    ↓ (family messaging core)
Layer 2: Triad (+ Kid)
    ↓ (multi-gen group dynamics)
Layer 3: Extended Family (+ Grandparent)
    ↓ (accessibility validation)
    ├─→ Layer 4: Autonomy & Safety (Teen features)
    │       ↓ (privacy model proven)
    └─→ Layer 5: Trusted Network (Family-to-family)
            ↓ (coordination model proven)
Layer 6: Cozy Differentiation
```

**Critical Path**: 0 → 1 → 2 → 3 (Must validate in order)
**Parallel Paths**: Layer 4 and 5 can explore independently after Layer 3
**Optional**: Layer 6 features can be experimented with throughout

---

## Feature Matrix by Layer

| Feature | L0 | L1 | L2 | L3 | L4 | L5 | L6 |
|---------|----|----|----|----|----|----|-----|
| **Core Messaging** |
| Self-messages | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 1:1 messaging | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Family group chat | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Photo sharing | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Voice messages | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Video messages | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **Logistics** |
| Shared lists | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Simple calendar | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Quick polls | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Accessibility** |
| Web UI | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Large text mode | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Voice input | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Simplified UI | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Safety & Autonomy** |
| Age-based autonomy | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Check-ins | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Safe zones | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Share ETA | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Emergency SOS | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| Transparency dashboard | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Network** |
| Family invites | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Shared channels | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| **Cozy Features** |
| Slow messaging | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Custom themes | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Family space | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| No read receipts | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

---

## Technology Decisions by Layer

### Layer 0-3: Foundation Through Extended Family

**Stack:**
- Phoenix LiveView (web UI for dogfooding)
- **Server-side** Signal Protocol encryption (backend Rustler NIF + libsignal-client)
- PostgreSQL (local data)
- Self-hosted (Docker on homelab)

**Rationale:**
- Fastest iteration (single codebase, no separate client)
- Accessible (web URL, no app install needed)
- Server-side encryption aligns with LiveView architecture (server renders decrypted content)
- Self-hosted = you control backend (trust model: server has keys but you own server)
- Signal Protocol proves E2EE security model for families (2-6 people)
- Dogfood encrypted experience before committing to native app
- Validates core messaging hypothesis

**Encryption Approach:**
- **Sprint 8**: Authentication + LiveView UI (messages stored plaintext)
- **Sprint 9**: Signal Protocol implementation (3 weeks - Rust NIF, key mgmt, encryption)
- **Sprint 10**: Dogfood with encryption enabled (Layer 0 validation)

### Layer 4: Autonomy & Safety (Location Features)

**Decision Point: Native app needed?**

Location features (check-ins, safe zones, ETA sharing) likely require native mobile app for:
- Background geofencing (iOS/Android native APIs)
- Reliable location permissions
- Battery-efficient location tracking
- Push notifications for safe zone alerts

**Options to Evaluate (after Layer 3 validates LiveView UX)**:

**Option A: Capacitor wrapper (LiveView + native shell)**
- Pros: Reuse LiveView codebase, native APIs accessible via plugins
- Cons: App install required, app store deployment

**Option B: Native iOS/Android**
- Pros: Full native control, best performance
- Cons: Two codebases (iOS Swift + Android Kotlin), slower iteration

**Option C: Flutter**
- Pros: Single codebase for iOS/Android, good performance
- Cons: Rewrite UI layer, new framework to learn

**Option D: Continue LiveView + PWA**
- Pros: No app install, no rewrite
- Cons: Geofencing unreliable in browser, battery drain, permission UX poor

**Recommendation**: Defer decision until Layer 3 completion. If LiveView UX validates well, prefer Option A (Capacitor) for minimal rewrite.

### Layer 5-6: Trusted Network & Cozy Features

**Continue with proven stack:**
- If LiveView works for L0-3, continue for web UI
- If native app needed for L4, use same approach for L5-6
- Evaluate based on Layer 3 learnings and Layer 4 requirements

---

## Kill Criteria (When to Stop/Pivot)

### Layer 0 → 1
**Kill if:**
- Signal Protocol integration takes >5 weeks (too complex)
- Self-hosting too difficult (can't deploy to homelab)
- Performance <200ms unachievable
- LiveView UX feels clunky or slow

**Pivot to:**
- Alternative encryption (TLS + database encryption only, defer E2EE)
- Managed hosting (abandon self-hosted requirement)
- Consider native app if LiveView performance inadequate

### Layer 1 → 2
**Kill if:**
- You + wife don't use daily after 2 weeks (not compelling)
- Still using SMS/WhatsApp (didn't replace existing)
- UI feels clinical, not cozy (design hypothesis failed)

**Pivot to:**
- Re-examine "cozy" hypothesis (what's missing?)
- Consider if problem is real (maybe WhatsApp is fine?)

### Layer 2 → 3
**Kill if:**
- Kid doesn't engage (too complex or boring)
- Logistics tools unused (not natural workflow)
- Family still uses WhatsApp group (not compelling)

**Pivot to:**
- Simplify further (remove features, not add)
- Rethink logistics tools (wrong approach?)

### Layer 3 → 4/5
**Kill if:**
- Grandparent can't onboard (too complex)
- Needs constant tech support (not accessible)
- Prefers phone calls (app not compelling)

**Pivot to:**
- Redesign for elderly accessibility
- Voice-first interface (not text)
- Consider if multi-gen is achievable

### Layer 4 (Autonomy)
**Kill if:**
- Teen refuses to use (feels like surveillance)
- Parent wants more control (transparency insufficient)
- Geofencing unreliable (technical failure)

**Pivot to:**
- Reconsider trust model (too permissive or restrictive?)
- Abandon location features (messaging-only)

### Layer 5 (Trusted Network)
**Kill if:**
- Families don't coordinate this way (phone preferred)
- Network grows uncontrollably (privacy concerns)
- Boundaries blur (becomes general social network)

**Pivot to:**
- Abandon network features (family-only product)
- Accept limited scope (not a problem to solve)

---

## Success Metrics by Layer

| Layer | Primary Metric | Target | Timeframe |
|-------|----------------|--------|-----------|
| L0 | Technical validation | Deploy + encrypt message | 2 weeks |
| L1 | Daily active usage (both users) | 7+ consecutive days | 2 weeks |
| L2 | Logistics usage | 3+ shopping lists/week | 4 weeks |
| L3 | Grandparent independence | Join + message without help | 1 week |
| L4 | Check-in usage | 5+ proactive check-ins/week | 4 weeks |
| L5 | Inter-family coordination | 2+ coordination events/week | 4 weeks |
| L6 | Slow feature adoption | 50%+ use letters voluntarily | 8 weeks |

---

## Current Status

**Active Layer**: Layer 0 (Foundation)
**Sprint**: 7 (transitioning to 8)
**Next Milestones**:
- Sprint 8: Authentication + LiveView messaging UI (2 weeks)
- Sprint 9: Signal Protocol encryption implementation (3 weeks)
- Sprint 10: Layer 0 dogfooding with encryption enabled (2 weeks)

---

**Last Updated**: 2025-10-05
**Version**: 1.0
**Status**: Living document - updated as layers validate or pivot
