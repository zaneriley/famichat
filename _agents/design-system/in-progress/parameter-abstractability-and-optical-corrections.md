# Parameter Abstractability & Optical Corrections

**Date**: 2025-10-04
**Context**: Meta-patterns extracted from typography weight/width architecture discussion.

## Overview

Design system parameters exist on a spectrum from fully abstractable (can be tokenized) to fundamentally contextual (runtime-only). Understanding where a parameter falls on this spectrum determines its implementation architecture.

## The Abstractability Spectrum

```
Static DNA ←→ Optical Corrections ←→ Semantic Patterns ←→ Content-Dependent
(Tokens)      (Calc formulas)       (Component bundles)   (Runtime/Manual)
```

### Level 1: Static DNA (Tokenizable)

**Characteristics**:
- Context-independent values
- Predetermined scales
- Pure data (no runtime computation)

**Examples**:
- Base size scale: `--fs-md`, `--fs-2xl`
- Hue anchors: `--hue-neutral`
- Base spacing scale: `--space-1xs`

**Implementation**: TypeScript constant → Generated CSS variable → Direct reference

**When to Use**: Value is context-independent and reusable across many components.

---

### Level 2: Optical Corrections (Derivable via calc())

**Characteristics**:
- Context-dependent (varies based on other values)
- Requires runtime calculation
- Uses mathematical relationships (deltas, ratios)

**Examples**:
- Size-dependent weight: `calc(baseWeight + sizeCompensation)`
- Weight-dependent color: `calc(baseColor * (1 + strokeCompensation))`
- Marker adjustments: `calc(parentWeight - delta)`

**Implementation**:
1. Declare delta constants in TypeScript
2. Output deltas as CSS custom properties
3. Apply via `calc()` in authored CSS (runtime)

**When to Use**: Value must respond to runtime context (parent values, size, theme).

**Critical Pattern**: Optical corrections are **deltas**, not absolute values.

```css
/* ❌ Wrong - absolute value, not responsive to context */
::marker {
  --font-wght: 450;
}

/* ✅ Correct - relative delta, adapts to parent */
::marker {
  --font-wght: calc(var(--font-wght) - var(--optical-marker-weight-delta));
}
```

---

### Level 3: Semantic Patterns (Bundled Adjustments)

**Characteristics**:
- Multiple parameters must coordinate
- Reusable across contexts
- Named combinations with semantic intent

**Examples**:
- Small-legible mode: weight + spacing + caps
- Display emphasis: size + width + weight coordination
- Elevated surface: lightness + hue shift + chroma adjustment

**Implementation**: Component modifier or utility class that applies multiple properties

**When to Use**:
- 2+ parameters must change together
- Coordination is reusable (not one-off)
- Intent is semantic (not just aesthetic)

**Example**:
```elixir
# Component-level pattern
<Typography size="1xs" legibility_mode={true}>
  # Applies: heavier weight + letter-spacing + uppercase
</Typography>
```

```css
/* Utility-level pattern */
.text-small-legible {
  --font-wght: calc(var(--base-wght, 400) * 1.15);
  letter-spacing: 0.03em;
  text-transform: uppercase;
}
```

---

### Level 4: Content-Dependent (Runtime/Manual)

**Characteristics**:
- Requires measuring actual rendered content
- Cannot be predetermined
- Decision per instance

**Examples**:
- Width based on string length
- Line-height based on actual line wrapping
- Layout adjustments based on content overflow

**Implementation**:
- Manual designer decision per instance
- OR JavaScript measurement + dynamic style application
- Cannot use static tokens or even calc()

**When to Acknowledge**: Parameter requires information not available until render time.

**Example**:
```elixir
# Manual control - designer decides per instance
<Typography size="4xl" width="condensed">
  Very Long Title That Needs Condensing To Fit
</Typography>

# OR JavaScript runtime
<Typography size="4xl" class="auto-condense-by-length">
  Title
</Typography>
# Where .auto-condense-by-length uses JS to measure and apply width
```

---

## Optical Corrections: The Cross-Cutting Mechanism

### Key Principle: Optical Corrections Are Implementation Details

Optical corrections are **not** a separate intent domain (like Canvas/Signal/Agency). They are the **perceptual math** that ensures semantic intent is achieved correctly.

**The Relationship**:
```
Semantic Intent (WHAT - Signal/Agency/Canvas)
  ↓
Implementation (HOW - includes optical corrections)
  ↓
Perceptual Outcome (WHAT USER EXPERIENCES)
```

**Example**:
```
Intent: "De-emphasize secondary text" (Signal)
  ↓
Implementation: Use lighter font weight (300 instead of 400)
  ↓
Optical Reality: Lighter strokes appear less opaque at same color
  ↓
Correction: Increase color lightness by 15% to maintain contrast
  ↓
Outcome: Text appears appropriately de-emphasized without losing readability
```

### Pattern: Optical Corrections Use Deltas

**Governing Principle**: Optical corrections must be theme-agnostic and context-adaptive by using relative deltas rather than absolute values.

**Why This Matters**:
- Works across all parent contexts (light/normal/bold all get compensated)
- Theme-agnostic (same formula works in light/dark themes)
- Maintainable (change parent, children adjust automatically)

**Example**:
```css
/* Define compensation constants */
:root {
  --optical-size-weight-delta: 50;
  --optical-marker-width-delta: -35;
  --optical-thin-stroke-lightness-bump: 0.15; /* 15% */
}

/* Apply as relative deltas */
.text-1xs {
  --font-wght: calc(var(--font-wght) + var(--optical-size-weight-delta));
}

::marker {
  --font-wdth: calc(var(--font-wdth) - var(--optical-marker-width-delta));
}

.thin-text {
  --adjusted-lightness: calc(
    var(--base-lightness) * (1 + var(--optical-thin-stroke-lightness-bump))
  );
}
```

### Where Optical Corrections Live

**Not**: A separate Intent domain (Canvas/Signal/Agency are semantic, not perceptual)

**Yes**: Part of the implementation layer (Principle #7: Algorithmic Derivation)

**Architecture Placement**:
- **Constants declared**: Layer 2 (Mapping - e.g., `type-config.ts`)
- **Applied in CSS**: Layer 4 (Generated CSS + Authored CSS)

**Example Structure**:
```typescript
// Layer 2: configs/type-config.ts
export const OPTICAL_COMPENSATIONS = {
  sizeWeightDelta: 50,
  markerWidthDelta: -35,
  thinStrokeLightnessBump: 0.15,
};

// Layer 4: generate-type-tokens.ts
function generateOpticalTokens() {
  return `
  --optical-size-weight-delta: ${OPTICAL_COMPENSATIONS.sizeWeightDelta};
  --optical-marker-width-delta: ${OPTICAL_COMPENSATIONS.markerWidthDelta};
  `;
}

// Layer 4: Authored CSS (app.css or components)
.text-1xs {
  --font-wght: calc(var(--font-wght) + var(--optical-size-weight-delta));
}
```

---

## Documentation Template for Optical Corrections

When adding optical corrections, document the perceptual rationale:

```css
/* Optical Correction: [Name]
 *
 * Perceptual Problem:
 *   [Describe what the eye perceives that needs compensation]
 *
 * Compensation Direction:
 *   [Increase/decrease which parameter and why]
 *
 * Formula:
 *   [The mathematical relationship]
 *
 * Status: [Experimental/Validated/Stable]
 *
 * Context: [Where this applies - universal or specific contexts]
 */
```

**Example**:
```css
/* Optical Correction: Size-to-Weight Compensation
 *
 * Perceptual Problem:
 *   As type size decreases, stroke weight appears proportionally lighter,
 *   causing small text to look washed out and disrupting visual "grey"
 *   (even texture across the page).
 *
 * Compensation Direction:
 *   Increase weight as size decreases to maintain perceptual density.
 *
 * Formula:
 *   small-text-weight = base-weight + sizeWeightDelta
 *   Current delta: +50 (e.g., 400 → 450 for text-1xs)
 *
 * Status: Experimental (needs validation across size range)
 *
 * Context: Applied to small sizes (1xs, 2xs) where weight loss is perceptible
 */
:root {
  --optical-size-weight-delta: 50;
}

.text-1xs {
  --font-wght: calc(var(--font-wght) + var(--optical-size-weight-delta));
}
```

---

## Decision Framework: Which Level?

When adding a new parameter or feature:

1. **Is the value predetermined and context-independent?**
   - YES → Level 1 (Static DNA token)
   - NO → Continue to Q2

2. **Does it depend on other runtime values (parent, size, theme)?**
   - YES → Level 2 (Optical correction with calc())
   - NO → Continue to Q3

3. **Is it a coordinated bundle of multiple parameters?**
   - YES → Level 3 (Semantic pattern)
   - NO → Continue to Q4

4. **Does it require measuring actual rendered content?**
   - YES → Level 4 (Content-dependent, manual/JS)
   - NO → Re-evaluate Q1-Q3 (you likely misunderstood the requirement)

---

## Common Anti-Patterns

### Anti-Pattern 1: Trying to Tokenize Content-Dependent Parameters

**Example**: Trying to create tokens for width based on string length.

**Why Wrong**: String length is runtime content, cannot be predetermined.

**Correct Approach**: Provide manual control or JavaScript runtime solution.

### Anti-Pattern 2: Using Absolute Values for Optical Corrections

**Example**: `::marker { --font-wght: 450; }`

**Why Wrong**: Doesn't adapt to parent context, theme changes, or component variations.

**Correct Approach**: `::marker { --font-wght: calc(var(--font-wght) - 50); }`

### Anti-Pattern 3: Creating Static Tokens for Derived States

**Example**: Creating separate tokens for `--Action--Hover`, `--Action--Pressed`

**Why Wrong**: Violates Principle #7 (Algorithmic Derivation), creates token explosion.

**Correct Approach**: Use calc() deltas: `calc(var(--action-l) * 1.08)`

See [design-system-approaches.md](./design-system-approaches.md) Principle #7 for examples.

---

## Related Principles

- **Principle #7: Algorithmic Derivation** (design-system-approaches.md)
- **Principle #3: Systemic Cohesion** (design-system-approaches.md)
- **Step 3.5: Token Creation Decision Framework** (applying-ia-and-ddd.md)

## References

- Typography Weight/Width Architecture (typography-weight-width-architecture.md)
- Color System: See `color-engine.ts` for complex optical calculations (chroma interpolation)
- Agency States: See `theme-config.ts` AGENCY_LIGHT_INTENSITY for ordinal power curve pattern
