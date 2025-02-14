# Current Sprint: Messaging Enhancement & Backend Refinement

**Sprint Duration:**  
Start Date: YYYY-MM-DD  
End Date: YYYY-MM-DD  
*(Adjust dates as necessary)*

---

## Purpose

This document is intended to track the current sprint's objectives, tasks, and objective measurements of done in our Famichat project. It serves as a live tracker for progress on enhancing backend messaging features, improving code quality, and integrating real-time functionalities.

---

## Sprint Objectives

The focus of this sprint is to further enhance our messaging functionality by:
- **Implementing missing backend features** such as message retrieval, direct conversation creation, conversation listing, and support for self-messages.
- **Resolving failing tests** and strengthening our error handling.
- **Enhancing documentation and code quality** through better inline comments and `@doc` annotations.
- **Laying the groundwork for real-time updates** via Phoenix Channels.
- **Preparing endpoints for Flutter integration** and enabling further customization for white-label support.

---

## Tasks, Milestones, and Definitions of Done

### Milestone 1: Backend Messaging Enhancements

#### Task 1.1: Implement Message Retrieval
- **Action:** Add a `get_conversation_messages(conversation_id)` function in `MessageService`.
- **Objective Measurement:**
  - Retrieves messages in chronological order.
  - Unit tests cover scenarios with messages, empty conversations, and non-existent conversations.
  - CI passes with no errors.

#### Task 1.2: Develop Conversation Creation Service
- **Action:** Create a new module `Famichat.Chat.ConversationService`.
  - **Subtask 1.2.1:** Implement `create_direct_conversation(user1_id, user2_id)`.
    - **Done If:**
      - A direct conversation is created or an existing one is returned for a user pair (order insensitive).
      - Unit tests validate both creation and duplicate handling.
  - **Subtask 1.2.2:** Implement `list_user_conversations(user_id)`.
    - **Done If:**
      - Returns an accurate list of direct conversations for a user.
      - Appropriate tests verify the list behavior for users with and without conversations.

#### Task 1.3: Support Self-Messages
- **Action:** Extend the conversation model and messaging service for self-messages.
  - **Subtask 1.3.1:** Implement `create_self_conversation(user_id)` in `ConversationService`.
    - **Done If:**
      - A self conversation (type `:self`) is created with exactly one user.
      - Unit tests confirm that only one participant is associated.
  - **Subtask 1.3.2:** Extend `send_message/3` in `MessageService` to support self-conversations.
    - **Done If:**
      - Message sending works seamlessly within self-conversations with proper validations.

---

### Milestone 2: Quality Assurance & Documentation

#### Task 2.1: Resolve Failing Tests and Enhance Error Handling
- **Action:** Fix the four remaining failing tests and add robust error management in service functions.
- **Objective Measurement:**
  - All tests pass.
  - Edge cases and error conditions are thoroughly covered with unit and integration tests.
  - Error messages and logs provide clear context for debugging.

#### Task 2.2: Update Documentation and Code Quality
- **Action:** Enhance documentation on all public functions (using `@doc`) and refactor for clarity.
- **Objective Measurement:**
  - Comprehensive inline and module documentation exists.
  - Peer code reviews report high readability and maintainability.
  - Static analysis tools (e.g., Credo, Sobelow) pass without critical warnings.

---

### Milestone 3: Real-Time Features & Deployment Enhancements

#### Task 3.1: Integrate Phoenix Channels for Real-Time Updates
- **Action:** Set up Phoenix Channels to broadcast new message events and conversation updates.
- **Objective Measurement:**
  - Dedicated channels are operational.
  - Test cases confirm that messages are broadcasted for live updates.
  - User feedback shows real-time updates without manual refresh.

#### Task 3.2: Refinement of Docker Deployment & White-Label Preparation
- **Action:** 
  - Ensure `docker-compose up` successfully deploys the full application with all backend services.
  - Build and stub endpoints for theme switching and white-label configuration.
- **Objective Measurement:**
  - Deployment process is smooth with no runtime errors.
  - Endpoints are documented and respond as expected.
  
#### Task 3.3: Flutter Client Integration Support
- **Action:** Finalize necessary backend endpoints for the Flutter client, including communication and state management.
- **Objective Measurement:**
  - The Flutter client can fetch and display chat data.
  - Documentation exists for required API endpoints.
  - Early integration tests between backend and Flutter client pass.

---

## Sprint Metrics and Tracking

We will monitor the following metrics as objective measures of completed work:
- **Test Coverage:** ≥ 95% for new and modified code.
- **CI/CD Status:** All build and test pipelines must be green.
- **Code Review Quality:** No critical issues after peer reviews.
- **Deployment Success:** Docker deployment should launch the application with zero runtime errors.
- **Feature Acceptance:** Each new feature aligns with the defined acceptance criteria in [done.md](done.md).

---

## Risks and Blockers

- **Integration Complexity:** Real-time updates might require additional adjustments to LiveView components.
- **Test Failures:** Persistent test failures may delay progress—prioritize resolving these blockers.
- **Deployment Concerns:** Environment-specific issues in Docker that might affect production consistency.

---

## Current Status & Next Steps

- **In Progress:**  
  - Implementation of messaging enhancements and conversation services.
  - Resolving failing tests and refining error handling.
  
- **Upcoming Reviews:**  
  - Sprint review will be conducted after Milestone 1 and 2 completion.
  - Post-review, focus will shift to real-time updates and Flutter integration.

- **Assigned Team Members:**  
  - **Backend:** Feature development, testing, code quality, and documentation.
  - **DevOps:** Docker deployment and environment stabilization.
  - **Frontend:** Flutter client adjustments and real-time integration review.

*Last Updated: [Insert Date]* 

# Famichat Sprint Plan

## Sprint Goals
- Implement foundational backend and frontend features for messaging.
- Ensure core functionalities are in place for both self-messaging and inter-user messaging.
- Establish telemetry instrumentation to monitor performance.

## Tasks
1. **Conversation Creation Endpoint:**
   - Allow a user to message themselves (self-conversation).
   - When creating conversations between two different users, confirm that both users share at least one common family.
   - Return consistent API responses with telemetry metadata.
2. **Messaging API Testing:**
   - Update and run tests to verify that:
     - A user can successfully create a self-conversation.
     - A conversation between two distinct users is created only if they share a common family.
     - An error is returned when no shared family exists.
3. **Frontend Integration:**
   - Update the Flutter client to support messaging flows, ensuring users can send self–messages.
4. **Telemetry Integration:**
   - Verify that telemetry spans are added around performance-critical functions.

## Acceptance Criteria
- Users can send messages to themselves, and these messages are stored as valid conversations.
- When two different users initiate a conversation, it is created only if both belong to a shared family. Otherwise, the API returns an appropriate error.
- All new endpoints adhere to uniform response formats (with telemetry metadata where applicable) and meet performance targets. 