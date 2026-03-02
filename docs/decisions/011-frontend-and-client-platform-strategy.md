# ADR 011: Frontend and Client Platform Strategy

**Date**: 2026-03-01
**Status**: Archived — superseded by [ADR 012](012-spa-wasm-client-architecture.md) (2026-03-01)

---

## Context

SPEC.md Path C (decided) requires a browser SPA where OpenMLS runs as WASM so that private keys never leave the device. LiveView-only is explicitly ruled out for message surfaces (server decrypts to render HTML = server sees plaintext). The decision is: what framework powers the SPA, and what is the roadmap for native mobile and desktop clients?

Constraints:
- The crypto layer is already Rust (OpenMLS NIF). This same library compiles to WASM for browser or links natively for iOS/Android/desktop — the crypto is inherently multi-platform.
- The backend is Elixir/Phoenix and will remain so. Phoenix Channels are the message transport. LiveView continues for non-content surfaces (auth, onboarding, settings, admin).
- React is explicitly off the table (developer preference, and React Native's "write once" promise is weaker than advertised given React/RN platform divergence anyway).
- Family messaging at 100–500 person scale does not require native app sophistication at L1–L4. A high-quality web app with a native wrapper is sufficient through most of the validation layers.

---

## Decision

### Web SPA: Svelte

Use **Svelte** (with Vite) for the browser SPA that handles all encrypted message surfaces.

Rationale:
- Compile-time reactivity: no virtual DOM, smallest runtime of the viable options
- Bundle size matters for self-hosted instances on modest hardware
- WASM integration is straightforward via `wasm-bindgen` + Vite
- Developer experience is closer to the "clean and simple" aesthetic of the Elixir ecosystem than React or Vue
- No framework churn burden at the scale Famichat targets

LiveView is **not replaced** — it continues to own auth flows, settings, navigation shell, and admin panel. These surfaces don't process encrypted message content and don't need WASM. The Svelte SPA replaces only the message view surfaces.

### Mobile (L3–L4): Capacitor wrapping the Svelte SPA

Use **Capacitor** to wrap the Svelte SPA as iOS and Android apps when mobile is needed.

Rationale:
- Reuses 100% of the Svelte SPA codebase — no duplicate frontend
- OpenMLS WASM runs in WKWebView/WebView without modification
- Capacitor provides access to native APIs (push notifications, camera, biometrics) when needed
- Sufficient for a family messaging app at L3–L4 scale; native UX gaps are minimal for this use case
- Defers the mobile engineering investment until validated demand exists

Gate: build Capacitor wrapper when L2/L3 makes mobile a blocker, not before.

### Desktop (if/when needed): Tauri

Use **Tauri** if a desktop client is ever required.

Rationale:
- Tauri uses a Rust backend process + the existing Svelte web frontend — no new frontend code
- OpenMLS Rust library links natively in the Tauri process (no WASM overhead)
- Natural fit with the existing Rust/Elixir stack
- Much smaller binaries than Electron

This is explicitly a future decision — desktop is not on the roadmap through L5.

### Native iOS/Android (L5+): Native Swift, evaluated at that time

If Capacitor hits hard limits (deep background processing, lock screen, ARKit, platform-specific UX gaps), write a native Swift client for iOS. At that point, OpenMLS links as a native Rust library via Swift Package Manager — no WASM needed, full performance.

This is **not an architectural decision today** — it's a known exit path from Capacitor if and when it becomes necessary. Evaluate after L3 validation.

---

## Platform Summary

| Platform | Technology | When |
|---|---|---|
| Browser | Svelte SPA + OpenMLS WASM | Before L3 (E2EE gate) |
| iOS/Android | Capacitor wrapping Svelte SPA | When L2/L3 makes mobile a blocker |
| Desktop | Tauri + Svelte SPA | If/when needed (not roadmapped) |
| Native iOS | Swift + OpenMLS Rust lib | If Capacitor hits hard limits at L5+ |

LiveView continues for: auth, onboarding, settings, admin panel, navigation shell.

---

## Performance Budgets (unchanged from SPEC.md)

These apply regardless of client platform:
- Sender → receiver: <200ms (hard requirement — Phoenix Channels problem, not framework problem)
- Typing → display: <10ms (local rendering — any modern framework handles this)
- Encryption: <50ms (OpenMLS WASM budget; Wire has validated this in production via `core-crypto`)

---

## Prerequisites

Path C (and therefore this entire ADR) has one prerequisite: **the OpenMLS → WASM compilation spike must succeed**. OpenMLS added official WASM support via the `js` feature flag (January 2026). If the spike reveals blockers, reassess before investing in the Svelte SPA.

The spike timebox is days, not weeks. If it fails, this ADR is superseded.

---

## Rejected Alternatives

**React + React Native**: React is off the table by developer preference. React Native's code-sharing with React web is weaker than advertised (different rendering model, significant churn). Does not leverage the Rust crypto layer.

**Flutter**: Single Dart codebase for iOS/Android/web/desktop sounds appealing, but Flutter's web output is canvas-rendered (poor accessibility, poor SEO if ever needed), Dart is a third language alongside Elixir and Rust, and `dart:ffi` to Rust adds integration complexity. Doesn't play to the stack's strengths.

**LiveView-only (Path A)**: Explicitly rejected in SPEC.md. Server-side rendering of message content means server sees plaintext. Also breaks multi-device: key lives in browser session only, new device cannot recover old messages.

**Elm**: Principled but niche. WASM story is immature. Community too small for a product that may want contributors.
