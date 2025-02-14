# Famichat User Onboarding

## Purpose
This document focuses on the onboarding experience for new Famichat users. Its goal is to guide you through account creation, profile setup, and initial navigation of key features. It is designed from a user perspective, and it supplements the developer-focused documentation available in other project docs.

## Additional Resources
- Detailed technical and implementation information can be found in the [project plan](project.md) and the [feature completion criteria](done.md) documents.

- Phone bump to add people

Decision Recommendation:

Let's definitely explore the "phone bumping" onboarding! It's a brilliant idea for Famichat's brand and user experience.

Next Steps:

    iOS Native (Nearby Interaction) Investigation: Prioritize deep research into Apple's Nearby Interaction framework. Assess its reliability, hardware requirements, iOS version compatibility, and ease of implementation. Build a quick prototype to test its "bump" detection accuracy and user experience.
    High-Frequency Audio Feasibility Study (If Desired for Wider Cross-Platform): If cross-platform "bump" is a high priority, conduct a feasibility study on using high-frequency audio. Experiment with audio libraries, test reliability in noisy environments, and measure battery impact. Be realistic about the challenges.
    Bluetooth Proximity Library Exploration (If iOS Native is Too Limited and Audio is Unreliable): If neither iOS Native nor audio proves ideal, investigate robust cross-platform Bluetooth proximity detection libraries.
    Onboarding Flow Design: Start designing the user onboarding flow that incorporates the "bump" action as the primary, encouraged method, but with clear fallbacks.
    Prototyping and User Testing: Build prototypes (even low-fidelity ones) of the "bumping" onboarding experience and get feedback from potential users, especially families. Test the reliability of the chosen technology (iOS Native, audio, or Bluetooth).