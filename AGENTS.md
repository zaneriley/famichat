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
- **All user-visible strings must use `gettext/1`** — no bare string literals in templates. "Famichat" as a brand name is the only exception.

---

## QA Rules — Never commit without verifying

These rules exist because agents repeatedly committed broken code that was never tested.

### Before committing any backend or routing change
- `curl -sv http://localhost:9000/AFFECTED_ROUTE` — check the HTTP status and response body
- If you deleted a function, `grep -r "function_name" lib/` before committing — check for other callers
- If you modified a Plug or router, curl every route that pipeline touches

### Before committing any JS change
- Read the actual API response shape with `curl -s ENDPOINT | python3 -m json.tool`
- Verify field names match what the JS accesses — don't assume
- Check the equivalent working hook for comparison (e.g. login hook vs register hook)

### Before committing any template change
- `mix compile` must be clean (zero errors, no new warnings)
- If you removed a helper function, search all templates for calls to it: `grep -r "function_name" lib/famichat_web/`

### The rule
**If you have not curled the endpoint or seen the actual output, you have not tested it. Do not commit.**

---

## URL / Routing Rules

- **Never hardcode locale in paths.** Use `locale_path(socket, "/path")` or `locale_path(assigns, "/path")` — defined in `FamichatWeb.LiveHelpers`, available in all LiveViews automatically.
- No `/en/...` or `/ja/...` string literals in LiveView `.ex` or `.heex` files
- The `LocaleRedirection` plug handles locale prefixing at the HTTP layer; `locale_path/2` handles it in LiveView navigations

---

## Architecture Rules

- Read `docs/NOW.md` before starting any task — it contains the current known bugs and what's been built
- Read `docs/SPEC.md` for product intent — don't build features marked as deferred or L3+
- Throwaway LiveViews (auth, onboarding) must stay tightly coupled — no abstractions, no shared components beyond what already exists
