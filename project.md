# Famichat Hello World - Project Plan

## Purpose
- Validate Docker-based Phoenix + Postgres.
- Confirm minimal SwiftUI iOS client can fetch data from the backend.
- Provide a foundation for future customizations and white-label features.

## Next Steps
1. Expand Ecto schemas for storing messages, user accounts.
2. Add theming endpoints to serve design tokens.
3. Implement actual mobile UI for messaging.

## Definition of Done
- `docker-compose up` shows a Phoenix "Hello World" message in a browser.
- The iOS app fetches and displays that message in a Text view.


---

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