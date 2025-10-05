# Famichat Unified Documentation  


─────────────────────────────  
Table of Contents

1. Product Vision & Overview  
2. Architecture & Technical Design  
3. Feature Roadmap & Sprint Planning  
4. UI/UX & Design Guidelines  
5. Quality Assurance, Testing & Telemetry  
6. User Onboarding & Change Management  
7. Change Log & Revision History  

─────────────────────────────  
1. Product Vision & Overview

Purpose & Mission  
 • Famichat is a self–hosted, white–label communication platform designed for families that supports asynchronous text messages (letters), real–time video calls, and "cozy" ambient features reminiscent of games like Animal Crossing.  
 • It is built to be highly customizable—each family can tailor branding, language support (e.g., Japanese and English), cultural details (e.g., location–specific weather), and unique features.  
 • The platform prioritizes privacy, control over personal data, and secure, end–to–end communication.

Key Use Cases  
 • Personal Note–taking: Users can send messages to themselves.  
 • Family Communication: Direct messaging is allowed only if users share at least one common family.  
 • White–Label Deployment: Enables families to self–host and customize their instance without vendor lock–in.

High-Level Product Goals  
 • Validate a Docker–based Phoenix and Postgres backend with a minimal Flutter client.  
 • Lay a foundation for future enhancements—custom themes, real–time notifications via Phoenix Channels, and advanced messaging features.  

─────────────────────────────  
2. Architecture & Technical Design

Overall Architecture  
 • Backend: A Phoenix application running in Docker with a Postgres database.  
 • Frontend: A native iOS app with an additional Flutter client to support both mobile and desktop use.  
 • Deployment & Containerization: Docker-compose is used to launch the backend, with planned integrations for white–label deployments and extensible endpoints.

Core Modules & Services  
 a. Messaging & Conversation Services  
  – MessageService for sending and retrieving messages, with support for both direct and self–conversations.  
  – ConversationService to create new conversations, list user conversations, and enforce business rules (e.g., validating that two users share a family before starting a conversation).  

 b. Real–Time Functionality  
  – Phoenix Channels provide real–time notifications for new messages and conversation updates.

 c. Telemetry & Monitoring  
  – Key functions are instrumented using telemetry (e.g., :telemetry.span/3) to track performance metrics and support production monitoring via tools such as Prometheus and Grafana.

Security & Performance Considerations  
 • End–to–end encryption, prioritized error handling, and robust logging throughout the backend.  
 • Database indexing and caching strategies to support performance at scale.  
 • Containerization for easier deployment and scalability.

## 2.3 Conversation Types & Data Model

Our security model is built on a hybrid encryption approach:
+ - Client-Side End-to-End Encryption (E2EE): Message content is encrypted on user devices such that only intended 
recipients can decrypt the messages.
+ - Field-Level Encryption: Sensitive user data (e.g., email, phone numbers, authentication tokens) will be encrypted 
using libraries like Cloak.Ecto to ensure privacy while still supporting necessary queries.
+ - Infrastructure/Database Encryption: Database-level or disk encryption provides a blanket safeguard for all data 
at rest.
+
+Key Management:
+ - A dedicated key management system will handle secure key storage, automatic key rotation, and auditing.
+ - Telemetry instrumentation (using :telemetry.span/3 in critical operations) will monitor encryption tasks to 
ensure performance and detect anomalies.

### Conversation Types
Famichat implements distinct conversation types with clear boundaries:
- **`:self`** - Personal note-taking conversations (single user)
- **`:direct`** - One-to-one conversations between users (exactly 2 users)
- **`:group`** - Multi-user conversations (3+ users)
- **`:family`** - Special group for family-wide communication (all family members)

### Implementation Principles
- **Type Immutability**: Conversation types are immutable after creation
- **Specialized Creation**: Type-specific creation functions enforce appropriate validation
- **Concurrency Protection**: Race conditions handled via database constraints and serializable transactions
- **Role Management**: Group conversations track member roles (admin vs. member)
- **Data Preservation**: Conversations can be "hidden" by users but data is preserved

### Technical Implementation
- Separate changesets for creation vs. updating (enforcing type immutability)
- Unique constraints for direct conversations to prevent duplicates
- Transaction isolation for concurrent operations
- Metadata field supports type-specific attributes

These implementation decisions align with industry standards while supporting our specific product requirements for family communication.

### Channel Topics & Authorization
- Channel topics follow the format `message:<type>:<id>` (e.g., `message:direct:123`)
- Authorization rules are type-specific:
  - **`:self`**: Only the creator can access
  - **`:direct`**: Only the two participants can access
  - **`:group`**: Only active members can access
  - **`:family`**: All family members have access
- Channel join attempts by unauthorized users are rejected with appropriate error codes
- Telemetry events track authorization failures without exposing sensitive information

This structured approach to conversation types and channels simplifies client implementations and improves security by enforcing clear boundaries at the database, API, and channel levels.


## 2.5 Concurrency & Race Condition Handling

Famichat implements robust strategies to handle concurrent operations:

### Direct Conversation Creation
- Uses database-level constraints to prevent duplicate direct conversations
- Implements upsert operations with ON CONFLICT clauses to return existing conversations
- Uses serializable transaction isolation for critical operations

### Group Membership Management
- Tracks original members (esp. creators/admins) to handle ownership transitions
- Implements proper locking strategies for concurrent membership changes
- Ensures at least one admin remains in group conversations
- Handles the "last member leaves" scenario gracefully

### Message Delivery & Acknowledgements
- Implements client acknowledgement (ACK) mechanisms for critical messages
- Uses optimistic concurrency control with version fields where appropriate
- Tracks message delivery status at the database level

These strategies ensure data consistency and prevent common race conditions while maintaining application responsiveness.

─────────────────────────────  
## 2.2 Database Schema and Encryption Considerations
Our current migration files provide important insights into our data structure and future encryption needs:
 - **Users Table:** Initially created with a binary_id, unique username, role, and family_id. As we add sensitive fields (such as email and password_hash), these will be enhanced with field-level encryption and associated encryption metadata.
 - **Families Table:** Contains family names and settings. Depending on the sensitivity of the settings data, encryption may be applied to preserve family privacy.
 - **Conversations Table:** Designed to manage conversation metadata. This schema can be extended to include encryption flags or version identifiers, ensuring support for end-to-end encryption metadata.
 - **Messages Table:** The primary candidate for client-side E2EE. In the future, the 'content' field will store ciphertext, and additional columns (e.g., encryption version tags) may be added to facilitate secure message handling.

These schema considerations ensure that our database remains flexible and secure, supporting the seamless integration of advanced encryption features while maintaining performance and data integrity.

─────────────────────────────  
3. Feature Roadmap & Sprint Planning


## Completed Sprints  

**Sprint 1: Environment & Foundational Setup** ✓
**Sprint 2: Basic Messaging Functionality (Sending)** ✓
**Sprint 3: Direct Conversation Creation** ✓  
**Sprint 4: Message Retrieval & Conversation Listing** ✓  
**Sprint 5: Self–Messaging Support** ✓  
**Sprint 6: Telemetry Instrumentation** ✓  
**Sprint 6b: Encryption Foundation** ✓  


## Current Sprint Progress  

 Sprint 1: Environment & Foundational Setup  
 Outcome: Developers can spin up the basic application environment with Docker and view a "Hello World" page in the browser.

• Story 1.1: Create a basic Phoenix application that displays a "Hello World" page  
• Story 1.2: Write a docker-compose configuration to deploy the Phoenix application locally  
• Story 1.3: Add a Postgres container to the docker-compose file  
• Story 1.4: Validate that "docker-compose up" launches the application with no runtime errors  
• Story 1.5: Document local environment setup instructions for new developers

─────────────────────────────  
Sprint 2: Basic Messaging Functionality (Sending)  
Outcome: The Message schema and basic message–sending function are implemented and tested.

• Story 2.1: Create the Message schema and run migration  
• Story 2.2: Implement send_message(sender_id, conversation_id, content) in MessageService  
• Story 2.3: Write validation logic (e.g., presence of sender_id, conversation_id, content) in Message changeset  
• Story 2.4: Create unit tests for the send_message function's happy path  
• Story 2.5: Document the basic messaging API usage in internal docs

─────────────────────────────  
Sprint 3: Direct Conversation Creation  
Outcome: The platform supports creating a direct conversation between two users (with family–membership rules checked).

• Story 3.1: Create the Conversation schema and write migration files  
• Story 3.2: Create conversation_users join table with migration  
• Story 3.3: Implement create_direct_conversation(user1_id, user2_id) in ConversationService  
• Story 3.4: Write unit tests for direct conversation creation and duplicate–conversation handling  
• Story 3.5: Document the business rules for direct conversations (e.g., checking common family)

─────────────────────────────  
Sprint 4: Message Retrieval & Conversation Listing  
Outcome: The API can retrieve messages and list conversations, ensuring proper ordering and error handling.

• Story 4.1: Implement get_conversation_messages(conversation_id) in MessageService  
• Story 4.2: Write unit tests for message retrieval (successful, empty, and non–existent conversation cases)  
• Story 4.3: Implement list_user_conversations(user_id) in ConversationService  
• Story 4.4: Write tests for listing user conversations (including users with no conversations)  
• Story 4.5: Update API documentation to reflect retrieval and listing endpoints

─────────────────────────────  
Sprint 5: Self–Messaging Support  
Outcome: The system now supports self–conversations, letting users message themselves as a notepad.

• Story 5.1: Update the Conversation schema to include a conversation_type (direct vs. self)  
• Story 5.2: Implement create_self_conversation(user_id) in ConversationService  
• Story 5.3: Update send_message to support self–conversations (if necessary)  
• Story 5.4: Write unit tests for self–messaging (ensuring only one participant is linked)  
• Story 5.5: Document self–messaging requirements and usage

─────────────────────────────  
Sprint 6: Telemetry Instrumentation & Performance Metrics  
Outcome: Key endpoints are instrumented and performance data flows are established.

• Story 6.1: Add telemetry instrumentation (using :telemetry.span/3) to send_message  
• Story 6.2: Add telemetry instrumentation to get_conversation_messages  
• Story 6.3: Write tests or logs to verify telemetry events are emitted correctly  
• Story 6.4: Document the telemetry event naming convention and associated metrics  
• Story 6.5: Configure Prometheus/Grafana (or a stub) to receive and display telemetry data for key endpoints

─────────────────────────────  
Sprint 6b: Encryption Foundation (SPIKE!)
Outcome: Core cryptographic patterns established and ready for E2EE implementation.

• Story 6b.1: Design encrypted message storage format  
• Story 6b.2: Implement key management service skeleton  
• Story 6b.3: Establish protocol for device trust verification  
• Story 6b.4: Create key rotation scaffolding  
• Story 6b.5: Document crypto architecture decisions  

─────────────────────────────  
Sprint 7: Real–Time Messaging Integration  
Outcome: New messages and conversation updates are broadcast in real time via Phoenix Channels.

• Story 7.1: Set up basic Phoenix Channels to broadcast new message events  
• Story 7.2: Write unit / integration tests to verify that new messages trigger channel events  
• Story 7.3: Document the process for subscribing to channels and the API for live updates  
• Story 7.4: Create a simple UI hook (dummy route/component) that consumes real–time events  
• Story 7.5: Verify real–time notifications with a manual test and log results  
• Story 7.6: Add encryption-aware message serialization/deserialization hooks

─────────────────────────────  
Sprint 8: Flutter Client – Messaging UI & Integration  
Outcome: The Flutter client can fetch and display messages from the backend.

• Story 8.1: Implement basic chat UI components in the Flutter client to display messages  
• Story 8.2: Integrate a simple state management pattern (e.g., Provider or Bloc) for messaging  
• Story 8.3: Connect the Flutter client to call the messaging retrieval endpoints  
• Story 8.4: Write an integration test (or use manual testing steps) to verify messaging flow  
• Story 8.5: Document the API endpoints used by the Flutter client, including sample responses

─────────────────────────────  
Sprint 9: Design System Integration & White–Label Preparation  
Outcome: Families can customize their interface with theme switching and basic white–label configurations.

• Story 9.1: Integrate design tokens into the application UI components  
• Story 9.2: Add theme switching support in the Flutter client  
• Story 9.3: Build a backend endpoint to serve theme configuration data  
• Story 9.4: Write tests to verify that the theme endpoint returns valid configuration  
• Story 9.5: Update documentation for white–label customization options

─────────────────────────────  
Sprint 10: Security & Performance Enhancements  
Outcome: Full Signal Protocol implementation with X3DH/Double Ratchet.

• Story 10.1: Implement X3DH key exchange protocol  
• Story 10.2: Add Double Ratchet message encryption  
• Story 10.3: Create key rotation system  
• Story 10.4: Implement encrypted message payload handling  
• Story 10.5: Develop key recovery/backup mechanism  

─────────────────────────────  
Sprint 11: Code Quality, Error Handling & Documentation Refinement  
Outcome: All modules are refined, tests pass, and the documentation is fully updated and comprehensive.

• Story 11.1: Fix any remaining failing tests across Message and Conversation services  
• Story 11.2: Enhance error handling in all service functions (adding additional checks/logging)  
• Story 11.3: Review and refactor inline documentation (@doc annotations) throughout the code  
• Story 11.4: Update the unified documentation with any recent changes and new endpoints  
• Story 11.5: Validate via a team code review that all acceptance criteria have been met

─────────────────────────────  
Sprint 12: Onboarding & Final End–to–End Testing  
Outcome: New users experience a polished onboarding workflow and the end–to–end system functions for production.

• Story 12.1: Design the onboarding screen layout for account creation (iOS and Flutter)  
• Story 12.2: Implement the onboarding flow in the iOS app (including profile setup)  
• Story 12.3: Develop an experimental "phone bump" detection using Apple's Nearby Interaction  
• Story 12.4: Collect feedback from a small user test group and iterate on onboarding flows  
• Story 12.5: Execute end–to–end system tests (Docker deployment, integrated backend–Flutter flow) and update final release documentation

─────────────────────────────  
Sprint 13: Final Polish & Release Readiness  
Outcome: The product is stabilized, monitored end-to-end, and fully documented for production rollout.

• Story 13.1: Implement comprehensive end–to–end tests that span all core functionalities  
• Story 13.2: Verify integration between Docker deployment, Telemetry, and live channels  
• Story 13.3: Finalize test coverage reports (aiming for ≥95% on new/modified code)  
• Story 13.4: Update the final change log and user release notes  
• Story 13.5: Conduct a final team code review and sign off on the release

─────────────────────────────  
Notes

• Although each story is 1 point, they are defined in such a way that their cumulative effect in a 2–week sprint yields a clear, measurable outcome.  
• This breakdown covers core backend, real–time messaging, frontend integration, customization, security, and onboarding. Additional one–point stories can be added for further refinements or any backlog items not listed here.  
• Regular refinement sessions will help ensure that "legacy" items or emerging requirements are converted into new one–point stories for upcoming sprints.


─────────────────────────────  
4. UI/UX & Design Guidelines

Product Aesthetic & Customization  
 • The visual identity is "family–centric" with custom branding and easily switched themes.  
 • Administrators have the ability to upload custom icons, colors, and overall look–and–feel for their family instance.

Information Architecture (IA) with Bottom Tab Navigation  
 a. Letters (Default Overview Screen)  
  – Inbox displaying a list of letters (messages), each styled with sender avatars, timestamps, preview snippets, and unread indicators.  
  – "Write a Letter" action is prominently displayed.  
 b. Calls  
  – Call history and an option to start a new call with quick access to family members' status.  
 c. Family Space  
  – A dedicated area for shared calendars, photo albums, and cozy community features.  
 d. Search  
  – A search bar at the top with relevant filters to quickly locate past messages, media, or shared content.  
 e. Profile  
  – User and family settings (including language selection, notification preferences, and admin–only controls for user management and aesthetic customization).

Letters Inbox Screen – Detailed Layout  
 • App Header: Displays a family crest/icon, a personalized title (e.g., "[Family Name] Home"), and a "Write a Letter" action button.  
 • Main Content: A scrollable list of letters presented in chronological order, with elements such as sender avatar, sender name, message preview, timestamp, and media indicator if applicable.  
 • Empty State: Friendly placeholder messaging prompting the user to write a letter if the inbox is empty.

Cozy features:
- "fingers touching" adds a to merge families, where one family can merge with another by touching a spot on the UI at the same time where it vibrates.
- "phone bumping" adds a to merge families, where one family can merge with another by touching a spot on the UI at the same time where it vibrates.
- "ambient tracing" lets users sketch across the other persons visible area, as a sort of shared canvas or sketchbook (per day? per week?)

─────────────────────────────  
5. Quality Assurance, Testing & Telemetry

Quality Assurance & Testing Approach  
 • Comprehensive unit and integration testing for all service modules.  
 • Regular code reviews to ensure readability, adherence to best practices, and that all validation logic is correctly implemented.  
 • Peer reviews and automated static analysis (using tools like Credo, Sobelow) to flag potential issues before merge.

Telemetry Guidelines & Best Practices  
 • Instrument critical functions (e.g., message retrieval, conversation creation) using :telemetry.span/3 and :telemetry.execute/3.  
 • Follow event naming convention: [:famichat, :context, :action] (e.g., [:famichat, :message, :sent]).  
 • Set performance budgets (e.g., 200ms for message retrieval endpoints).  
 • Export telemetry metrics to monitoring tools (Prometheus/Grafana) for live tracking, facilitating rapid detection of performance degradations.
 • Validate that every new endpoint or modified function includes telemetry hooks to support both development and production monitoring.

Acceptance Criteria  
 • Consistent API responses (e.g., {:ok, entity} or {:error, reason}).  
 • All new functionalities are verified against defined acceptance tests and meet the performance budget before deployment.

**Encryption-Specific Testing Strategy**  
 • All tests must validate encryption/decryption cycles  
 • Negative testing for tampered ciphertext detection  
 • Performance testing for crypto operations under load  

─────────────────────────────  
6. User Onboarding & Change Management

Onboarding Experience Overview  
 • The onboarding flow is designed to be intuitive and family–focused.  
 • Key steps include account creation, profile setup, and guided tour of key features (Letters inbox, Calls, Family Space).  
 • Supplemental features, such as "phone bumping," are investigated to offer a cool, frictionless way to add contacts. "fingers touching" adds a to merge families, where one family can merge with another by touching a spot on the UI at the same time where it vibrates.

Onboarding Flow & Innovations  
 • Explore iOS Native Nearby Interaction for "phone bump" onboarding.  
 • If cross–platform compatibility is needed, experimental investigations into high–frequency audio or Bluetooth–based proximity detection may be conducted.  
 • Prototyping will be undertaken along with user testing—a key input for refining the onboarding experience.

Change Management & Documentation Updates  
 • Keep a dedicated change log with version numbers and "last updated" timestamps to flag revisions.  
 • Clearly annotate sections that have legacy content versus new, approved guidelines.  
 • Schedule periodic documentation reviews to reconcile any conflicting or outdated information, ensuring that the team always has access to the most current implementation details.

─────────────────────────────  
7. Change Log & Revision History

 Version 1.0 (Initial Unified Documentation)  
  – Consolidated key documents from project planning, sprint details, design guidelines, and onboarding into a single reference.  
  – Establishment of core sections and acceptance criteria according to current sprint plans and product vision.
 
 Version 1.1 (January 25, 2024 Update)  
  – Updated sprint dates and task statuses.  
  – Expanded Telemetry, QA, and UI/UX sections based on recent reviews and team feedback.
 
+Version 1.2 (February 14, 2024 Update) ✓  
+ – Completed Sprints 3-6: Conversation services, message retrieval, self-messaging, and telemetry  
+ – Standardized API response format across all services  
+ – Updated testing strategy documentation  
+ – Verified end-to-end functionality through updated test suite  
+ – Added API Design Principles section
+
+Version 1.3 (Proposed Encryption Update)  
+ – Integrated E2EE roadmap into sprint planning  
+ – Added security testing requirements  
+ – Updated telemetry guidelines for crypto operations

Version 1.4 (June 14, 2025 Update)
  – Updated Lefthook configuration in `.lefthook.yml` (stricter pre-push hook, corrected `wait_for_web` port to 8001). Added VS Code DevContainer configuration (`.devcontainer/devcontainer.json`). Corrected date in `project-docs/telemetry.md`.
 
 ─────────────────────────────  
 Final Notes

• This unified document is intended as a living guide for the Famichat project. Products, processes, and requirements are subject to change.  
• Team members should refer to the appropriate section for details relevant to their role while cross–referencing the sprint roadmap for current priorities.  
• Regular audits and reviews will help ensure this document remains error–free and fully aligned with evolving project requirements.

## Open Questions

This section contains topics that require further discussion and exploration in future sprints and technical reviews.

### Topics to Explore:
 - How should we handle membership updates in group chats? Should a change in membership result in a new conversation, or should the existing conversation be updated?
 - What additional business and UX rules should govern the creation and management of direct and group chats to prevent duplication and confusion?
 - What are the best strategies to monitor and enforce security policies related to computed keys and metadata protection without impacting performance?
 - Are there alternative mechanisms for enforcing conversation uniqueness that might better accommodate dynamic participant lists in evolving product requirements?
 - How can we better integrate this discussion with our encryption and key management strategy, ensuring that our computed key approach scales securely with changes?

Please add any new questions or considerations as research and product requirements evolve.



## API Design Principles (Updated)

### Uniform Response Format
All service functions now return simple status tuples to simplify client handling:
```elixir
{:ok, result} | {:error, reason}
```
**Key Benefits:**
- Predictable pattern matching in controllers and clients
- Clear separation of business logic from telemetry instrumentation
- Reduced cognitive overhead for developers

### Telemetry Integration
- Metrics emission handled through dedicated `:telemetry` calls
- No metadata mixed with business logic returns
- Span measurements captured internally using `:telemetry.span/3`

### Testing Strategy Updates
- Tests now verify core functionality without telemetry coupling
- Telemetry-specific verification done through event listeners
- Example pattern:
  ```elixir
  {:ok, conv} = ConversationService.create(...)
  assert conv.property == expected_value
  ```

**Related Documents:**
- [Telemetry Implementation Guidelines](./telemetry.md)
- [Feature Completion Criteria](./done.md)