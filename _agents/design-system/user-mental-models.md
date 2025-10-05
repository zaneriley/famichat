The ideal user experience (UX) for Push Search must seamlessly integrate three distinct modalities: **Exploration** (general chatting with Gemini), **Deep Dive** (structured research and briefings), and **Interrogation** (contextual analysis of existing reports). The challenge is managing the ambiguity of user intent through a single "omnipotent" composer without sacrificing clarity or workflow fluidity.

The solution is a **Context-Aware Interaction Model** realized through a spatial design called "The Stage and the Stream," coordinated by a dynamic Composer featuring a "Context Tray."

### 1. The Spatial Model: The Stage and the Stream

The interface architecture should be organized into two primary, persistent zones to separate the subject of focus from the history of interaction.

1.  **The Stage (Focus Area):**
    *   **Purpose:** The main content area where detailed artifacts—research briefings, visualizations, dashboards, or search results—are displayed. It represents the "noun" the user is examining.
    *   **Behavior:** Dynamic; the content on the Stage changes based on navigation or the results of user actions.

2.  **The Stream (Interaction History):**
    *   **Purpose:** A persistent (though collapsible) sidebar containing the chronological flow of all interactions: general queries, commands, LLM responses, and summaries of research runs. It represents the "verb" and the dialogue history.
    *   **Behavior:** Provides historical context and immediate conversational feedback.

**The Relationship:** Interactions in the Stream can drive what appears on the Stage (e.g., initiating research loads a briefing), and the content on the Stage provides the context for subsequent interactions in the Stream.

### 2. The Omnipotent Composer: Managing Context and Intent

The Composer is the single, unified entry point for all input. Its effectiveness relies on clearly managing and visualizing both the **Context** (what the user is talking about) and the **Intent** (the weight of the interaction).

#### A. The Context Tray (Managing Context)

The Context Tray is a visual area adjacent to the Composer input field. It holds "Context Pills"—tokens representing the information currently included in the conversation scope. This provides explicit clarity on the scope of the subsequent input.

1.  **Implicit Context (Tethering):**
    *   When the user navigates to a specific briefing on the Stage, that briefing is automatically added to the Context Tray.
    *   *UX:* If the user asks, "Summarize the key findings," the system implicitly understands they mean *this* briefing.
    *   If the Stage is a dashboard (no specific focus), the Context Tray is empty, defaulting to general Exploration.

2.  **Explicit Context (Synthesis and Cross-Referencing):**
    *   Users can manually augment the context.
    *   *Mechanisms:* Using `@` mentions to add existing topics (e.g., `@EU AI Act Report`), uploading files, or pasting URLs into the tray.
    *   *UX:* This enables multi-topic synthesis, allowing queries like, "Compare the methodology of @ReportA with @ReportB."

3.  **Context Control (Untethering):**
    *   Users must have clear control to remove items from the Context Tray (clicking the 'X' on a Context Pill). Clearing the tray returns the composer to its general Exploration state, allowing a user to ask an unrelated question without leaving the current view.

#### B. The Engine Switch (Managing Intent/Weight)

The system must distinguish between lightweight chats (Gemini) and heavyweight research (The Research Engine), managing user expectations for response time and depth.

1.  **Intelligent Inference:** The backend `InteractionRouter` analyzes the input complexity. "What is 2+2?" infers "Quick Chat." "Analyze the geopolitical impact..." infers "Deep Research."
2.  **Explicit Control:** The Composer UI provides clear overrides. The primary action button should adapt visually based on the inference (e.g., a different icon or label for "Send" vs. "Research"). A toggle or dropdown allows the user to explicitly force the interaction weight.

### 3. Key Interaction Flows

This model facilitates seamless transitions between different user needs.

#### Flow 1: Exploration (General Q&A)

*   **Context:** User is on the Dashboard. Context Tray is empty. Intent is "Quick Chat."
*   **Input:** "What is the difference between OAuth and SAML?"
*   **Output:** A quick Gemini response appears in the Stream. The Stage is unaffected.
*   **Evolution:** The user can click an "Evolve to Topic" button on the chat response to initiate a Deep Research run based on this initial exploration.

#### Flow 2: Deep Dive (Initiating Research)

*   **Context:** Context Tray is empty. Intent is inferred or set to "Deep Research."
*   **Input:** "Provide a comprehensive analysis of semiconductor shortages."
*   **Output:** The system initiates a Research Run. Crucially, the **Stage navigates** to the new Topic View, displaying the live visualization. The Context Tray automatically updates to include the new topic.

#### Flow 3: Interrogation (Contextual Dialogue)

*   **Context:** User opens the "Semiconductor Shortages" briefing on the Stage. The Context Tray shows `[Semiconductor Shortages] (X)`. Intent is "Quick Chat" (using RAG).
*   **Input:** "Explain the methodology in the 'Market Analysis' section."
*   **Output:** The system uses the briefing content as context. The response appears in the Stream, visually associated with the topic on the Stage.

#### Flow 4: Synthesis (Multi-Context)

*   **Context:** User has "Semiconductor Shortages" in the tray. They add "@EV Trends 2024".
*   **Input:** "How do the shortages in the first report affect the predictions in the second?"
*   **Output:** The system synthesizes information from both contexts. The comparison appears in the Stream.

### 4. Unified Search and Retrieval

While the Composer is for *input*, retrieval requires a unified approach.

*   **Global Search:** A dedicated global search interface (distinct from the Composer) must index all artifacts: raw chat transcripts in the Stream and the full content of generated briefings.
*   **UX:** Search results clearly delineate the source (Chat vs. Briefing). Clicking a result loads the relevant artifact onto the Stage and restores the Composer's Context Tray to that state.