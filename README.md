# Famichat

Secure, Self-Hosted Family Communication Platform

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Project Status: Alpha](https://img.shields.io/badge/Project%20Status-Alpha-orange)](https://en.wikipedia.org/wiki/Software_release_life_cycle#Alpha)

**A self-hosted, white-label video and chat application designed to create a secure and intimate digital space for families.**

## 🚦 Project Status (2025-10-05)

**Phase**: Alpha Development
**Progress**: ████████░░░░░░░░░░░░ 40% to MVP
**Current Sprint**: Sprint 7 - Real-Time Messaging (30% complete)

### Quick Health Check
- ✅ **Backend Core**: 60% complete (messaging works, auth missing)
- ⚠️ **Frontend**: 5% complete (proof-of-concept only)
- ✅ **Infrastructure**: 50% complete (dev ready, prod missing)
- 🚨 **Critical Blocker**: No authentication system

## 📍 Navigation

### Daily Work
- 🎯 **[STATUS.md](STATUS.md)** - Comprehensive current state (**READ THIS FOR DETAILED STATUS**)
- 📋 **[CURRENT-SPRINT.md](CURRENT-SPRINT.md)** - Sprint 7 tasks (**YOUR DAILY FILE**)
- 🗓️ **[ROADMAP.md](ROADMAP.md)** - Timeline & sprint history

### Development
- 🏗️ **[backend/README.md](backend/README.md)** - Backend setup & commands
- 📚 **[backend/guides/](backend/guides/)** - Technical implementation guides
  - [Messaging Implementation](backend/guides/messaging-implementation.md)
  - [Telemetry & Performance](backend/guides/telemetry.md)
  - [Conversation Types](backend/guides/overview.md)

### Deep Dives
- 🏛️ **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System design decisions
- 🎯 **[docs/VISION.md](docs/VISION.md)** - Product vision & goals
- 🔐 **[docs/ENCRYPTION.md](docs/ENCRYPTION.md)** - Security architecture
- ⚡ **[docs/PERFORMANCE.md](docs/PERFORMANCE.md)** - Performance budgets & optimization
- 📊 **[docs/API-DESIGN.md](docs/API-DESIGN.md)** - API principles & patterns
- ❓ **[docs/OPEN-QUESTIONS.md](docs/OPEN-QUESTIONS.md)** - Unresolved architectural decisions
- 🎨 **[docs/design/](docs/design/)** - UI/UX specifications
- 📝 **[docs/decisions/](docs/decisions/)** - Architecture Decision Records (ADRs)

## 🚀 Quick Start

```bash
# Start backend
cd backend && docker-compose up

# Run tests
cd backend && ./run mix test

# Check current sprint tasks
cat CURRENT-SPRINT.md
```

## 📊 Key Metrics (Latest)

- **Tests**: 98/98 passing ✅
- **Coverage**: Unknown (needs measurement)
- **Backend files**: 49 Elixir modules
- **Migrations**: 9 applied
- **Performance**: All operations < 200ms budget ✅

## 🎯 What Works vs What Doesn't

### ✅ Working
- Text messaging (send/retrieve with pagination)
- Conversations (direct, self, group with role management)
- Real-time channels (Phoenix Channels configured)
- Telemetry & monitoring (all critical paths instrumented)
- Conversation hiding/visibility management

### ❌ Missing (Critical Blockers)
- **User authentication** (CRITICAL - no login/registration!)
- **Flutter client** (WebSocket integration missing)
- **E2E encryption** (infrastructure ready, not implemented)
- **Production deployment** (no prod config)

### 🚧 In Progress (Sprint 7)
- Channel routing & authorization
- Broadcast testing
- Client integration documentation
- Encryption serialization tests

## 📚 Documentation Structure

```
/
├── README.md                    # ← You are here
├── STATUS.md                    # Detailed current state
├── CURRENT-SPRINT.md            # Active sprint tasks
├── ROADMAP.md                   # Sprint timeline
│
├── /backend/
│   ├── README.md               # Backend setup (see below for quick commands)
│   └── /guides/                # Technical implementation guides
│       ├── messaging-implementation.md
│       ├── telemetry.md
│       └── overview.md
│
├── /docs/
│   ├── ARCHITECTURE.md         # System design
│   ├── VISION.md               # Product vision
│   ├── API-DESIGN.md           # API patterns
│   ├── ENCRYPTION.md           # Security model
│   ├── PERFORMANCE.md          # Performance budgets & optimization
│   ├── OPEN-QUESTIONS.md       # Unresolved architectural decisions
│   │
│   ├── /design/                # UI/UX specs
│   │   ├── information-architecture.md
│   │   └── onboarding-flows.md
│   │
│   ├── /decisions/             # Architecture Decision Records
│   │   ├── 001-conversation-types.md
│   │   ├── 002-encryption-approach.md
│   │   ├── 003-telemetry-strategy.md
│   │   ├── 004-refresh-token-rotation.md
│   │   └── 005-encryption-metadata-schema.md
│   │
│   └── /sprints/               # Sprint archive
│       ├── sprints-01-02-foundation.md
│       └── sprints-03-06-messaging.md
│
└── /project-docs/archive/      # Historical docs
```

## 🏗️ Tech Stack

- **Backend**: Phoenix 1.7, Elixir 1.13+
- **Database**: PostgreSQL 16
- **Real-time**: Phoenix Channels (WebSocket)
- **Frontend**: Flutter (iOS, Web planned)
- **Infrastructure**: Docker, Docker Compose
- **Quality**: Credo, Sobelow, Dialyzer, ExCoveralls

## 🎯 Current Focus

**This Week**:
1. Complete Sprint 7 channel authorization (Story 7.1.3)
2. Start Accounts context (Story 7.9) - CRITICAL for auth
3. Measure test coverage

**Next Sprint**:
- Build Flutter WebSocket client
- Implement basic authentication
- Create messaging UI

## 📖 Getting Started Guide

### Prerequisites
- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/)
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (latest stable version)
- [Lefthook](https://github.com/evilmartians/lefthook) for Git hooks management

### Setup Steps

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-user/famichat.git
   cd famichat
   ```

2. **Set up Lefthook for Git hooks:**
   ```bash
   # Download for your platform from: https://github.com/evilmartians/lefthook/releases
   # Initialize in the repository
   lefthook install
   ```

3. **Start the Docker containers:**
   ```bash
   docker-compose up --build
   ```

4. **Verify the Backend:**
   Open [http://localhost:8001](http://localhost:8001) - should see "Hello from Famichat!"

### Development Commands

**Backend (Phoenix/Elixir)**:
```bash
cd backend

./run mix test              # Run tests
./run iex -S mix           # Interactive console
./run mix format           # Format code
./run mix credo            # Code analysis
./run mix ecto.migrate     # Run migrations
```

**Frontend (Flutter)**:
```bash
cd flutter/famichat

flutter pub get            # Get dependencies
flutter run -d chrome      # Run in browser
flutter run                # Run on device
flutter test               # Run tests
```

### Git Hooks (Lefthook)

- **Pre-commit**: Starts Docker, waits for services, formats staged files
- **Pre-push**: Runs format checks, linting, tests (allows push even if fails)
- **Configuration**: See `.lefthook.yml` files

## 🏛️ Architecture Overview

```
+---------------------+      WebSocket/Phoenix Channels     +---------------------+
| Flutter Client App  | <-----------------------------------> | Phoenix Backend     |
+---------------------+                                     +---------------------+
      |                                                         |
      | UI, State Mgmt, WebRTC                                  | Controllers, Channels,
      | WebRTC Signaling                                        | Services, Telemetry
      v                                                         v
+---------------------+                                     +---------------------+
| Rich Media (Local  |                                      | PostgreSQL Database |
| Caching, Playback) |                                      +---------------------+
+---------------------+                                          ^
                                                                 | (Metadata, Text, Media Refs)
                                                                 |
                                                         +---------------------+
                                                         | Object Storage      |
                                                         | AWS S3, MinIO, etc. |
                                                         +---------------------+
                                                                 ^
                                                                 | (Rich Media)
                                                                 |
                                                         +---------------------+
                                                         | TURN/STUN Servers   |
                                                         | (for WebRTC)        |
                                                         +---------------------+
```

## 📖 Additional Resources

- **Detailed Status**: See [STATUS.md](STATUS.md) for comprehensive implementation status
- **API Documentation**: Run `mix docs` in backend/ directory
- **Sprint Planning**: See [ROADMAP.md](ROADMAP.md) for timeline
- **Architecture Decisions**: See [docs/decisions/](docs/decisions/) for ADRs
- **Design Specs**: See [docs/design/](docs/design/) for UI/UX documentation

---

**Last Updated**: 2025-10-05
**License**: MIT
**Status**: Alpha - Not production ready
