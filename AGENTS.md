# Famichat — Agent Rules

Rules every agent must follow when writing or modifying frontend code.

---

## Design System

### Typography
- **All text must go through `<.typography>`** — defined in `backend/lib/famichat_web/components/typography.ex`
- No raw `<p>`, `<h1>`–`<h6>`, `<span>` with text styling, or Tailwind typography classes (`text-sm`, `font-bold`, `leading-*`, etc.)
- `backend/lib/famichat_web/components/core_components.ex` may be used as a fallback in a pinch

### Spacing
- **No margins.** Use `gap` and space elements only.
- **No hardcoded pixel values** — no `px-[14px]`, no inline `style="margin: 8px"`, nothing
- **No raw Tailwind spacing classes** — no `p-4`, `mt-2`, `mb-6`, etc.
- Maximum **4 spacing units** per layout — if you need more, the layout needs rethinking

### General
- No hardcoded Tailwind classes for color, sizing, or layout beyond what the component system provides
- No inline styles
