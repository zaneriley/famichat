# Sprint 7: Real–Time Messaging Integration

## TDD Methodology

For each story in this sprint, follow these TDD steps:
1. **Red:** Write failing tests that capture the expected behavior.
2. **Green:** Implement the minimal code needed to make the tests pass.
3. **Verification:** Run all tests, lint checks, security checks, and static analysis to ensure the new code meets quality standards.
4. **Final Review:** Once tests pass and subtasks are verified, mark off the corresponding story's checkbox in this document.

This sprint focuses on integrating real–time messaging using Phoenix Channels, including testing, documentation, and adding hooks for encryption-aware message handling.

## Domain Model Refinement

Based on industry standards and application requirements, we've refined our conversation type boundaries:

### Conversation Types
- `:self` - Personal note-taking conversations (single user)
- `:direct` - One-to-one conversations between users (exactly 2 users)
- `:group` - Multi-user conversations (3+ users)
- `:family` - Special group for family-wide communication (all family members)

### Implementation Guidelines
- Conversation types are **immutable** after creation
- Type-specific creation functions enforce appropriate validation
- Race conditions handled via database constraints and serializable transactions
- Group membership includes role tracking (admin vs member)
- Conversations can be "hidden" by users but data is preserved
- Security model balances E2EE requirements with implementation practicality

These refinements align with industry standards while supporting our specific product requirements.

## Information Architecture Analysis

### Mental Models & User Experience

We've analyzed both user expectations and industry patterns to ensure our conversation type boundaries align with established mental models:

| Type | User's Mental Model | Expected Behavior |
|------|---------------------|-------------------|
| Self | "Notes to myself" | Private, persistent, no sharing options |
| Direct | "Private conversation with one person" | 1:1, private, cannot add others |
| Group | "Conversation with multiple people" | Multiple participants, roles, can add/remove people |
| Family | "Everyone in my family" | All family members included, possibly special status |

Breaking these established boundaries (e.g., allowing direct messages to transform into group chats) creates cognitive friction and potential privacy/security concerns. Our implementation maintains clear separation between types to preserve user trust and simplify authorization models.

### Schema Design Considerations

For tracking group membership with role information, we evaluated several schema design approaches:

1. **Enhanced ConversationParticipant**: Adding role fields to the existing join table
   - *Pros*: Simpler structure, fewer tables
   - *Cons*: Risks overloading the basic join model, less explicit

2. **Dedicated GroupConversationPrivileges schema**: A separate schema focused on roles/privileges
   - *Pros*: Clear separation of concerns, explicit permission model, audit capabilities
   - *Cons*: Additional table and relationships to maintain
   
After analysis, we chose option 2 with the name `group_conversation_privileges` to maintain clear boundaries between basic participation tracking and privilege/role management. This aligns with our DDD approach of making domain concepts explicit in the schema design.

### API Design Clarity

Our implementation uses type-specific creation functions rather than a generic approach:

```elixir
# Instead of generic create_conversation:
Chat.create_direct_conversation(user1_id, user2_id)
Chat.create_self_conversation(user_id)
Chat.create_group_conversation(creator_id, name, initial_member_ids)
Chat.create_family_conversation(creator_id)
```

This provides clearer intent, more predictable validation, and a better developer experience.

## Stories

### Story 7.1: Phoenix Channel Setup
- [x] **7.1.1:** Write failing tests for the Phoenix Channel module
  - [x] **Subtask:** Write test that simulates a channel join with an invalid token (expect failure).
  - [x] **Subtask:** Write test that simulates a channel join with a valid token (expect success).
  - [x] **Subtask:** Write test that verifies telemetry events are emitted for channel joins.
  - [x] **Subtask:** Run the tests to verify they fail as expected:
    ```bash
    cd backend && ./run elixir:test test/famichat_web/channels/message_channel_test.exs
    ```
- [x] **7.1.2:** Implement a basic Phoenix Channel module (e.g., `MessageChannel`) with `join/3` and `handle_in/3` callbacks.
  - [x] **Subtask:** Ensure the module and functions include proper inline documentation and module docstrings.
  - [x] **Subtask:** Verify code quality by running:
    - `cd backend && ./run elixir:lint`
    - `cd backend && ./run elixir:format:check`
  - [x] **Subtask:** Run a security check by executing:
    - `cd backend && ./run elixir:security-check`
  - [x] **Subtask:** Run static analysis and verify typespecs by executing:
    - `cd backend && ./run elixir:static-analysis`
  - [x] **Subtask (New):** Implement minimal token-based authentication for channel joins; verify with tests and security checks:
    - `cd backend && ./run elixir:lint`
    - `cd backend && ./run elixir:security-check`
  
- [ ] **7.1.3:** Configure the channel in the socket and backend routing; verify via IEx (using `Endpoint.broadcast!/3`) that dummy messages broadcast correctly.
  - [ ] **Subtask:** Configure conversation-type-aware topic formats (`message:<type>:<id>`) in channel routes
  - [ ] **Subtask:** Implement proper authorization checks based on conversation type
  - [ ] **Subtask:** Run `cd backend && ./run elixir:lint` and verify there are no issues.
  - [ ] **Subtask:** Run security check (`cd backend && ./run elixir:security-check`) and static analysis (`cd backend && ./run elixir:static-analysis`) to validate changes.
  - [ ] **Subtask (New):** Integrate basic telemetry instrumentation for channel join and broadcast events and verify via logs/telemetry dashboards.
    - **Expected Test:** Write tests that simulate channel join and message broadcast events; verify that telemetry events are emitted (e.g., check for expected event names and payloads in the test logs).
    - 
- [ ] **7.1.4:** Enhance channel join tests to validate that encryption-aware telemetry events are emitted and that no sensitive encryption metadata is leaked during failed channel joins.
- [ ] **7.1.4:** Write tests to verify encryption-aware telemetry for channel joins:
  - [ ] **Subtask:** Assert that failed channel join telemetry events contain NO encryption metadata fields (key_id, encryption_flag, encryption_version).
  - [ ] **Subtask:** Assert that successful channel join telemetry events include ONLY an 'encryption_status' field with value 'enabled' or 'disabled'.
  - [ ] **Subtask:** Run the test suite and verify both assertions fail before implementation:
    ```bash
    cd backend && ./run elixir:test test/famichat_web/channels/message_channel_test.exs:45-65
    ```
- **Final Review 7.1:** Once all subtasks for Story 7.1 have been completed and verified, mark off the Story 7.1 checkbox in this Sprint7.md file.

### Story 7.2: Testing Channel Broadcasts
- [ ] **7.2.1:** Write unit tests to simulate message sending and assert correct event broadcasting within the channel.
  - [ ] **Subtask:** Ensure tests are properly documented and include comments.
  - [ ] **Subtask:** Validate by running:
    - `cd backend && ./run elixir:lint`
    - `cd backend && ./run elixir:test`
  - [ ] **Subtask:** Run security check and static analysis:
    - `cd backend && ./run elixir:security-check`
    - `cd backend && ./run elixir:static-analysis`
  - **Expected Test:** When simulating a message send, the unit test should verify that:
      - The channel broadcasts the event with a payload that matches expected (including any encryption-aware fields, if stubbed).
- [ ] **7.2.2:** Write integration tests (using `Phoenix.ChannelTest`) to simulate a WebSocket client subscribing to the channel and verify event reception.
  - [ ] **Subtask:** Ensure test files adhere to code style and include inline documentation.
  - [ ] **Subtask:** Verify tests via lint and test runs as mentioned above.
  - [ ] **Subtask:** Run security and static checks:
    - `cd backend && ./run elixir:security-check`
    - `cd backend && ./run elixir:static-analysis`
- **Final Review 7.2:** Once all subtassks for Story 7.2 have been completed and verified, mark off the Story 7.2 checkbox in this Sprint7.md file.

### Story 7.3: Documentation for Channels and API
- [ ] **7.3.1:** Document the channel subscription process for client integration using sample code, curl commands, or IEx examples.
  - [ ] **Subtask:** Document conversation type boundaries and their implications for channel subscriptions
  - [ ] **Subtask:** Explain how conversation types affect authorization and message handling
  - [ ] **Subtask:** Update the related documentation files (e.g., README, developer docs) and ensure the content is well formatted.
- [ ] **7.3.2:** Document the API for live updates (list event names, payload formats, and client expectations).
  - [ ] **Subtask:** Incorporate examples within the documentation and verify consistency.
  - [ ] **Subtask (New):** Document the encryption-aware payload structure (including version tags and key IDs) for future E2EE integration.
  - [ ] **Subtask (New):** Document known mobile background handling limitations (e.g., iOS/Android constraints).
  - **Expected Documentation Test:** Include an example payload in the docs that shows the encryption-aware structure (e.g., version tags, key IDs) and clearly note mobile background limitations.
- **Final Review 7.3:** Once all subtasks for Story 7.3 have been completed and verified, mark off the Story 7.3 checkbox in this Sprint7.md file.

### Story 7.4: Creating a UI Hook / CLI Testing Endpoint
- [ ] **7.4.1:** Implement a dummy UI route or LiveView component that connects to the channel and displays incoming events.
  - [ ] **Subtask:** Ensure the new component includes proper module-level documentation and inline comments.
  - [ ] **Subtask:** Run:
    - `cd backend && ./run elixir:lint`
    - `cd backend && ./run elixir:format:check`
  - [ ] **Subtask:** Run security check and static analysis:
    - `cd backend && ./run elixir:security-check`
    - `cd backend && ./run elixir:static-analysis`
- [ ] **7.4.2:** Create a CLI testing endpoint (e.g., via a simple controller action) to trigger test broadcasts that can be verified using curl.
  - [ ] **Subtask:** Update the controller code with appropriate documentation.
  - [ ] **Subtask:** Verify code style using the provided run commands.
  - [ ] **Subtask:** Run security checks and static analysis to ensure the controller changes are robust.
  - **Expected Test:** A curl command against the endpoint should trigger an event, with output verified either via logs or by a test client receiving a broadcast.
- **Final Review 7.4:** Once all subtasks for Story 7.4 have been completed and verified, mark off the Story 7.4 checkbox in this Sprint7.md file.

### Story 7.5: Verification of Real–Time Notifications
- [ ] **7.5.1:** Develop and run a manual test script (or use an IEx command) to trigger channel events; log and verify the complete end-to-end notification flow.
  - [ ] **Subtask:** Document the manual test process and keep a record of output logs.
  - [ ] **Subtask:** Run security check and static analysis after implementing test scripts:
    - `cd backend && ./run elixir:security-check`
    - `cd backend && ./run elixir:static-analysis`
  - **Expected Test:** The manual test should show that triggering a channel event (e.g., a dummy broadcast) logs the expected output and that a connected test client receives the event.
- [ ] **7.5.2:** Automate logging of broadcast event details and integrate assertions in existing tests.
  - [ ] **Subtask:** Ensure updated tests are well documented and pass linting/formatting checks.
  - [ ] **Subtask:** Run final security and static analysis validations.
  - [ ] **Subtask (New):** Implement a basic client ACK mechanism for critical message events; verify functionality via IEx and test suites.
  - **Expected Test:** Write a test that simulates a client sending an ACK upon receiving a message; the system should log or register the ACK, which the test then verifies.
- **Final Review 7.5:** Once all subtasks for Story 7.5 have been completed and verified, mark off the Story 7.5 checkbox in this Sprint7.md file.

### Story 7.6: Encryption-Aware Message Serialization/Deserialization
- [ ] **7.6.1:** Implement a placeholder for adding encryption metadata (e.g., key IDs, encryption flags) to the message serialization function.
  - [ ] **Subtask:** Define conversation-type-specific encryption requirements
  - [ ] **Subtask:** Implement configuration-based encryption policy enforcement
  - [ ] **Subtask:** Write failing tests for message serialization that verify required encryption metadata
- [ ] **7.6.2:** Write tests that verify messages with the new encryption-aware serialization and deserialization hooks preserve the extra metadata.
- [ ] **7.6.2:** Write failing tests for encryption error handling:
  - [ ] **Subtask:** Assert decryption of malformed ciphertext emits telemetry event with:
    - error_code: 603
    - error_type: "decryption_failure"
    - NO sensitive data in error details
  - [ ] **Subtask:** Run test suite to verify assertions fail:
    ```bash
    cd backend && ./run elixir:test test/famichat/messages/decryption_test.exs:40-60
    ```
- **Final Review 7.6:** Once all subtasks for Story 7.6 have been completed and verified, mark off the Story 7.6 checkbox in this Sprint7.md file.

### Story 7.7: Finalize and Commit Changes
- [ ] **7.7.1:** Stage all modified files (including source code and project documentation) for commit.
  - [ ] **Subtask:** Verify by running `git status` from the repository root.
- [ ] **7.7.2:** Create a conventional commit with a message that follows our commit conventions (e.g., `feat: add real-time messaging sprint tasks with validation and security checks`).
  - [ ] **Subtask:** Verify the commit message adheres to the Conventional Commits specification.
- [ ] **7.7.3:** Push the commit to the main branch.
  - [ ] **Subtask:** Verify by checking repository logs or running `git log` to ensure that changes have been pushed.
- **Final Review 7.7:** Once all subtasks for Story 7.7 have been completed and verified, mark off the Story 7.7 checkbox in this Sprint7.md file.

### Story 7.8: Verify Test Coverage for New Files
- [ ] **7.8.1:** Run the test coverage tool to generate a coverage report.
  - [ ] **Subtask:** Execute `cd backend && ./run mix coveralls` to generate the test coverage report.
  - [ ] **Subtask:** Verify that the overall test coverage for the new files is at least 80%.
  - [ ] **Subtask:** If coverage is below 80%, write additional tests until the minimum threshold is met.
  - **Expected Outcome:** The test coverage report should indicate at least 80% overall coverage.
- **Final Review 7.8:** Once all subtasks for Story 7.8 have been completed and verified, mark off the Story 7.8 checkbox in this Sprint7.md file.

### Story 7.9: Accounts Context Refactor and Sensitive Data Management
- [ ] **7.9.1:** Create Dedicated Accounts User Schema Module
  - [ ] **Subtask:** Develop a new file at `backend/lib/famichat/accounts/user.ex` with an Ecto schema that includes the following fields:
        - `username` (string)
        - `email` (string, encrypted via Cloak.Ecto)
        - `password_hash` (string)
        - `confirmed_at` (utc_datetime)
        - `confirmation_token` (string)
        - `reset_token` (string)
        - `reset_token_sent_at` (utc_datetime)
        - `last_login_at` (utc_datetime)
        - Standard timestamps
  - [ ] **Verification:** Run `cd backend && ./run mix format` to ensure correct formatting and run tests via:
        ```bash
        cd backend && ./run elixir:test test/famichat/accounts/user_test.exs
        ```

- [ ] **7.9.2:** Create Migration for the Accounts_Users Table
  - [ ] **Subtask:** Write a migration (e.g., `backend/priv/repo/migrations/20250301000000_create_accounts_users.exs`) to create the `accounts_users` table with all fields specified in 7.9.1 and proper unique constraints for `username` and `email`.
  - [ ] **Verification:** Execute:
        ```bash
        cd backend && ./run mix ecto.migrate
        cd backend && ./run psql -d postgres -c "\d accounts_users"
        ```

- [ ] **7.9.3:** Write Unit Tests for the Accounts Changeset
  - [ ] **Subtask:** Develop tests in `backend/test/famichat/accounts/user_test.exs` that verify:
        - Changeset errors when required fields (`username`, `email`, `password_hash`) are missing.
        - Email format validation works.
        - Uniqueness constraints for `email` and `username`.
  - [ ] **Verification:** Run:
        ```bash
        cd backend && ./run elixir:test test/famichat/accounts/user_test.exs
        ```
        and confirm all tests pass.

- [ ] **7.9.4:** Update CLI Run Tasks and Documentation
  - [ ] **Subtask:** Update the README and internal documentation to mention the new Accounts context. Verify that our standard run commands still function:
        - Migrations: `cd backend && ./run mix ecto.migrate`
        - Testing: `cd backend && ./run elixir:test`
  - [ ] **Verification:** Ensure the docs are updated and that the run commands complete without error.

- [ ] **7.9.5:** Integration Test Between Accounts and Chat Context
  - [ ] **Subtask:** Write an integration test (e.g., in `backend/test/integration/accounts_chat_integration_test.exs`) that:
        - Creates a user in the Accounts context.
        - Associates that user with an existing Family from the Chat context.
        - Verifies that retrieving the family information using the user's account ID works as expected.
  - [ ] **Verification:** Run:
        ```bash
        cd backend && ./run elixir:test test/integration/accounts_chat_integration_test.exs
        ```
        and confirm that the integration test passes.

**Final Review 7.9:** Once all subtasks for Story 7.9 have been completed and verified (via appropriate CLI commands and test outputs), mark off the Story 7.9 checkbox in Sprint7.md.

### Story 7.10: Conversation Type Boundary Implementation
- [ ] **7.10.1:** Enhance conversation schema for type enforcement
  - [x] **Subtask:** Add separate changesets for creation vs. updating (to enforce type immutability)
  - [ ] **Subtask:** Verify code quality and security
    - Run linting checks: `cd backend && ./run elixir:lint`
    - Run security analysis: `cd backend && ./run elixir:security-check`
    - Run static analysis: `cd backend && ./run elixir:static-analysis`
    - Ensure proper formatting: `cd backend && ./run elixir:format:check`
  - [ ] **Subtask:** Add tests for schema validation and constraints

- [ ] **7.10.2:** Implement type-specific conversation creation functions
  - [ ] **Subtask:** Create the `create_self_conversation/1` function
  - [ ] **Subtask:** Create the `create_direct_conversation/2` function
  - [ ] **Subtask:** Create the `create_family_conversation/1` function
  - [ ] **Subtask:** Add comprehensive tests for type-specific creation functions
  - [ ] **Subtask:** Update API documentation to reflect the type-specific approach

- [ ] **7.10.3:** Implement race condition handling with transactions
  - [ ] **Subtask:** Use serializable transactions for critical operations
  - [ ] **Subtask:** Implement proper ON CONFLICT handling for direct conversations
  - [ ] **Subtask:** Verify code quality and security
    - Run linting checks: `cd backend && ./run elixir:lint`
    - Run security analysis: `cd backend && ./run elixir:security-check`
    - Run static analysis: `cd backend && ./run elixir:static-analysis`
    - Ensure proper formatting: `cd backend && ./run elixir:format:check`
  - [ ] **Subtask:** Test concurrent creation scenarios
    - Simulate simultaneous conversation creation
    - Verify appropriate handling of conflicts
    - Test transaction isolation levels

- [ ] **7.10.4:** Add basic group conversation management
  - [ ] **Subtask:** Create the `create_group_conversation/3` function
  - [ ] **Subtask:** Implement user count validation per conversation type
  - [ ] **Subtask:** Add migration for required fields
  - [ ] **Subtask:** Test group conversation creation and validation

- [ ] **7.10.5:** Create group membership role tracking schema
  - [ ] **Subtask:** Create new schema `group_conversation_privileges.ex` for role management
    - Schema fields: conversation_id, user_id, role (admin/member), granted_by, granted_at
    - Schema relations: belongs_to conversation, user, and granting user
    - Purpose: Clearly separate privilege management from basic participation
    - **Naming Rationale**: After reviewing existing schema patterns (`conversation_participant.ex`, `conversation.ex`, etc.), chose `group_conversation_privileges.ex` to explicitly indicate:
      - Scoped to group conversations specifically (not direct or self)
      - Focused on privilege/permission management
      - Distinct from the basic `conversation_participant.ex` join schema
    - The name ensures clarity in the codebase and properly communicates the schema's responsibility for handling authorization/permissions rather than just tracking participation
    - **Implementation Details**:
      ```elixir
      # Schema structure
      schema "group_conversation_privileges" do
        belongs_to :conversation, Famichat.Chat.Conversation, type: :binary_id
        belongs_to :user, Famichat.Chat.User, type: :binary_id
        belongs_to :granted_by, Famichat.Chat.User, type: :binary_id, foreign_key: :granted_by_id
        
        field :role, Ecto.Enum, values: [:admin, :member], default: :member
        field :granted_at, :utc_datetime, default: &DateTime.utc_now/0
        
        timestamps(type: :utc_datetime)
      end
      ```
    - **Migration Structure**:
      ```elixir
      # Migration file
      def change do
        create table(:group_conversation_privileges, primary_key: false) do
          add :id, :binary_id, primary_key: true
          add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all), null: false
          add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
          add :granted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
          add :role, :string, null: false
          add :granted_at, :utc_datetime, null: false, default: fragment("NOW()")
          
          timestamps()
        end
        
        # Create indexes
        create unique_index(:group_conversation_privileges, [:conversation_id, :user_id])
        create index(:group_conversation_privileges, [:conversation_id])
        create index(:group_conversation_privileges, [:user_id])
        create index(:group_conversation_privileges, [:granted_by_id])
      end
      ```
  - [ ] **Subtask:** Implement role-based authorization functions
    - Add helper functions for checking admin status
    - Implement proper permission checks for group operations
    - Add telemetry instrumentation for role-based actions
  - [ ] **Subtask:** Verify code quality and security for the new schema and functions
    - Run linting checks: `cd backend && ./run elixir:lint`
    - Run security analysis: `cd backend && ./run elixir:security-check`
    - Run static analysis: `cd backend && ./run elixir:static-analysis`
    - Ensure proper formatting: `cd backend && ./run elixir:format:check`
    - Run tests for the new module: `cd backend && ./run elixir:test test/famichat/chat/group_conversation_privileges_test.exs`
  - [ ] **Subtask:** Create migration for the new schema
  - [ ] **Subtask:** Add basic tests for schema validation

- [ ] **7.10.6:** Implement group membership role functions
  - [ ] **Subtask:** Add helper functions for checking admin status
  - [ ] **Subtask:** Implement proper permission checks for group operations
  - [ ] **Subtask:** Add telemetry instrumentation for role-based actions
  - [ ] **Subtask:** Test role management edge cases
    - Prevent last admin from leaving/being removed from group
    - Handle concurrent permission changes
    - Test role-specific operations and authorization

- [ ] **7.10.7:** Document group conversation architecture
  - [ ] **Subtask:** Document role-based permissions model
  - [ ] **Subtask:** Explain separation from ConversationParticipant
  - [ ] **Subtask:** Provide usage examples in developer documentation
  - [ ] **Subtask:** Update API documentation to include role management

- [x] **7.10.8:** Add conversation hidden_by_users field
  - [x] **Subtask:** Create migration to add the hidden_by_users field
  - [x] **Subtask:** Implement basic schema support for tracking hidden conversations
  - [x] **Subtask:** Add tests for schema changes

- [x] **7.10.9:** Implement conversation hiding functionality
  - [x] **Subtask:** Create hide_conversation/2 and unhide_conversation/2 functions
  - [x] **Subtask:** Update query functions to filter based on visibility
  - [x] **Subtask:** Test conversation hiding and retrieval
  - [x] **Subtask:** Test conversation re-discovery after previous hiding
  - [x] **Subtask:** Verify code quality and security
    - Run linting checks: `cd backend && ./run elixir:lint`
    - Run security analysis: `cd backend && ./run elixir:security-check`
    - Run static analysis: `cd backend && ./run elixir:static-analysis`
    - Ensure proper formatting: `cd backend && ./run elixir:format:check`
  - [x] **Subtask:** Test conversation hiding and retrieval
    - Test hiding conversations for specific users
    - Test visibility filtering in queries
    - Test conversation re-discovery after previous hiding

---

*Each story is scoped to a one–point effort, and the story will not be considered complete unless all subtasks—including additional security, telemetry, and encryption–preparation tasks, along with appropriate documentation and validations—are satisfied. Remember: the tests must be written (red) before any implementation (green) is added!*

## Command Reference

Below are some relevant commands to run within the Docker-based development environment. Make sure to navigate to the `backend` directory before executing these commands:

 - **Start IEx Session:**  
   ```bash
   cd backend && ./run iex -S mix
   ```
   This opens an interactive Elixir shell inside the Docker container.

 - **Run Tests:**  
   ```bash
   cd backend && ./run elixir:test
   ```
   Runs the entire test suite within the Docker container.

 - **Format Check:**  
   ```bash
   cd backend && ./run elixir:format:check
   ```
   Checks for any unformatted code.

 - **Lint:**  
   ```bash
   cd backend && ./run elixir:lint
   ```
   Runs code quality checks using Credo.

 - **Security Check:**  
   ```bash
   cd backend && ./run elixir:security-check
   ```
   Executes Sobelow security checks for the codebase.

 - **Static Analysis:**  
   ```bash
   cd backend && ./run elixir:static-analysis
   ```
   Performs static analysis (e.g., Dialyzer) on the project.

These commands help ensure that all changes are verified for code quality, security, and consistency inside our Dockerized environment.
