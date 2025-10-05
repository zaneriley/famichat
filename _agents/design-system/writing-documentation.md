## The living documentation doctrine

This document outlines the philosophy, architecture, and practices for maintaining documentation within our Design Computation Engine. Our goal is to ensure absolute synchronization between implementation and documentation. This improves the developer experience (DX) and enables effective use by both human engineers and AI tooling (LLMs).

Documentation is not a secondary task. It is a primary artifact of the engineering process.

---

### 1. Core principles

These principles govern how we create and maintain knowledge within the system.

#### 1.1 The proximity principle

**Mantra:** Documentation must live as close to the code it describes as possible.

**Execution:** We don't use external wikis or disconnected documents. Documentation is authored directly within Elixir modules, TypeScript configurations, and dedicated Governance Markdown files. This ensures that documentation is version-controlled, reviewed alongside code changes, and less likely to become stale.

#### 1.2 Federated authoring, centralized consumption

**Mantra:** Write everywhere, read from one place.

**Execution:** While authoring is distributed across the stack (Federated), the consumption of this information must be centralized. We achieve this through the Unified Artifact Registry.

#### 1.3 The unified artifact registry (`/docs`)

**Mantra:** The Single Source of Truth (SSoT) for all consumers.

**Execution:** The `/docs` directory in the repository root is the canonical location for all finalized documentation artifacts. It is structured to serve human readability (IDE browsing, Git repository) and machine consumption (LLM context injection, Storybook integration).

#### 1.4 Documentation as code; generation as build

**Mantra:** If it isn't automated, it's broken.

**Execution:** We rely on a "Living Documentation Pipeline" integrated into the build process. This pipeline extracts documentation from the source code, merges it with narrative principles, and serializes it into the Artifact Registry. Manually updating generated documentation in `/docs/generated` is strictly forbidden; updates must occur upstream in the source.

---

### 2. The information architecture

We define distinct domains within our documentation architecture: The Source (where we write) and the Registry (where we read).

#### 2.1 The source (federated authoring locations)

We organize the repository by Domain Contexts. Implementation details reside in code, while the Conceptual Core resides in the **Governance Context** (`/governance`).

| Artifact type | Location (SSoT) | Authoring Context and Method |
| :--- | :--- | :--- |
| **Component API & behavior** | Elixir component modules (`.ex`) | **Implementation Context.** `@moduledoc` (Reasoning/Overview), `@doc` (API Contract). |
| **Foundations & intent** | TypeScript configs (`tailwind/configs/`) | **Implementation Context.** Structured `metadata` objects embedded within definitions. |
| **Computational logic** | TypeScript engines (`tailwind/engines/`) | **Implementation Context.** TSDoc comments explaining algorithms. |
| **Principles & narrative** | `/governance/principles/` | **Governance Context.** Authored Markdown for the Conceptual Core (Spatial Paradigm, Color Philosophy). |
| **Glossary template** | `/governance/templates/` | **Governance Context.** The structural template and static rules for the auto-generated `style-glossary.md`. |

#### 2.2 The artifact registry (`/docs`)

The build pipeline synthesizes the Source documentation into this central registry.

```
/docs/
├── principles/               # Narrative and Concepts (Copied from /governance/principles/)
│   ├── spatial-paradigm.md
│   ├── color-philosophy.md
│   └── motion-guidelines.md
│
└── generated/                # Auto-Generated Specifications (DO NOT EDIT MANUALLY)
    ├── style-glossary.md     # The primary governance artifact (Merged)
    ├── components-api.md     # Extracted Elixir component data
    └── foundations-data.md   # Extracted TS foundation data
```

---

### 3. The authoring playbook

This section details the specific practices for authoring documentation in different contexts.

#### 3.1 Documenting components (Elixir)

Use Elixir documentation attributes strategically to capture different levels of information.

1.  **Design reasoning (`@moduledoc`):** Explain the "Why." Describe the component's purpose, how it implements specific design principles (e.g., Coplanar Composition), and its relationship to the Intent system (Canvas, Signal, Agency).
2.  **API contract (`@doc` on attributes/slots):** Explain the "What." Document the function of each attribute and slot. This data is extracted by the pipeline for the Registry and visualized by Storybook.

```elixir
@moduledoc """
Implements the primary interaction input.

## Design Reasoning
Adheres to the 'Agency' context, using `--Action--Primary` tokens.

## Spatial Behavior
This component adheres to the Coplanar Composition paradigm. When focused, 
it expands its footprint, dynamically reshaping the adjacent Content Zone.
"""
defmodule MyApp.Composer do
  # ...
  attr :state, :string, default: "compact", doc: "Controls the spatial footprint: 'compact' or 'expanded'."
  # ...
end
```

#### 3.2 Documenting foundations and intent (TypeScript)

Embed structured metadata directly into the configuration objects. This is superior to comments as it is strongly typed and easily machine-readable.

1.  **Structured metadata:** Define a `metadata` field for every token or configuration entry.
2.  **Context (The "Deep Why"):** Use the metadata to explain the computational rationale or semantic context required for the Style Glossary. This must provide information **not obvious from the code itself**.

```typescript
// Example: assets/tailwind/configs/theme-config.ts
export const LightTheme = {
    'Canvas--Base': {
        L: 0.95,
        H: Hues.Neutral + LIGHT_THEME_HUE_SHIFT,
        metadata: {
            name: 'Base Surface (Light)',
            // Explain the rationale for the parameters, not just the obvious context
            context: 'The primary interaction plane (Z=1). High lightness (L:0.95). Implements an environmental Hue Shift (ΔH -20°) to create a warmer tint distinct from the Dark Theme.',
        }
    },
};
```

#### 3.3 Documenting principles (narrative Markdown)

High-level concepts (Spatial Paradigms, Color Philosophy, Writing Guidelines) require narrative explanation and define the system's Conceptual Core.

1.  **Location:** Author these in the **Governance Context**: `/governance/principles/`.
2.  **Focus:** Focus on the architectural intent and the decision-making frameworks, abstracted from implementation details.
3.  **Review:** These documents must be reviewed alongside relevant code changes. For example, update the Spatial Paradigm document when changing layout behavior.

---

### 4. The consumption strategy

The Unified Artifact Registry (`/docs`) supports multiple consumption modes efficiently.

#### 4.1 Human consumption

1.  **IDE and repository browsing:** Developers should primarily use the `/docs` directory within their IDE or the Git repository interface for daily reference.
2.  **The visualized hub (Storybook):** Phoenix Storybook serves as the interactive Design System Hub. The build pipeline executes a **Synchronization Task** that copies and transforms artifacts from `/docs` (as `.mds` files) into the Storybook source path. This provides a visualized, searchable interface combining narrative principles, the generated glossary, and live component examples.

#### 4.2 LLM and tooling consumption

The Artifact Registry is optimized for AI tooling, RAG (Retrieval-Augmented Generation), and dynamic context injection.

1.  **Canonical source:** All AI tooling MUST be configured to index the `/docs` directory.
2.  **Format:** Markdown is the canonical format. It provides structured narrative and specifications optimized for LLM ingestion.
3.  **Context injection:** By maintaining this registry, we ensure that LLMs assisting with UI tasks are automatically provided with the correct design principles (`/docs/principles`) and implementation rules (`/docs/generated/style-glossary.md`), enforcing alignment and consistency.