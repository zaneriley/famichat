# Purpose
This document defines the "Done" criteria for various project feature levels. It outlines what is expected at each milestone and indicates the current implementation status.

**Current Status Updates:**
- Level 2 (Message Retrieval): NOT IMPLEMENTED (only basic message sending is available).
- Level 3 (Direct Conversation Creation): NOT IMPLEMENTED (conversation creation logic is in progress; this includes proper telemetry instrumentation and adherence to business rules).
- Level 4 (List User Conversations): NOT IMPLEMENTED (no dedicated listing function exists).
- Level 5 (Self-Messages): PARTIALLY IMPLEMENTED (self-messaging is now allowed; users can message themselves as a text pad for storing notes).

---

# Implementation Progress

Level 1: Foundation - Basic Direct Message Sending (Text Only)

"Done" Definition:
* Schema: Conversation and Message schemas are set up (as we've discussed). Migrations are run and database is updated.
*  Service Modules:
    * Famichat.Chat.MessageService module is created.
        MessageService includes a function send_message(sender_id, conversation_id, content) that:
            Creates a new Message record in the database of message_type: :text.
            Returns {:ok, message} on success, or {:error, changeset} on validation failure.
        Basic changeset validation in Message schema for sender_id, conversation_id, and content (for :text type).
    Testing:
        Unit tests for MessageService.send_message:
            Test successful message creation.
            Test validation errors (e.g., missing sender_id, conversation_id, empty content).
    Scope: Focus only on sending text messages in direct conversations. Assume conversations and users exist (seed data or manual setup). No message retrieval yet, no conversation listing, no self-messages, no statuses beyond initial creation.

Level 2: Message Retrieval - Get Messages in a Conversation

    "Done" Definition (Builds on Level 1):
        Service Modules:
            MessageService module is updated to include get_conversation_messages(conversation_id) function.
            get_conversation_messages function:
                Retrieves all messages for a given conversation_id from the database, ordered by inserted_at (or timestamp if you add one).
                Returns {:ok, messages} on success, or {:error, :not_found} if the conversation doesn't exist (optional error handling for MVP, could also just return empty list if no messages found).
        Testing:
            Unit tests for MessageService.get_conversation_messages:
                Test successful retrieval of messages for a conversation.
                Test case with no messages in a conversation (should return empty list or :ok, []).
                (Optional for MVP Level 2) Test case where conversation doesn't exist (return :error, :not_found or handle gracefully).
        Scope: Focus on retrieving messages for existing direct conversations. Still text messages only. No conversation creation, no listing, no self-messages.

Level 3: Conversation Creation - Start Direct Conversations

    "Done" Definition (Builds on Level 2):
        Service Modules:
            Famichat.Chat.ConversationService module is created.
            ConversationService includes a function create_direct_conversation(user1_id, user2_id):
                Creates a new Conversation record in the database of conversation_type: :direct.
                Associates user1_id and user2_id with this new conversation using the conversation_users join table.
                Handles cases where a direct conversation already exists between these two users (either return the existing one or prevent creation and return error - decide desired behavior). For MVP, let's say we return the existing conversation if one exists between the same user pair (order doesn't matter, user A & B is same as user B & A).
                Returns {:ok, conversation} on success, or {:error, changeset} or {:error, :already_exists} on failure.
        Testing:
            Unit tests for ConversationService.create_direct_conversation:
                Test successful creation of a new direct conversation between two users.
                Test case where a conversation already exists between the same two users (should return the existing conversation).
                Test validation errors (if any for conversation creation itself at this stage - maybe for future metadata).
        Scope: Focus on creating direct conversations. Message sending and retrieval from Level 1 & 2 should still work. No conversation listing, no self-messages.

Level 4: List User Conversations - Get User's Direct Conversations

    "Done" Definition (Builds on Level 3):
        Service Modules:
            ConversationService module is updated to include list_user_conversations(user_id):
                Retrieves all direct conversations that a given user_id is a participant in (using the conversation_users join table).
                Returns {:ok, conversations}. Could return an empty list if the user has no conversations yet.
        Testing:
            Unit tests for ConversationService.list_user_conversations:
                Test successful retrieval of a list of direct conversations for a user.
                Test case where a user has no direct conversations (should return empty list).
                Test that it only returns direct conversations and not other types (if we introduce other types later).
        Scope: Focus on listing direct conversations for a user. All previous levels' functionality should remain working. No self-messages yet.

Level 5: Self-Messages - Basic Support

    "Done" Definition (Builds on Level 4):
        Service Modules:
            MessageService is extended to handle conversation_type: :self. send_message should now work for self-conversations too.
            ConversationService is extended to include create_self_conversation(user_id):
                Creates a Conversation of conversation_type: :self associated with a single user_id. We need to decide how self-conversations are modeled - maybe a direct conversation with the same user ID as both participants? Or a special type? Let's go with a special type conversation_type: :self for clarity.
                list_user_conversations might need to be updated to optionally include self-conversations or have a separate list_user_self_conversations function if we want to distinguish them in the UI later. For now, let's have list_user_conversations return only direct conversations and have a separate list_user_self_conversations.
        Testing:
            Unit tests for MessageService.send_message extended to test with conversation_type: :self.
            Unit tests for ConversationService.create_self_conversation.
            Unit tests for ConversationService.list_user_self_conversations.
        Scope: Adding basic self-message functionality. Direct messages and listing from previous levels remain. No message statuses beyond creation yet.

Level 6: Basic Message Status - "Sent" Status

    "Done" Definition (Builds on Level 5):
        Schema: Message schema already has status field. Ensure it defaults to :sent.
        Service Modules:
            MessageService.send_message should, by default, create messages with status: :sent. No explicit changes needed in function logic likely, just verify in testing.
        Testing:
            Unit tests for MessageService.send_message to verify that created messages have status: :sent.
        Scope: Implementing the "sent" message status. All previous levels' functionality remains. No "delivered" or "read" statuses yet.

Level 7: Refinement, Testing, and Documentation - MVP Backend Complete

    "Done" Definition (Builds on Level 6):
        Code Review: Review all code in Famichat.Chat context for clarity, maintainability, and adherence to best practices.
        Error Handling: Ensure proper error handling and logging in service modules.
        Validation: Double-check all input validation in changesets and service functions.
        Comprehensive Testing: Write integration tests (if feasible at this backend-only stage, maybe unit tests that test interactions between services) to ensure all levels work together as expected. Ensure good test coverage for all service functions.
        Documentation: Add basic documentation to service modules and functions (using @doc in Elixir).
        MVP Backend Functionality Complete: Levels 1-7 represent the core backend chat functionality for the MVP (Direct Messages, Self-Messages, Text messages, basic listing, "sent" status).

## Updated Messaging Criteria:
- **Self-Conversations:**  
  - A user messaging themselves is valid and should be stored as a conversation. This enables the user to use the messaging interface as a personal note pad.
- **Inter-User Conversations:**  
  - For two distinct users, the conversation is only valid if they share at least one common family. A conversation attempt between users who share no common family must fail.
- **Consistent API and Telemetry:**  
  - All messaging endpoints should return a consistent tuple structure (with or without metadata) and be instrumented using telemetry where applicable.

## Updated Messaging Criteria

- **API Response Format:**  
  All messaging endpoints return simple status tuples:
  ```elixir
  {:ok, entity} | {:error, reason}
  ```
- **Telemetry Integration:**  
  Critical operations emit telemetry events with detailed metadata while keeping business logic returns clean.

## Implementation Progress

**Level 1: Foundation - Basic Direct Message Sending (Text Only)**  
- `docker-compose up` shows a Phoenix "Hello World" message.
- The iOS app fetches and displays that message.
- Messaging functionality now supports:
  - **Self-Messaging:** Users can send messages to themselves.
  - **Family-Based Messaging:** Messaging between distinct users is allowed only when they share a common family.