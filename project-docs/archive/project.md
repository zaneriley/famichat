# Famichat Hello World - Project Plan

## Purpose
- Validate Docker-based Phoenix + Postgres.
- Confirm minimal Flutter client that can fetch data from the backend.
- Provide a foundation for future customizations and white-label features.
- **Messaging Requirements:**
  - Enable users to send messages to themselves (acting as a personal notepad).
  - Allow inter-user conversations only if both users are members of at least one common family.

This document provides an overview of the Famichat project's architecture, design choices, and overall roadmap for future development. For detailed technical feature statuses and implementation criteria, please refer to the [done.md](done.md) document.

## Next Steps (Updated January 25, 2024)

1. Backend Refinements
   - Fix remaining 4 failing tests
   - Add additional error handling for edge cases
   - Implement message delivery status updates
   - Add real-time updates via Phoenix Channels

2. Flutter Client Development
   - Implement chat UI components
   - Add state management (Provider/Bloc)
   - Integrate with backend chat endpoints
   - Add offline support & caching

3. Design System Integration
   - Complete design tokens implementation
   - Add theme switching support
   - Implement white-label configuration

4. Security & Performance
   - Add end-to-end encryption
   - Implement message caching
   - Add performance monitoring
   - Set up error tracking

Current Status:
- Backend core functionality is largely complete with 94/98 tests passing
- Basic Flutter client is set up with configuration management
- Chat context and schemas are implemented and tested
- Initial HTTP integration is working

## Definition of Done
- `docker-compose up` shows a Phoenix "Hello World" message in a browser.
- The iOS app fetches and displays that message in a Text view.
- **Messaging API:**  
  - Supports creation of self-conversations for personal note taking.
  - Permits creating a conversation between two distinct users only if they share a common family.

# NEXT STEPS
Plan:

    Address Flutter client fetching data: Define data models, develop new backend endpoints, update the Flutter client, and implement state management solutions.

    Address foundation for customizations and white-labeling: Create a backend theme endpoint, integrate theming in Flutter, and extend configuration for white-label settings.

About the Project:
This project is a self-hosted, white-label video and chat application designed specifically for families. It provides a secure and private digital space for families to stay connected through asynchronous messaging, occasional video calls, and unique "cozy" features inspired by games like Animal Crossing. The platform is highly customizable, allowing each family to tailor the experience, from branding to features, creating a truly personalized communication hub. It's built for families who value privacy, control over their data, and a more intimate, intentional way to connect with loved ones. It was originally built to meet a single family's needs for bilingiual, secure communication across continents, with a way to share photos, updates, and milestones. It is being made white-label so that others can use for their own families.

Core Functionality & Features:

    Asynchronous Communication: The primary mode of communication will be asynchronous, similar to text/group messages, with an emphasis on "slow" features like leaving "letters."
    Real-time Communication: Live video calls are a secondary need, accounting for approximately 15% of usage.
    "Cozy" Connection: Exploration of features inspired by games like Animal Crossing that foster a sense of ambient connection and shared experience, focusing on asynchronous interactions.
    Native iOS App: The primary platform will be a dedicated iOS app.
    Web Client: A secondary web client will provide accessibility from computers.
    Searchable Content: Robust search functionality to easily find past conversations, media, and other shared content is essential.
    Notifications: Standard iOS notification system will be used to alert users to new messages.
    Customizable Features: The ability to create bespoke features tailored to your family's needs (e.g., Japanese/English language support, Missouri/Tokyo weather, etc.) is a key advantage. The platform should support a high degree of customization for other families.

User Experience & Design:

    Family-Centric Design: The UX should be specifically designed with families in mind, incorporating features related to holidays, birthdays, kids' photos/galleries, addresses, etc.
    Aesthetic: You, as a designer, will handle the visual design for your family's instance. The platform should allow for easy aesthetic customization by other families.
    User Roles: The app will serve your nuclear family (wife, you, child) as well as extended family (parents, siblings, nieces). The platform should support different user roles and permissions.

Technical Considerations:

    Security: Top priority. End-to-end encryption, passcodes, and other robust security measures are non-negotiable. Security architecture must be adaptable to different family's instances.
    Reliability: While you acknowledge concerns about speed and reliability, the app needs to be stable and performant across all family instances.
    Maintenance: You will need to allocate time for ongoing development and maintenance. Consider the maintenance needs of other families using the platform.
    Self-Hosted: The app will be self-hosted, giving you full control over data and features. The platform should be easy for others to self-host.
    Scalability: The platform's architecture needs to be designed for easy deployment and scaling for multiple families.
    Containerization: To be considered for easier deployment.

Cultural & Family-Specific Needs:

    Bilingual Support: Japanese and English language options are needed for your family. The platform should allow for easy addition of new languages.
    Location-Specific Information: Missouri and Tokyo weather and potentially other location-based data is needed for your family.
    Family Traditions: Consider how to incorporate features that support or reflect your family's unique traditions and cultural background. The platform should be adaptable to other families' traditions.
    Privacy: Given the sensitive nature of family information, privacy must be carefully considered in all design and development decisions.

White-Label/Turnkey Considerations:

    Customization:
        Branding: Easy customization of the app's appearance (logos, colors, etc.).
        Features: A system for enabling/disabling features.
        Language: Easy addition of new language options.

## Backlog Items

As we continue to evolve Famichat, the following items have been identified as backlog features or improvements. These are important for future iterations, even though they are not part of our current sprint:

- **Pagination for Message Retrieval**  
  - **Priority:** High  
  - **Description:** Enhance `get_conversation_messages/1` to support pagination (limit/offset) to handle large conversations without performance degradation.

- **Concurrency and Simultaneous Access Handling**  
  - **Priority:** Medium  
  - **Description:** Monitor and address potential race conditions in simultaneous message sending and retrieval. Revisit once heavier traffic is observed.

- **Soft Deletes and Message Editing**  
  - **Priority:** Low-Medium  
  - **Description:** Support for soft deletes (e.g., setting a `deleted_at` timestamp) & message edits to allow "undo" functionality and better moderation.

- **Rate Limiting for Messaging Endpoints**  
  - **Priority:** Medium  
  - **Description:** Implement rate limiting on sending and retrieval APIs to prevent abuse, ensuring that telemetry helps monitor any potential spamming or overloads.

- **Enhanced Telemetry for Error Scenarios**  
  - **Priority:** Medium  
  - **Description:** Expand telemetry instrumentation to capture and report error events and failure rates (e.g., database errors or not-found cases) to improve system monitoring.

- **Multi-Device Synchronization & Advanced Features**  
  - **Priority:** Low  
  - **Description:** Plan for future features such as multi-device sync, message attachments, and real-time edits once the core messaging flows are established.

- **Database Indexing Verification**  
  - **Priority:** High  
  - **Description:** Confirm that critical database fields (such as `conversation_id` on messages) are appropriately indexed to meet our performance targets.

- **Improved Caching Strategy**  
  - **Priority:** Medium  
  - **Description:** Revisit our caching implementation to mitigate repeated database hits, especially for frequently accessed conversations.