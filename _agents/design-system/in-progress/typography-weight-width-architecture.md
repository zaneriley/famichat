# Typography Weight & Width Architecture

**Date**: 2025-10-04
**Context**: Design system discussion on implementing font-weight and font-width as systematic variables with optical compensations.

## The Problem Space

Font weight and width need to be:
1. Systematically declared as CSS custom properties (like color system)
2. Adjusted based on size (optical compensation)
3. Adjustable in specific contexts (markers, display type)
4. Responsive to runtime values (can't be static)

## Architectural Decisions

### Decision 1: Computational Constants Live in Layer 2 (Mapping)

**Where**: `configs/type-config.ts`

**What**: Optical compensation deltas, weight scales, width adjustments

**Why**:
- Follows existing pattern (`ELEVATION_FACTORS`, `AGENCY_LIGHT_INTENSITY` in theme-config)
- These are perceptual/semantic constants, not raw DNA
- DNA is for physical properties (font metrics, base sizes)
- Mapping is for how we **apply** those properties

**Example**:
```typescript
// type-config.ts (additions)
export const WEIGHT_SCALE = {
  light: 300,
  normal: 400,
  semibold: 600,
  bold: 700,
};

export const WIDTH_SCALE = {
  condensed: 75,
  normal: 100,
  expanded: 125,
};

export const OPTICAL_COMPENSATIONS = {
  // Size-to-weight relationship
  // Smaller sizes need heavier weights to maintain visual "grey"
  sizeWeightDelta: 50,  // e.g., text-1xs gets +50 weight

  // Width adjustment for specific contexts
  // Sometimes width needs adjustment for visual balance
  widthAdjustment: 35,  // e.g., markers get -35 width

  _rationale: {
    sizeWeight: "As type gets smaller, strokes appear lighter. Heavier weight maintains even texture across sizes.",
    width: "Contextual adjustment for visual balance (markers, display type). Not universal.",
  },
};
```

### Decision 2: Runtime Calculations Happen in CSS

**Critical Constraint**: Font-size is a runtime value (responsive, fluid via clamp()).

**Implication**: Weight/width adjustments must be calculated in CSS using `calc()`, not pre-computed in TypeScript.

**The Pipeline**:
```
TypeScript (Layer 2)           TypeScript (Layer 4)           CSS (Generated)              CSS (Authored)
┌─────────────────┐           ┌──────────────────┐           ┌────────────────┐          ┌──────────────────┐
│ Declare Delta   │  ──────>  │ Output to CSS    │  ──────>  │ Custom Props   │  ──────> │ Runtime calc()   │
│ sizeWeight: 50  │           │ Variables        │           │ --delta: 50    │          │ calc(400 + 50)   │
└─────────────────┘           └──────────────────┘           └────────────────┘          └──────────────────┘
```

**Example Flow**:
```typescript
// 1. Declare in type-config.ts
export const OPTICAL_COMPENSATIONS = { sizeWeightDelta: 50 };

// 2. Generate in generate-type-tokens.ts
function generateOpticalTokens() {
  return `--optical-size-weight-delta: ${OPTICAL_COMPENSATIONS.sizeWeightDelta};`;
}

// 3. Output to _typography.css (generated)
:root {
  --optical-size-weight-delta: 50;
  --font-wght: 400;  /* Base normal weight */
  --font-wdth: 100;  /* Base normal width */
}

// 4. Apply in authored CSS (app.css or component styles)
.text-1xs {
  --font-wght: calc(var(--font-wght) + var(--optical-size-weight-delta));
}

::marker {
  --font-wdth: calc(var(--font-wdth, 100) - var(--optical-width-adjustment, 35));
}

/* Global font-variation-settings reads these */
* {
  font-variation-settings: "wght" var(--font-wght), "wdth" var(--font-wdth);
}
```

### Decision 3: Weight Scale Is Designer-Declared

**Key Insight**: "The weight amounts I'll personally declare based on what optically looks right."

**Principle**: Weight values are **design decisions** based on optical perception, not derived from font metrics.

**Why Not Font-Derived**:
- Font may support 100-1000 range
- But 100 might be too thin for accessibility
- 1000 might be too loud for brand voice
- Optical differentiation varies by font (300→400 delta in Font A ≠ same perception in Font B)

**Implication**: When fonts change, the designer **redeclares the scale** based on the new font's characteristics.

**Example**:
```typescript
// type-config.ts
export const WEIGHT_SCALE = {
  light: 300,    // Designer decision: "This looks optically light in Google Sans"
  normal: 400,   // Font's default normal
  semibold: 600, // Designer decision: "Enough differentiation from normal"
  bold: 700,     // Designer decision: "Loudest we want for brand voice"
};

// NOT derived from:
// ❌ fontMetrics["google-sans"].minWeight (too technical)
// ❌ font.weights.available[0] (not perceptual)
```

**When Font Changes**:
```typescript
// Before: Google Sans
export const WEIGHT_SCALE = {
  light: 300,
  normal: 400,
  bold: 700,
};

// After: Switch to New Font
// Designer tests and redeclares based on new font's optical characteristics
export const WEIGHT_SCALE = {
  light: 250,    // New font's 250 looks like old font's 300
  normal: 400,
  bold: 650,     // New font's 650 looks like old font's 700
};
```

### Decision 4: Width Is Contextual, Not Systematic

**Key Insight**: Width adjustments are **sometimes needed**, not universally applied.

**Pattern**: Provide the adjustment constant, apply contextually in CSS.

```css
/* Constant available */
:root {
  --optical-width-adjustment: 35;
}

/* Applied only where needed */
::marker {
  --font-wdth: calc(var(--font-wdth, 100) - var(--optical-width-adjustment));
}

.display-expanded {
  --font-wdth: calc(var(--font-wdth, 100) + var(--optical-width-adjustment));
}

/* Most elements don't use it */
.text-md {
  /* No width adjustment */
}
```

## Open Questions

### Q1: Size-to-Weight Scaling

**Current**: Fixed delta (+50 for small sizes)

**Question**: Should the delta scale with size reduction?
- `text-md` (16px): +0
- `text-1xs` (14px): +50
- `text-2xs` (12px): +100?

**Or**: Is +50 sufficient across all small sizes?

**To Test**: Visual comparison of small sizes with different deltas to determine if scaling is needed.

### Q2: Width Adjustment Directionality

**For Markers**: `-35` (condense)
**For Display**: `+35` (expand)

**Question**: Are these the same magnitude but opposite direction, or should they be separate constants?

```typescript
// Option A: Symmetric
export const OPTICAL_COMPENSATIONS = {
  widthAdjustment: 35,  // Use +/- as needed
};

// Option B: Explicit
export const OPTICAL_COMPENSATIONS = {
  widthCondense: -35,   // For compact contexts
  widthExpand: +35,     // For display contexts
};
```

### Q3: Typography Engine Needed?

**Current Color System**: Has `color-engine.ts` for chroma interpolation (complex math).

**Typography**: Weight/width calculations are simpler (clamp, addition).

**Question**: Do we need `typography-engine.ts`, or inline the logic in generator?

**Complexity Comparison**:
- Color: Curve interpolation, perceptual calculations → **Engine justified**
- Typography: `clamp(calculated, min, max)`, `base + delta` → **Inline in generator?**

**Decision**: Start without engine. If complexity grows (multi-step calculations, validation), extract to engine.

## Implementation Checklist

- [ ] Extend `type-config.ts` with weight/width constants
- [ ] Extend `generate-type-tokens.ts` to output weight/width custom properties
- [ ] Add optical compensation constants as CSS variables
- [ ] Update global font-variation-settings to read from custom properties
- [ ] Document the size-to-weight relationship (after testing)
- [ ] Test weight deltas across size range
- [ ] Apply contextual width adjustments (markers, display type)
- [ ] Document when/how to redeclare weight scale on font changes

## Related Discussions

**Original Context**: List markers using tabular numerals appeared too heavy, prompting investigation into font-weight/width compensation.

**Key Realization**: The marker issue revealed a broader need for systematic weight/width variables, not just a one-off fix.

**Principles Established**:
1. Optical corrections are deltas, not absolute values
2. Runtime CSS calc() required for responsive contexts
3. Weight scales are designer-declared, not font-derived
4. Constants live in mapping layer (type-config.ts)

## References

- Related: `configs/theme-config.ts` (ELEVATION_FACTORS, AGENCY_LIGHT_INTENSITY patterns)
- Related: `engines/color-engine.ts` (engine pattern for complex calculations)
- Related: `generate-type-tokens.ts` (current typography generation)
- See: [design-system-approaches.md](./design-system-approaches.md) (Principle #7: Algorithmic Derivation)
