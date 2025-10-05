## The IA and DDD Doctrine: Methodology and Structure

This document defines the rigorous methodology for applying Information Architecture (IA) and Domain-Driven Design (DDD) principles within our application and its Design Computation Engine. This framework is the authoritative guide for both human engineers and LLMs, ensuring consistency, clarity, and scalability when extending or modifying the system.

### 1. The core philosophy

We utilize DDD to model the visual presentation layer. This approach is governed by the following principles:

1.  **Intent over Aesthetics:** Our language and structure must prioritize the *purpose* and *role* of an element (Intent) over its *appearance* (Aesthetics). Aesthetics are derived algorithmically from intent.
2.  **The Ubiquitous Language:** A precise, shared vocabulary must be used identically across design discussions, documentation, and the codebase (token names, component APIs).
3.  **Bounded Contexts:** We divide the system into distinct contexts with explicit boundaries and responsibilities to manage complexity.
4.  **Parametric Modeling:** The system relies fundamentally on mathematical relationships and parameters (OKLCH values, scaling ratios, easing curves), not static values.

---

### 2. The system map: Bounded contexts

Our Core Domain (The Design System) is divided into the following Bounded Contexts. Implementation must respect these boundaries.

#### 2.1. Foundations (The DNA)

The context for the raw parameters, constraints, and mathematical definitions of the system.

*   **Focus:** Color DNA (Hue Anchors, Chroma Curves), Measurement DNA (Ratios, Scales), Base Units.
*   **Implementation:** TypeScript configurations (`configs/dna/`).

#### 2.2. The intent system (The core taxonomy)

The context defining the semantic roles of visual elements. This is the primary IA, subdivided into:

*   **Canvas:** Spatial modeling, the Z-axis environment, and background surfaces.
*   **Signal:** Information hierarchy, emphasis, and foreground elements (text, icons). Governed by the Contrast Contract and Optical Corrections.
*   **Agency:** Functional intent, interaction hierarchy, and status feedback.
*   **Implementation:** TypeScript Intent Mapping (`theme-config.ts`) and generated CSS artifacts (`_intent.css`).

#### 2.3. The spatial system (The behavior)

The context defining the layout logic, dynamic behavior, and motion principles.

*   **Focus:** Layout Scaffolds, Behavioral Patterns (Spatial Negotiation), Motion Parameters, Spatial Paradigm (e.g., Coplanar Composition).
*   **Implementation:** Elixir Layout Components and specialized CSS/Motion tokens.

---

### 3. The methodology: The 5-step integration process

When extending or modifying the system (e.g., adding a new color, creating a component, defining a new behavior), you MUST follow this process.

#### Step 1: Domain analysis (Define the intent)

Analyze the requirement to understand its fundamental purpose within the design domain.

1.  **Identify the Core Concept:** What is the essential design intent? (e.g., "We need a surface for temporary modals," "We need to indicate a critical error.")
2.  **Define the Role:** What role does this element play in the user experience or the environment?

#### Step 2: Establish the bounded context (Categorize)

Determine where the requirement belongs within the System Map. This defines the implementation location.

1.  **Assign the Context:** Is it a raw parameter (Foundations)? A semantic visual role (Intent System)? Or a layout behavior (Spatial System)?
2.  **Assign the Sub-Context:** If Intent System, is it Canvas, Signal, or Agency?

*   *Example:* A "critical error" color belongs to `Intent System -> Agency`.

#### Step 3: Define the ubiquitous language (Name)

Establish the precise, semantic name. This name becomes the shared vocabulary and the implementation identifier (token or component name).

1.  **Enforce Semantics:** The name MUST reflect the intent defined in Step 1.
2.  **Strictly Avoid Aesthetics:** The name MUST NOT reference aesthetic values (e.g., use `--Status--Critical`, not `--Color--Red`).
3.  **Adhere to Schemas:**
    *   *Intent Tokens:* `[Context]--[Role]--[Modifier (Optional)]` (e.g., `--Canvas--Overlay`).

#### Step 3.5: The Token Creation Decision Framework (CRITICAL)

**Before creating any new token, you MUST answer these questions in order:**

##### Decision Tree

```
1. Does this describe a FUNDAMENTAL SEMANTIC ROLE that will be reused across components?
   ├─ YES → Proceed to Question 2
   └─ NO  → ⛔ DO NOT CREATE TOKEN. Use existing tokens + CSS derivation.

2. Can this be derived algorithmically from an existing token?
   ├─ YES → ⛔ DO NOT CREATE TOKEN. Use calc() or CSS variables.
   └─ NO  → Proceed to Question 3

3. Does this belong to Canvas, Signal, or Agency context?
   ├─ Component-specific (e.g., "Table Header") → ⛔ WRONG. Rethink as semantic role.
   └─ Semantic role (e.g., "Primary Action") → ✅ Create token.
```

##### Examples: What NOT to Create

❌ **Component-Specific Tokens** (Violates Ubiquitous Language):
```typescript
// WRONG - These are component-specific, not semantic roles
"Signal--Table-Header"        // Just use Signal--Primary or Signal--Emphasis
"Agency--Table-Row--Hover"    // Derive via calc(var(--canvas-base-l) * 1.08)
"Canvas--Modal-Backdrop"      // Use Canvas--Overlay (semantic role)
"Agency--Button-Disabled"     // Derive algorithmically with opacity or lightness delta
```

❌ **State Variations** (Should be algorithmically derived):
```typescript
// WRONG - States should use Principle #7: Algorithmic Derivation
"Agency--Action--Hover"       // Derive: calc(var(--agency-action-l) + 0.05)
"Agency--Action--Pressed"     // Derive: calc(var(--agency-action-l) - 0.08)
"Agency--Action--Disabled"    // Derive: opacity: 0.4
```

##### Examples: What TO Create

✅ **Fundamental Semantic Roles**:
```typescript
// CORRECT - These are reusable semantic roles
"Signal--Primary"             // Primary text/content hierarchy
"Signal--Emphasis"            // Emphasized/important information
"Agency--Action"              // Primary interactive action color
"Agency--Status--Critical"    // Critical/error status (system-wide)
"Canvas--Overlay"             // Overlay/modal surfaces (Z=3)
```

##### The Reuse-First Principle

**Default to reusing existing tokens with CSS modifiers:**

| Need | ❌ Don't Create | ✅ Do This Instead |
|------|----------------|-------------------|
| Hover state | `--Agency--Action--Hover` | `background: oklch(calc(var(--agency-action-l) * 1.08) ...)` |
| Table header bg | `--Canvas--Table-Header` | Use `Canvas--Base` or `Canvas--Raised` |
| Subdued text | `--Signal--Table-Content--Subdued` | Use `opacity: 0.7` on `Signal--Primary` |
| Row selection | `--Agency--Table-Selected` | Use `Canvas--Raised` + border |

**Rule of Thumb:** If the token name contains a component name (Table, Button, Modal), you're doing it wrong.

#### Step 3.6: Selection from Existing Palettes (Before Derivation)

Before writing any `calc()` or creating new tokens, **survey the existing palette** in your determined context (Canvas, Signal, or Agency).

**The mental model:**

The Intent System is organized like a museum with three wings:
- **Canvas wing** - Spatial surfaces and depth (Z-axis relationships)
- **Signal wing** - Information hierarchy and emphasis
- **Agency wing** - Interactive states and functional feedback

When you need a color, first visit the appropriate wing and examine what's already on display.

**Example: Styling borders**

*Step 2 determined: Canvas context (spatial separator)*

Now, survey the Canvas palette:

```typescript
// Current Canvas tokens (from theme-config.ts):
"Canvas--Backdrop"  // Z=0, foundational layer, darker than base
"Canvas--Base"      // Z=1, primary surface
"Canvas--Raised"    // Z=2, elevated above surface
```

**Ask**: "Which of these existing tokens represents a spatial boundary?"

- Not `Canvas--Base` - That's the surface being divided
- Not `Canvas--Raised` - That's elevated, borders recede
- Yes `Canvas--Backdrop` - Foundational layer, defines boundaries

**Use it directly:**
```css
border-color: oklch(
  var(--canvas-backdrop-l)
  var(--canvas-backdrop-c)
  var(--canvas-backdrop-h)
);
```

**Example: Styling hover states**

*Step 2 determined: Agency context (interactive feedback)*

Survey the Agency palette:

```typescript
// Current Agency tokens (from theme-config.ts):
[None defined yet]
```

**Recognition**: "The palette is incomplete. I've identified a missing semantic role: `Agency--Interactive--Hover`"

**Do NOT invent:**
```css
/* ❌ This creates an undocumented, arbitrary relationship */
background: oklch(calc(var(--canvas-base-l) * 1.08) ...);
```

**Instead, document and use fallback:**
```css
/* TODO: Use Agency--Interactive--Hover once defined (issue #XXX) */
/* Temporary: Using Canvas--Raised as visual approximation */
background: oklch(
  var(--canvas-raised-l)
  var(--canvas-raised-c)
  var(--canvas-raised-h)
);
```

**When selection reveals gaps:**

If the existing palette doesn't contain the semantic role you need, this is valuable discovery:

1. **Document it** - Create an issue describing the missing role
2. **Don't work around it with math** - Arbitrary calculations hide system gaps
3. **Use the closest existing token temporarily** - With a clear TODO comment
4. **Escalate** - Design system stewards need to know about palette gaps

This ensures the system evolves to cover real needs, rather than being bypassed with component-specific hacks.

#### Step 4: Parametric modeling (Model the logic)

Define the underlying parameters and mathematical relationships that govern the concept. This step is crucial before implementation.

1.  **Identify Parameters:** What are the variables? (e.g., Lightness, Chroma, Easing Curves, ΔL Deltas).
2.  **Define Relationships:** What are the mathematical rules? (e.g., Chroma Infusion curves, Optical Correction factors, Fluid Dynamic breakpoints).
3.  **Define Contracts:** Identify cross-context rules and constraints (e.g., The Contrast Contract between Signal and Canvas; The Spatial Contract for layout behavior).

#### Step 5: Implementation and documentation (Build and record)

Implement the requirement according to the architectural patterns governing its Bounded Context, and document it at the source.

1.  **Follow Architectural Patterns:**
    *   If implementing a parametric token (Color/Depth), you MUST use the **Master Pattern** (Registration, Base Parameters, Runtime Variables, Reconstruction).
    *   If implementing text color (`Signal`), you MUST integrate the **Adjustment Layer** for optical corrections.
    *   If implementing layout, you MUST adhere to the **Spatial Negotiation** patterns.
2.  **Document at the Source (Proximity Principle):**
    *   *Foundations/Intent:* Add structured `metadata` in the TypeScript configuration.
    *   *Components/Spatial:* Update `@moduledoc` (reasoning) and `@doc` (API) in the Elixir module.
    *   *Principles:* Document new conceptual principles (like Chroma Infusion) narratively in `docs_src/principles/`.