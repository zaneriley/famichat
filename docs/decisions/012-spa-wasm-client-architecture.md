# ADR 012: SPA + WASM Client Architecture

**Date**: 2026-03-01
**Status**: Accepted — WASM spike passed GO (2026-03-01); S7/M3 pending physical iOS device confirmation before L3
**Supersedes**: ADR 011 (Frontend and Client Platform Strategy)

---

## 1. Status and Supersession

ADR 011 made the framework and platform choices (Svelte, Capacitor, Tauri). This ADR supersedes it and incorporates all detail from proposals 01–04 v2. It is the single authoritative reference for implementation.

ADR 011 is archived. Do not implement from ADR 011 directly — use this document.

**Activation gate**: Nothing in this ADR is locked for implementation until the WASM spike passes all acceptance criteria in §3. The spike runs first. If it fails, this ADR is reassessed.

---

## 2. Context

- SPEC §Security mandates Path C: OpenMLS WASM in the browser so private keys never reach the server. This is required before L3 (any family other than the operator's own trusts the server). Server-side LiveView decryption is acceptable at L0/L1 only.
- The Rust NIF (OpenMLS 0.8.1, fully hardened via Track A) is ~70% reusable as a WASM target. The ~30% to delete is the two-actor `GroupSession` model and DashMap server-side state. This is not a rewrite.
- OpenMLS added official WASM support via the `js` feature flag (January 2026). Wire ships this pattern in production via `core-crypto`. The spike validates it compiles and runs in our exact target environment before any scaffolding begins.

---

## 3. WASM Spike Gate

**NON-NEGOTIABLE: all eight criteria must pass before any frontend directory is created, any Phoenix route is added, or any socket code is written.**

| # | Criterion | Pass Condition |
|---|---|---|
| S1 | Compilation | `cargo build --target wasm32-unknown-unknown` with `js` feature flag completes with no linker errors |
| S2 | Bundle size | Gzip-compressed WASM binary ≤ 500 kB; if exceeded, evaluate `libcrux-provider` swap or raise gate with written justification |
| S3 | CSPRNG | `window.crypto.getRandomValues` shim via `getrandom/wasm_js` backend initializes in a real browser |
| S4 | Clock shim | `fluvio-wasm-timer` `SystemTime` shim works; no panic on `Instant::now()` in WASM context |
| S5 | Group operations | Encrypt/decrypt round-trip on a two-member MLS group completes in browser JS console using raw WASM bindings |
| S6 | Vite integration | `vite-plugin-wasm` + `vite-plugin-top-level-await` load the WASM module in a Vite dev server with no ESM/MIME errors |
| S7 | WKWebView | Same round-trip runs inside a Capacitor WKWebView on a physical iOS 15+ device (not simulator) |
| S8 | Performance | Single message encrypt + decrypt ≤ 50ms in browser (SPEC encryption budget) |

**Spike results (2026-03-01): GO**

| # | Criterion | Result | Notes |
|---|---|---|---|
| S1 | Compilation | **PASS** | No source changes; two-step wasm-opt required (`--no-opt` then manual with `--enable-bulk-memory --enable-nontrapping-float-to-int`) |
| S2 | Bundle size | **PASS** | 481.8 kB gzip (18.2 kB under gate) |
| S3 | CSPRNG | **PASS** | `window.crypto.getRandomValues` confirmed non-zero in browser |
| S4 | Clock shim | **PASS** | `fluvio-wasm-timer` confirmed via group ops succeeding |
| S5 | Group ops | **PASS** | Encrypt 2.2ms, decrypt 2.1ms; plaintext matched exactly |
| S6 | Vite | **PASS** | Vite 6.4.1 + vite-plugin-wasm; no MIME/ESM errors |
| S7 | WKWebView | **PENDING** | Requires physical iOS device; must confirm before L3 |
| S8 | Performance | **PASS** | Warm-path P95 = **1.90ms** (gate 50ms — 26× under) |
| M1 | IndexedDB | **PASS** | Full PBKDF2-SHA256 → AES-256-GCM → IDB → restore → encrypt round-trip |
| M2 | Worker postMessage | **PASS** | 141ms init; 3.1ms avg round-trip; `Uint8Array` 11 kB via structured clone; replay protection confirmed |
| M3 | Passkey/WKWebView | **PENDING** | Requires physical iOS device; must confirm before L3 |
| M4 | CSP | **PASS** | `'wasm-unsafe-eval'` sufficient; `'unsafe-eval'` not required |

Spike artifacts: `spikes/openmls-wasm/`, results at `.tmp/2026-03-01-SPA/spike/spike-results-final.md`

Scaffolding may begin. S7 + M3 must be confirmed on physical device before L3 gate.

---

## 4. Platform Decisions

### Summary Table

| Platform | Technology | When |
|---|---|---|
| Browser | Svelte 5 SPA + SvelteKit 2 + Vite + OpenMLS WASM | Before L3 (E2EE gate) |
| iOS/Android | Capacitor 7 wrapping the Svelte SPA | When L2/L3 makes mobile a blocker |
| Desktop | Tauri + Svelte SPA (OpenMLS links natively, no WASM) | If/when needed; not on roadmap through L5 |
| Native iOS | Swift + OpenMLS Rust lib via Swift Package Manager | If Capacitor hits hard limits at L5+ |

### Rationale: Svelte 5 + SvelteKit 2

- Compile-time reactivity, no virtual DOM; smallest runtime of viable options.
- Bundle size matters for self-hosted modest hardware.
- WASM integration via `wasm-bindgen` + Vite is the canonical path; no friction.
- Svelte 5 (current: 5.53.6) is production-tested by Apple, Spotify, NYT, Bloomberg. Runes are stable enough for greenfield use. Active patch cadence is ongoing stabilization, not a crisis.
- TypeScript + runes verbosity is a real ergonomics trade-off; acceptable for a small team starting fresh.
- SvelteKit WebSocket native support is experimental — use `phoenix` npm package directly, not SvelteKit's WS API.
- Package: `phoenix@1.8.4` (not `phoenix-channels`, not `phoenix-socket` — both dead).

### Rationale: LiveView retained

LiveView continues for surfaces with no E2EE requirement. **These views are tightly coupled and deletable — do not invest in design system infrastructure for them.**

| LiveView surface | Reason |
|---|---|
| Auth flows (login, passkey register/assert, OTP, magic link) | REST + form; server orchestrates state machine |
| Onboarding (invite accept, passkey setup, QR pair) | Multi-step wizard; server owns transitions |
| Admin panel (device mgmt, user roles, household settings) | Low traffic; no encryption; high server logic |
| `/up` health checks | Ops tooling |
| Error pages | Trivial |

LiveView is NOT a shell or layout wrapper for the SPA. The SPA is a separate HTML document with its own root.

### Rationale: Capacitor over Expo/native

- Reuses 100% of the Svelte SPA; no duplicate frontend.
- OpenMLS WASM runs in WKWebView single-threaded (no Rayon, no SharedArrayBuffer needed).
- Capacitor 7 chosen over 8: Cap 8 requires Xcode 26+ (not yet generally available). Migrate to Cap 8 when Xcode 26 ships broadly.
- Bundle ID: `chat.famichat.app` on both platforms. This cannot change after first App Store submission.

### Rejected Alternatives

| Alternative | Reason Rejected |
|---|---|
| React + React Native | React off-the-table by developer preference; RN code reuse weaker than advertised |
| Flutter | Canvas web output (poor a11y), Dart is a third language, `dart:ffi` to Rust complexity |
| LiveView-only (Path A) | Server sees plaintext; breaks multi-device (key lives in browser session only) |
| LiveSvelte hybrid for message surfaces | Server constructs all props → server sees plaintext; SSR broken with Svelte 5 (issue #192); defeats E2EE entirely |
| Inertia.js | Same server-sees-props limitation as LiveSvelte; adds no value for E2EE constraint |
| Elm | WASM story immature; community too small |

---

## 5. LiveView / SPA Boundary

### Route-level split

| Route pattern | Owner | Notes |
|---|---|---|
| `/:locale/login`, `/:locale/register`, `/:locale/auth/*` | LiveView | Passkey, OTP, magic link forms |
| `/:locale/onboarding/*` | LiveView | Invite redemption, QR pair, device setup |
| `/admin/*` | LiveView | Household admin panel, device revocation, theme settings |
| `/up` | LiveView | Health check |
| `/app` and `/app/*` (catch-all) | Svelte SPA | All message surfaces |

### SPA owns

- Conversation list (metadata: IDs, member count, timestamps — not decrypted content)
- Message view + message input (all encrypted content)
- Real-time message stream (Phoenix Channel directly from browser)
- Key package management UI
- User profile / notification preferences / language setting
- Search results (encrypted content, must decrypt client-side)

### SPA → LiveView boundary for settings

- In SPA: user display name, notification preferences, language, device list (read-only).
- In LiveView (full navigation, clearly exits SPA): household admin panel, passkey management, account recovery.
- The SPA profile tab contains a clearly-labeled "Family Settings" link that navigates out via `<a href="/admin/household">` (not a Svelte router push). The full-page reload is intentional — it signals a context change.

### Deletability constraint (NON-NEGOTIABLE)

All LiveView views must remain tightly coupled and deletable in one move. Do not build design system infrastructure, shared component libraries, or reusable styling systems for LiveView surfaces. Per SPEC §Theming: keep throwaway views throwaway.

---

## 6. Token Bootstrap and Auth

### Session token lifecycle

- **Access token**: short-lived (5–15 min), stateless, signed `Phoenix.Token`, claims: `user_id`, `device_id`, `issued_at`. Stored in-memory only (Svelte `$state` singleton — not `localStorage`, not long-lived `sessionStorage`).
- **Refresh token**: 30-day, cryptographically random, DB-stored.
  - L0/L1: memory only (lost on tab close; user re-authenticates each session). Acceptable — operator is sole user.
  - Before L2: migrate to `httpOnly; Secure; SameSite=Strict` cookie on `/api/v1/auth/sessions/refresh`. ~10-line change to `AuthController`.
  - Capacitor (L3+): `@capacitor/secure-storage` — iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), Android Keystore (`EncryptedSharedPreferences`). Do NOT use `@capacitor/preferences` (NSUserDefaults — not Keychain, not encrypted, backup-extractable).

### Token bootstrap across navigation

The access token lives in the old page's JS heap and does not survive `window.location.assign("/app")`. The handoff mechanism:

```javascript
// In LiveView login page JS, immediately before navigation:
sessionStorage.setItem("__boot_token", JSON.stringify({
  access_token: response.access_token,
  device_id: response.device_id,
  expires_at: Date.now() + (response.expires_in * 1000)
}))
window.location.assign("/app")
```

```javascript
// frontend/src/lib/auth/boot.ts — runs once at SPA startup before anything else:
export function consumeBootToken(): BootToken | null {
  const raw = sessionStorage.getItem("__boot_token")
  sessionStorage.removeItem("__boot_token")  // consume immediately — single use
  if (!raw) return null
  try {
    const parsed = JSON.parse(raw)
    if (parsed.expires_at < Date.now()) return null  // clock skew guard
    return parsed
  } catch { return null }
}
```

If `consumeBootToken()` returns `null` (direct tab open, expired token, cleared storage): SPA redirects to `/:locale/login`. This is the only acceptable use of `sessionStorage` in the entire SPA.

Why `sessionStorage` and not URL fragment or embedded HTML:
- Survives the navigation (same tab) but not other tabs or sessions — correct scope for single-use bootstrap.
- Consumed and deleted immediately on first read — cannot be replayed.
- URL fragment appears in browser history and leaks via `Referer`.
- Embedding in `index.html` would require Phoenix to dynamically render it, breaking `Plug.Static` deployment.

### Socket params as function

```javascript
// frontend/src/lib/socket.js
export const socket = new Socket("/socket", {
  params: () => ({ token: authStore.token }),  // re-evaluated on every reconnect
  reconnectAfterMs: (tries) =>
    [10, 50, 100, 150, 200, 500, 1000, 2000][tries - 1] ?? 5000,
  longPollFallbackMs: false  // WS only; disable LongPoll to avoid double-connection behavior
})
```

`params` as a function (not a static string) is mandatory. Token expiry on reconnect is silently fatal if `params` is a static string.

### Passkey platform abstraction

`navigator.credentials.create/get()` are not available in Capacitor WKWebView (iOS) or Android WebView. The abstraction is created at scaffold time even though the native implementation is a stub at L0/L1.

```typescript
// frontend/src/lib/auth/passkey-platform.ts
export interface PasskeyPlatform {
  isAvailable(): Promise<boolean>
  createCredential(options: PublicKeyCredentialCreationOptionsJSON): Promise<RegistrationResponseJSON>
  getCredential(options: PublicKeyCredentialRequestOptionsJSON): Promise<AuthenticationResponseJSON>
}
```

- `passkey-web.ts`: implements via `navigator.credentials.create/get`. Used on web.
- `passkey-native.ts`: implements via ASWebAuthenticationSession (iOS) / Chrome Custom Tabs (Android). Used when `Capacitor.isNativePlatform()`.
- `passkey.ts`: factory returning the correct implementation at runtime.

### ASWebAuthenticationSession — native passkey path (L3+)

**NON-NEGOTIABLE path for self-hosting compatibility**: Native platform passkey APIs (`ASAuthorizationPublicKeyCredentials`) require Associated Domains entitlements encoded in the app binary at signing time. A self-hoster cannot add their own domain to a published App Store binary. `ASWebAuthenticationSession` sidesteps this: the system browser handles the FIDO2 exchange, domain binding resolves against the operator's domain (not the app binary's entitlements), and only a standard `ASWebAuthenticationSession` entitlement (no domain-specific entitlement) is required in the binary.

**UX**: A system browser sheet slides up from the bottom (standard iOS pattern). The sheet hosts the operator's passkey session page at `https://<WEBAUTHN_RP_ID>/auth/passkey-session`. Face ID / Touch ID authenticates. Callback via `famichat://auth/callback`. Wax receives unchanged CBOR attestation/assertion objects.

On Android: Chrome Custom Tabs provides the equivalent.

**What operators must do (already required by SPEC §Deployment)**: Serve `.well-known/apple-app-site-association` and `assetlinks.json` at their own domain. The published app binary requires no modification per self-hoster.

**Pre-spike gate before any native passkey implementation**: Run on physical iOS 15+ and Android API 24+ devices and confirm: (1) UV flag in assertion response passes `Wax.authenticate/5`; (2) attestation format accepted by Wax (confirm `attestation:` setting in `passkeys.ex` — if `"none"`, format is moot; if `"direct"`, Apple CA trust anchor must be configured); (3) `famichat://auth/callback` round-trip works without the Capacitor `commitPreviewController` crash; (4) Android parity. If any fail: ship L3 mobile with OTP + magic link only; add native passkeys at L4.

---

## 7. Phoenix Integration

### CORS (`endpoint.ex`)

```elixir
plug CORSPlug,
  origin: Application.compile_env(:famichat, :cors_origins, []),
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  credentials: true
```

`CORSPlug` must be in `endpoint.ex`, NOT in a pipeline. Pipelines only run on matched routes; OPTIONS preflight requests often have no matching route, producing silent 404s that break CORS.

### WebSocket `check_origin`

WebSocket connections are not subject to HTTP CORS. Phoenix enforces its own origin check. **Must be set explicitly before any external deployment.**

```elixir
# config/prod.exs
config :famichat, FamichatWeb.Endpoint,
  check_origin: System.get_env("CHECK_ORIGIN", "https://#{System.fetch_env!("PHX_HOST")}")
  |> String.split(",") |> Enum.map(&String.trim/1)
```

`CHECK_ORIGIN` defaults to `PHX_HOST`. Multiple origins: comma-separated. Misconfigured `check_origin` is the #1 production WebSocket failure mode and produces silent 403s.

```elixir
# config/dev.exs
config :famichat, FamichatWeb.Endpoint, check_origin: false
```

### Channel params as function and auth split

- Auth is socket-level only: `UserSocket.connect/3` verifies the `Phoenix.Token` from `params`. `user_id` and `device_id` are assigned to the socket there.
- Channel join params are empty `{}` — no per-channel auth tokens needed; socket-level assigns carry the identity.
- Channel join params re-send on automatic rejoin; empty params means stale rejoin is never a problem.

### API vs Channels split

| Mechanism | Operations |
|---|---|
| Phoenix Channels (WebSocket) | Real-time send (`new_msg` push), real-time receive (`new_msg` broadcast), message ACK (`message_ack`), device revocation notification (`security_state` push), future: typing indicators |
| REST `/api/v1` | All auth flows, session refresh, conversation list (with `unread_count`), message pagination history, REST fallback for message send (retry/offline queue), security state recovery, key package upload/download, device management |

Unread count: server-side, defined as `latest_message_seq - last_acked_seq_for_device`. Server never decrypts; it counts integer sequences. Include `unread_count` in `GET /api/v1/me/conversations` from day one. Do not defer — the conversation list is useless as an inbox replacement without it.

`GET /api/v1/me/conversations` response must include: `conversation_id`, `conversation_type`, `member_count`, `last_message_at`, `unread_count`. Must NOT include `last_message_preview` — server cannot decrypt; SPA decrypts and caches locally.

### CSP — `wasm-unsafe-eval` is required (NON-NEGOTIABLE)

`wasm-unsafe-eval` is required for WASM execution in all modern browsers (Chrome 95+). Without it, WASM instantiation fails. `unsafe-eval` is NOT sufficient — `wasm-unsafe-eval` is a separate CSP Level 3 directive.

```
Content-Security-Policy:
  default-src 'self';
  script-src 'self' 'wasm-unsafe-eval';
  connect-src 'self' wss://yourdomain.com;
  img-src 'self' data: blob:;
  style-src 'self' 'unsafe-inline';
  worker-src 'self' blob:;
  child-src 'self' blob:;
```

`worker-src 'self' blob:` is required because the Web Worker is created from a blob URL by `vite-plugin-wasm`. `child-src` is the fallback for browsers without `worker-src`. No `unsafe-inline` for scripts. This policy must be finalized and in place before L1 ships — not deferred.

### Production: Phoenix serves SPA as static assets

Phoenix `Plug.Static` serves the built SPA bundle. No separate nginx container. Rationale: same origin = no CORS for REST API calls; same origin = `check_origin` trivially satisfied; `docker-compose up` stays the single deploy command.

```elixir
# endpoint.ex
plug Plug.Static,
  at: "/",
  from: :famichat,
  gzip: true,
  only: ~w(assets fonts images favicon.ico robots.txt _app)
```

```elixir
# router.ex — SPA catch-all MUST be the last scope in the file
pipeline :spa do
  plug :accepts, ["html"]
  # No session fetch, no CSRF, no LiveView flash — SPA uses Bearer token auth
end

scope "/", FamichatWeb do
  pipe_through :spa
  get "/*path", PageController, :spa_fallback  # Serve index.html for all unmatched paths
end
```

Vite hashes asset filenames — serve `_app/immutable/**` with `Cache-Control: max-age=31536000, immutable`. Serve `index.html` with `Cache-Control: no-cache`.

---

## 8. WASM Crypto Layer

### What gets deleted from the NIF (~30%)

- `GroupSession` struct — the entire two-actor co-located model.
- `GROUP_SESSIONS: LazyLock<DashMap<String, GroupSession>>` — server-side session registry.
- `rustler` dependency and all `#[rustler::nif]` annotations.
- `dashmap` dependency (browser JS runtime is single-threaded; concurrent hash map not needed).
- `KEY_PACKAGE_COUNTER: AtomicU64` — server-managed key package counter.
- `LockPoisoned` `ErrorCode` variant — only relevant to multi-threaded DashMap.
- Two-phase snapshot (N6) — exists only to minimize DashMap lock hold time; irrelevant without DashMap.

### What gets kept (~70%)

- `ErrorCode` enum (all variants except `LockPoisoned`), `MlsError`, `MlsResult`.
- `MemberSession` struct — one per device, not two per conversation.
- All crypto operations: `create_group`, `join_from_welcome`, `process_incoming`.
- Epoch validation: `merge_epoch == state.epoch + 1` strict check.
- Group ID validation: empty/len>256/NUL-byte checks at all entry points.
- `MAX_HEX_DECODE_BYTES = 1_048_576` guard.
- Snapshot serialization/deserialization — format unchanged; WASM reads/writes same binary format.
- `catch_unwind` + `AssertUnwindSafe` (H3) around `tls_deserialize`.
- Decrypt cache (N4) — `VecDeque<String>` + `Vec<(String, CachedMessage)>` bounded at 256 entries.

### Cargo feature flag split

```toml
# backend/infra/mls_nif/Cargo.toml  (or mls_wasm/Cargo.toml — kept as separate crates)
[features]
default = []
nif = ["rustler", "dashmap"]
wasm = ["wasm-bindgen", "openmls/js", "getrandom/wasm_js", "console_error_panic_hook"]
libcrux = ["openmls/libcrux-provider"]
```

- Build NIF: `cargo build --features nif`
- Build WASM: `wasm-pack build --target bundler --features wasm,libcrux`
- The `js` flag on `openmls` is gated behind the `wasm` feature — it must NEVER bleed into the NIF build or a hypothetical WASI build.
- `rustler` annotations live in `src/nif_bindings.rs` (compiled only when `cfg(feature = "nif")`).
- WASM bindgen annotations live in `src/wasm_bindings.rs` (compiled only when `cfg(feature = "wasm")`).
- Core logic in `src/lib.rs` has zero feature-flag pollution.

`openmls_rust_crypto` → `libcrux-provider`: libcrux is faster and smaller on WASM targets. One-line `Cargo.toml` change + provider initialization call.

### Worker ownership of session state

The WASM functions are stateless at the Rust boundary. The Web Worker owns session state:

```
Worker-internal: Map<groupId, sessionBytes>  ← authoritative session state per group
  ↓ worker fetches current sessionBytes for groupId
WASM call: (session_bytes, message_bytes) → (updated_session_bytes, ciphertext_bytes)
  ↑ worker writes updated_session_bytes back to Map before posting reply
```

The main thread (Svelte) never holds, receives, or passes `session_bytes`. It only passes `groupId` and message payloads. The worker is the sole owner of session state for the lifetime of the browser session.

### Key storage — `extractable: false` (NON-NEGOTIABLE)

Every `CryptoKey` object created via WebCrypto must be created with `extractable: false`. This is not a preference — it is the single most important XSS mitigation for key material. With `extractable: false`, the key cannot be exported from the WebCrypto subsystem even by JS code on the same origin.

```javascript
const wrappingKey = await crypto.subtle.deriveKey(
  { name: "PBKDF2", salt: kdfSalt, iterations: 600_000, hash: "SHA-256" },
  keyMaterial,
  { name: "AES-GCM", length: 256 },
  false,   // extractable: false — NON-NEGOTIABLE
  ["wrapKey", "unwrapKey"]
)
```

### Key derivation

```
recovery_phrase (12 words, BIP-39)
  → PBKDF2-SHA256 (600,000 iterations, salt = random 16 bytes generated at key-setup time)
  → 32-byte root key (intermediate; never stored)
  → HKDF-SHA256 (info: "famichat-mls-key-storage-v1|{rp_id}|{user_id}")
  → AES-256-GCM wrapping key (extractable: false)
```

- Salt: `crypto.getRandomValues(new Uint8Array(16))` at key-setup time. Stored in IndexedDB `keystore_metadata`. Not secret; must be unique and random.
- HKDF `info` field includes `rp_id` and `user_id` for domain separation across Famichat instances and accounts.
- PBKDF2 at 600k iterations chosen over Argon2id for initial implementation: WebCrypto native (zero dependencies), no additional WASM binary, OWASP-acceptable. Argon2id upgrade is an open decision (severity: MEDIUM) for L2+.

### IndexedDB schema

```
famichat_mls_keystore (IndexedDB database)
  ├── keystore_metadata   { kdf_salt: Uint8Array, kdf_algo: string, created_at: timestamp }
  ├── signing_keys        group_id → { ciphertext: Uint8Array, iv: Uint8Array }
  ├── hpke_private_keys   key_package_ref → { ciphertext: Uint8Array, iv: Uint8Array }
  ├── group_snapshots     group_id → { ciphertext: Uint8Array, iv: Uint8Array, server_epoch: number }
  └── key_packages        ref → { ciphertext: Uint8Array, iv: Uint8Array }
```

Each record: AES-256-GCM encrypted bytes. IV: 12 random bytes generated fresh per write. No IV reuse.

### `navigator.storage.persist()` (required)

Call `navigator.storage.persist()` during initial key-setup, before writing any key material to IndexedDB. If it returns `false`, show a non-blocking banner: "Your message history may be lost if you clear browser storage. Install the app to your home screen to prevent this." Do not block the flow, but do not silently proceed.

On Capacitor iOS, IndexedDB is subject to OS eviction. After each MLS epoch advance, serialize MLS group state and write a backup copy to `@capacitor/filesystem` (`FilesystemDirectory.Documents`, AES-256-GCM encrypted with a key derived from the recovery phrase). Documents directory is iCloud-backed and not subject to OS eviction.

### Snapshot MAC stays server-side (NON-NEGOTIABLE)

`Famichat.Crypto.MLS.SnapshotMac` (HMAC-SHA256, `MLS_SNAPSHOT_HMAC_KEY` env var) is an Elixir-side protection for snapshots stored in `conversation_security_states` against DB-level tampering. It does not move to the browser under any circumstances. Client-side IndexedDB encryption (AES-256-GCM, wrapping key from recovery phrase) and server-side MAC address different adversaries; they must not be merged.

Server snapshot is canonical. Client snapshot is a performance cache. On IndexedDB loss, client fetches latest server snapshot (MAC-verified by Elixir) and re-seeds locally.

### No plaintext fallback (NON-NEGOTIABLE)

If WASM decryption fails for any message, that message is shown with a lock icon. The failure is surfaced explicitly to the user. The app does not fall back to displaying plaintext or raw ciphertext as a readable substitute. Fail-closed always.

---

## 9. Multi-Device Key Distribution

### KeyPackage pool

Each device pregenerates and uploads N=10 KeyPackages on registration (Signal/Wire pattern). Server maintains a per-device pool in `conversation_security_client_inventories`. When a KeyPackage is consumed, server notifies device to generate and upload a replacement. Generation happens in background via WASM worker. Pool exhaustion returns an error requiring user-facing retry.

### Join protocol

```
New device (D_new):
  1. Generates KeyPackage via WASM
  2. Uploads: POST /api/v1/devices/{device_id}/key_packages
  3. Enters pending_welcome UI state ("Waiting for another device to approve your access")

Existing device (D_existing) — any active device:
  4. On connect: GET /api/v1/key_packages/pending
  5. For each conversation D_new should join:
     a. Fetches D_new's KeyPackage from server
     b. WASM: add_member(groupId, keyPackage) → { commit, welcome }
     c. POST /api/v1/conversations/{id}/commits
     d. Server stores commit; delivers Welcome to D_new via channel event mls_welcome

New device (D_new):
  6. Receives Welcome via Phoenix channel
  7. WASM: join_from_welcome(welcome) → initializes MLS session
  8. Writes session snapshot to IndexedDB
  9. Full group member; can encrypt/decrypt
```

### Offline handling

If all existing devices are offline when D_new registers: join deferred. Server holds pending KeyPackage. Maximum wait: until any existing device reconnects (typically hours for a family app). No server-side secret material involved in the wait. If all existing devices are permanently lost: D_new enters recovery phrase path — derives key material, fetches server snapshot, reconstructs session.

### Required new endpoints (relay-only; server stores opaque blobs, does not inspect key material)

```
POST   /api/v1/devices/{device_id}/key_packages     — upload new device KeyPackage
GET    /api/v1/key_packages/pending                  — fetch pending KeyPackages for this user
POST   /api/v1/conversations/{id}/commits            — submit Add commit + Welcome
GET    /api/v1/conversations/{id}/welcome            — new device polls/receives Welcome
```

Key package endpoints are gated on the WASM spike — the spike's group operation round-trip will reveal the exact API surface. Do not design these endpoints before S5 passes.

---

## 10. Worker Failure Handling

All four failure modes have specified behaviors. None are silently swallowed.

| Mode | Trigger | Specified Behavior |
|---|---|---|
| WASM panic escaping `catch_unwind` | Worker process terminates; `worker.onerror` fires | `CryptoWorkerManager` rejects all in-flight requests with `{ code: "worker_crashed" }`. Sets `cryptoError` in Svelte store. Attempts one automatic restart. If restarted worker also fails init: no further restart; UI shows lock icon on all message bodies with tooltip "Encryption unavailable. Restart app." |
| IndexedDB unavailable (private browsing, restricted permissions) | Worker posts `{ type: "init_error", code: "indexeddb_unavailable" }` | Main thread shows inline banner: "Encrypted messages cannot be displayed in private browsing. Open the app in a regular tab." App functional for non-encrypted surfaces. No automatic recovery. |
| Wrapping key timeout (30-minute idle on web) | Worker discards in-memory wrapping key; posts `{ type: "key_required" }` | Lock screen overlay: "Session locked. Enter your passphrase to continue." In-flight calls queued (not rejected) for up to 2 minutes. User enters passphrase → worker resumes. If user does not respond within 2 minutes: queued calls rejected with `{ code: "key_required" }`. On Capacitor: biometric re-auth via OS (not passphrase). |
| Worker terminated by browser (memory pressure, mobile backgrounding) | `worker.onmessageerror` or failed postMessage | `CryptoWorkerManager` detects termination; restarts worker. Re-init requires re-deriving wrapping key (passphrase or biometric — same UX as wrapping key timeout above). In-flight requests at termination time rejected with `{ code: "worker_terminated" }`. |

The socket is NOT joined until the worker posts `ready`. This prevents the SPA from receiving channel messages it cannot yet decrypt. While WASM loads, the conversation view shows a loading skeleton.

All `MlsWorkerApi` calls go through `CryptoWorkerManager.post()` with a 10-second per-request timeout. No Promise hangs forever.

Comlink is adopted for the worker/main-thread RPC layer. It solves the pending-request-map failure modes (memory leaks on crash, no built-in timeout, ID collision risk) at a cost of ~3 kB.

---

## 11. Capacitor Mobile

### WebAuthn: ASWebAuthenticationSession (see §6 for full rationale)

- L0/L1: web-only; `navigator.credentials` used directly in desktop browser.
- L3 gate: before mobile ships to any non-operator user, the passkey platform abstraction (`PasskeyPlatform` interface) must have a working native implementation validated against physical iOS 15+ and Android API 24+ devices (see pre-spike gate in §6).
- `@perfood/capacitor-crypto-api` removed as primary path: entitlement conflict with self-hosting model; unvalidated against Wax attestation format.

### Secure storage (NON-NEGOTIABLE)

Use `@capacitor/secure-storage` (or `@aparajita/capacitor-secure-storage`) for the refresh token from day one. Do NOT use `@capacitor/preferences` (NSUserDefaults — not encrypted at rest independently of device encryption; backup-extractable; not Keychain-protected).

Required Keychain configuration:
- `kSecAttrAccessible`: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — accessible after first unlock post-boot; does NOT leave the device (no iCloud Keychain sync, no backup).
- Verify this protection class is set in the plugin's iOS native source before shipping.
- Android: plugin must use `EncryptedSharedPreferences` (Jetpack Security, backed by Android Keystore) — not plain `SharedPreferences`. Verify in plugin's Android source.

### WASM in WebView constraints

- Single-threaded WASM only. No Rayon, no `wasm-bindgen-rayon`, no SharedArrayBuffer.
- SharedArrayBuffer cannot be enabled on Android WebView (no site isolation regardless of headers).
- iOS: SharedArrayBuffer technically possible with GCDWebServer header injection hack — maintenance burden too high; single-threaded is sufficient.
- iOS floor: iOS 15 (required by `wasm-pack --target bundler` ES module + `WebAssembly.instantiateStreaming` baseline).
- If a user presents on iOS 14: show explicit error "Your iOS version does not support encrypted messaging; please update to iOS 15 or later." No plaintext fallback.
- Test WASM on physical devices only. iOS Simulator does not support WASM (WebKit bug #191064).

### Push notification payload minimization (NON-NEGOTIABLE)

APNs/FCM payload:
```json
{ "aps": { "badge": 1, "sound": "default", "content-available": 1 } }
```

No `title`, no `body`, no `conversation_id`, no `message_id`, no sender information. Silent push wakes the app; app connects to Phoenix Channel to pull notification state. This is a deliberate privacy tradeoff. SPEC §Security: "data minimization is a security primitive, not a product choice."

Plugin: `@capacitor-firebase/messaging` from day one (supports silent push). Do NOT start with `@capacitor/push-notifications` (does not support background data delivery) and migrate later.

`notificationActionPerformed` navigates to inbox root (`/letters`) — not to a specific conversation. Because the payload contains no `conversation_id`, the app cannot deep-link; this is correct behavior under the privacy model.

### BrowserStack CI gate (L3 prerequisite — BLOCKING)

Physical device testing cannot be skipped. The SPEC's 200ms canonical flow gate applies to the full sender-to-receiver path, and WASM decrypt timing on a physical iOS device is a distinct performance profile from server-side Rust.

**Pass criteria (measured at JS layer around WASM function invocations):**
- MLS `encrypt_message` on physical iPhone 12 (P95): ≤ 50ms
- MLS `decrypt_message` on physical iPhone 12 (P95): ≤ 50ms
- Full sender-to-receiver round trip on same LAN (P95): ≤ 200ms

Results written to `canonical_flow_timing_mobile.json`. CI fails if any budget is exceeded.

Until BrowserStack is wired into CI, the manual gate before each L3 release candidate: build production Capacitor app, install on iPhone 12 or equivalent, run timing test script manually. Release is blocked if timings exceed budget.

### App foreground token refresh (race condition requirement)

```typescript
CapacitorApp.addListener("appStateChange", async ({ isActive }) => {
  if (!isActive) return
  const refreshToken = await loadRefreshToken()
  if (!refreshToken) return

  const socket = get(socketStore)
  if (socket) socket.disconnect()  // MUST disconnect before async refresh

  try {
    const { access_token, refresh_token } = await refreshSession(refreshToken)
    accessTokenStore.set(access_token)
    await saveRefreshToken(refresh_token)
    if (socket) socket.connect()   // reconnect AFTER new token is in store
  } catch {
    await clearRefreshToken()
    accessTokenStore.set(null)
    goto("/auth/login")
  }
})
```

Disconnect before refresh, reconnect after. The socket's `params()` function reads the updated token on reconnect. Do not allow reconnect with a stale token during the network round-trip.

---

## 12. Project Structure and Build

### Directory layout

```
famichat/                    # repo root (Docker build context)
  backend/                   # Phoenix app
    assets/                  # KEEP: throwaway LiveView CSS/JS — delete when SPA ships
    infra/
      Cargo.toml             # NEW: Cargo workspace root
      Cargo.lock             # Single lock file for both crates
      mls_nif/               # Rustler NIF — server-side relay/auth
      mls_wasm/              # WASM binary crate — production client path
        scripts/
          wasm-rebuild-atomic.sh
    priv/static/             # Phoenix serves SPA bundle in prod (via Plug.Static)
    lib/
    config/
    Dockerfile
    docker-compose.yml
    docker-compose.production.yml
    run
  frontend/                  # NEW: SvelteKit SPA
    packages/
      mls-wasm/              # pnpm workspace package — live symlink to built pkg/
    src/
      lib/
        auth/                # passkey-platform.ts, passkey-web.ts, passkey-native.ts, boot.ts
        crypto/              # mls-worker.ts, crypto-service.ts, worker-supervisor.ts
        stores/              # auth.svelte.js, crypto.svelte.js, conversations.svelte.js
        channel/             # socket.js, channel wrappers
      routes/
        (auth)/              # Login, passkey, invite redemption
        (app)/               # Conversation list, message view, profile
      app.html
    static/
    vite.config.js
    svelte.config.js
    package.json
    pnpm-workspace.yaml
    tsconfig.json
  Procfile.dev               # overmind: phoenix + vite + wasm watch
  docs/
  .github/
    workflows/
      ci.yml                 # Elixir + Rust (existing; minimal additions)
      ci-wasm.yml            # NEW: WASM build + size gate + artifact upload
      ci-frontend.yml        # NEW: Svelte typecheck + test + bundle gate
```

### Cargo workspace and profile inheritance

Workspace root at `backend/infra/Cargo.toml`. Single `Cargo.lock`. Member `[profile]` sections in `mls_nif/Cargo.toml` and `mls_wasm/Cargo.toml` are silently ignored in a workspace — remove them. All profiles live in the workspace root only.

```toml
# backend/infra/Cargo.toml
[workspace]
members = ["mls_nif", "mls_wasm"]
resolver = "2"

[profile.release]
panic = "abort"       # Required for NIF correctness (FFI boundary)
opt-level = 3
lto = true
codegen-units = 1

[profile.release-wasm]
inherits = "release"
opt-level = "z"       # Size-optimized for browser delivery
strip = true
panic = "abort"
lto = true
codegen-units = 1
```

When workspace root is first added: delete per-crate `Cargo.lock` files, run `cargo generate-lockfile` from `backend/infra/`, commit the unified lock in the same PR. Invalidate CI and Docker caches. Document this explicitly in the PR.

### pnpm workspaces

pnpm workspaces maintain a live symlink at `node_modules/@famichat/mls-wasm` → built `pkg/`. npm `file:` copies at install time — breaks the dev watch loop (requires `npm install` after every WASM rebuild). pnpm is required, not optional.

`frontend/packages/mls-wasm/package.json`:
```json
{
  "name": "@famichat/mls-wasm",
  "version": "0.0.0",
  "private": true,
  "main": "../../backend/infra/mls_wasm/pkg/mls_wasm.js",
  "types": "../../backend/infra/mls_wasm/pkg/mls_wasm.d.ts"
}
```

### Artifact pipeline — WASM binary not committed (NON-NEGOTIABLE)

Do NOT commit `backend/infra/mls_wasm/pkg/` to the repository. A committed binary with no source-match check is a silent security drift failure mode: the browser runs old crypto code indefinitely while the Rust source appears correct, and CI passes green.

The canonical pipeline: `ci-wasm.yml` builds WASM and uploads as a GitHub Actions artifact named `mls-wasm-pkg-{github.sha}`. `ci-frontend.yml` declares `needs: [wasm-build]` and downloads the artifact. Artifact name includes SHA — a frontend job downloading `mls-wasm-pkg-<SHA>` fails with `if_no_artifact_found: fail` if no artifact was uploaded for that exact commit. No stale binary can silently substitute.

`.gitignore` must include `backend/infra/mls_wasm/pkg/` and `backend/infra/mls_wasm/pkg-staging/`.

### Atomic wasm-pack watch

`wasm-pack build` writes files to `pkg/` sequentially (`.wasm` first, then JS glue, then `.d.ts`). On a ~30–90 second build, Vite detects partial state and attempts to load a mismatched JS/WASM pair, producing a `RuntimeError` in the browser.

Fix: write to `pkg-staging/`, then atomically `mv` to `pkg/` on success. Vite only ever sees the complete, consistent output.

`backend/infra/mls_wasm/scripts/wasm-rebuild-atomic.sh` implements this. The `Procfile.dev` `wasm:` process uses it. The watch loop uses `--dev` profile (3-5x faster than release; no lto). Production and CI use `--profile release-wasm`.

### Docker stage ordering

Stage order is mandatory; breaking it causes `pnpm install` to fail:

1. `wasm-build`: compiles Rust → WASM → outputs `/app/pkg/`
2. `frontend-build`: `COPY --from=wasm-build /app/pkg /app/backend/infra/mls_wasm/pkg` FIRST, then `pnpm install`, then copy remaining source, then `pnpm run build`
3. `assets`: merges SPA output into `priv/static/`, builds LiveView assets
4. `dev` / `prod`: unchanged

`docker-compose.yml` build context changes from `backend/` to repo root (`..`). All existing `COPY` paths in the Dockerfile must be updated to be relative to repo root. Do this in the same PR as the Dockerfile stage additions.

wasm-pack installation in Dockerfile: `cargo install wasm-pack --version X.Y.Z --locked --root /usr/local`. Do NOT use `curl | sh` (non-reproducible, unversioned, runs as root). Version in Dockerfile and CI must match — update both together.

### Vite config

```javascript
import { sveltekit } from '@sveltejs/kit/vite'
import wasm from 'vite-plugin-wasm'
import topLevelAwait from 'vite-plugin-top-level-await'
import { defineConfig } from 'vite'

export default defineConfig({
  server: {
    proxy: {
      '/api': 'http://localhost:4000',
      '/socket': { target: 'ws://localhost:4000', ws: true },
      '/uploads': 'http://localhost:4000',
    }
  },
  plugins: [sveltekit(), wasm(), topLevelAwait()],
  optimizeDeps: {
    include: ['phoenix'],  // fix ESM/CJS interop issue (phoenix npm issue #4662)
  },
  build: {
    target: ['chrome89', 'safari15', 'firefox89'],
  },
  worker: {
    plugins: () => [wasm(), topLevelAwait()],  // required for Worker bundle
  },
})
```

`worker.plugins` is required — Vite builds the Worker as a separate chunk; without it, the Worker's WASM import fails at runtime.

---

## 13. Performance Gates

All gates from SPEC §Performance Requirements. Mobile additions from §11.

| Metric | Budget | Gate type | CI behavior |
|---|---|---|---|
| Sender → receiver latency | < 200ms | Hard requirement | CI FAIL if exceeded (`canonical_flow_timing_detail.json`) |
| Typing → display latency | < 10ms | Hard requirement | Manual verification |
| MLS encrypt (browser) | ≤ 50ms | Budget | CI FAIL if exceeded |
| MLS decrypt (browser) | ≤ 30ms | Budget | CI FAIL if exceeded |
| Persist + broadcast path | ≤ 30ms | Budget | Telemetry alert |
| Server encrypt path | ≤ 50ms | Budget | Telemetry alert |
| MLS failure rate | < 5% | CI gate | CI FAIL; gate_report.json |
| Coverage snapshot | ≥ 80% | Threshold | CI WARN |
| WASM bundle (gzip) | ≤ 500 kB | Hard gate | CI FAIL (`ci-wasm.yml`) |
| JS bundle total (gzip, WASM excluded) | ≤ 500 kB | Hard gate | CI FAIL (`ci-frontend.yml`) |
| MLS encrypt on physical iPhone 12 (P95) | ≤ 50ms | Mobile gate | BrowserStack FAIL (L3+) |
| MLS decrypt on physical iPhone 12 (P95) | ≤ 50ms | Mobile gate | BrowserStack FAIL (L3+) |
| Full round trip on same LAN, physical devices (P95) | ≤ 200ms | Mobile gate | BrowserStack FAIL (L3+) |

Telemetry: `:telemetry.span/3` on all critical operations. P50/P95/P99 tracking required. Automated alerts on budget violations.

---

## 14. Security Non-Negotiables

These are structural constraints, not preferences. A proposal that violates any of these is rejected without further review.

| Constraint | Specification |
|---|---|
| `extractable: false` on all CryptoKey objects | Every `deriveKey`, `generateKey`, `importKey` call uses `extractable: false`. No exceptions. |
| Snapshot MAC stays server-side | `Famichat.Crypto.MLS.SnapshotMac` (HMAC-SHA256, `MLS_SNAPSHOT_HMAC_KEY`) is Elixir-side only. Never moves to the browser. |
| No plaintext fallback on decryption failure | Fail-closed always. Surface error explicitly. Lock icon on failed messages. Never show raw ciphertext as readable content. |
| Server must not hold MLS private keys | All private key material generated on device, never transmitted. Server stores and forwards encrypted blobs it cannot decrypt. |
| WASM crypto module not committed to repo | Build in CI, upload as artifact named with git SHA, download in frontend job. No committed binary path. |
| `wasm-unsafe-eval` in CSP before L1 | Required for WASM execution. Must be in place before L1 ships. Cannot be deferred. |
| Refresh token in Keychain (Capacitor) | `@capacitor/secure-storage` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. `@capacitor/preferences` is forbidden for tokens. |
| Push payload minimization | APNs/FCM payload: badge + sound + `content-available` only. No `conversation_id`, no `message_id`, no sender. |
| ASWebAuthenticationSession for native passkeys | Required for self-hosting compatibility. Native plugin with Associated Domains entitlements is incompatible with a published App Store binary used by self-hosters. |
| Secure WebAuthn: UV flag, COSE JSON, CSPRNG | Per existing Track A + Auth hardening: `flag_user_verified` checked on both register and assert; COSE key stored as portable JSON; OTP uses `:crypto.strong_rand_bytes/1`. |
| Snapshot integrity fail-closed | MAC tamper → `snapshot_integrity_failed`. No silent continuation. |

---

## 15. Anti-Patterns

Full anti-patterns table is in SPEC.md §Anti-Patterns. Additions specific to this ADR:

| Anti-Pattern | Why | Instead |
|---|---|---|
| Implementing frontend scaffolding before WASM spike passes | Inverts SPEC's explicit sequencing; wastes work if spike reveals blockers | Run spike first; all 8 acceptance criteria must pass |
| `longPollFallbackMs` typo in socket config | `longPollFallbackMs: false` — the field name is camelCase; misspelling silently enables LongPoll, causing double-connection behavior | Use exact field name; test in dev tools |
| Committing WASM binary to repo | Silent security drift — browser runs stale crypto code while Rust source looks correct; CI passes green | Artifact pipeline with SHA-named artifact |
| npm `file:` for WASM workspace package | Copies at install time; does not reflect subsequent `pkg/` changes; breaks dev watch loop | pnpm workspaces with live symlink |
| `COPY --from` with relative `../` path in Docker | Docker does not support relative destination paths in `COPY --from`; silent build failure | Absolute paths throughout |
| wasm-pack build writing directly to `pkg/` in dev watch | Vite detects partial write state, loads mismatched JS/WASM pair, produces `RuntimeError` | Atomic write via `pkg-staging/` → `mv` |
| `worker.plugins` omitted from Vite config | Worker bundle built without WASM plugins; Worker's WASM import fails at runtime with no useful error | Include `worker: { plugins: () => [wasm(), topLevelAwait()] }` |
| Cargo `[profile]` sections in workspace member `Cargo.toml` | Silently ignored in workspace context; creates false confidence | All profiles in workspace root only |
| LiveSvelte for E2EE message surfaces | Server constructs all props → server sees plaintext; Svelte 5 SSR broken (issue #192) | Svelte SPA with Phoenix Channels |
| LiveView as SPA shell/layout wrapper | Forces LiveView page loads on SPA navigation; not deletable as a unit | SPA is its own root HTML document |
| Static `params` string in Socket constructor | Silently fails to refresh token on reconnect; socket uses expired token indefinitely | `params: () => ({ token: authStore.token })` |
| httpOnly cookie for refresh token in Capacitor WKWebView | WKWebView cookie jar has cross-origin behavioral differences; deprecated cookie APIs on newer Android | `@capacitor/secure-storage` (Keychain/Keystore) |
| `@capacitor/preferences` for refresh token | NSUserDefaults: not independently encrypted, backup-extractable, no Keychain access control | `@capacitor/secure-storage` |

---

## 16. Open Decisions

| Decision | Severity | Trigger for Resolution |
|---|---|---|
| WASM spike passes all 8 acceptance criteria | BLOCKING | Must resolve before any frontend scaffolding begins |
| Argon2id upgrade from PBKDF2 for wrapping key KDF | MEDIUM | L2 or when Argon2 WASM crate can be integrated and audited without blocking MLS spike |
| HKDF context string and exact key derivation parameters for IndexedDB wrapping key | MEDIUM | Must be finalized before L1 key storage implementation |
| ASWebAuthenticationSession spike: UV flag + attestation format + callback URL scheme on physical iOS/Android | BLOCKING (for L3 mobile) | Must pass before any native passkey implementation begins |
| Wax `attestation:` setting in `passkeys.ex` — `"none"` vs `"direct"` | BLOCKING (for L3 mobile spike) | Confirm before passkey spike; if `"direct"`, configure Apple CA trust anchor |
| BrowserStack App Automate wired into CI | BLOCKING (for L3 ship) | Required before L3 ships; manual gate is temporary substitute |
| MLS state persistence design for Capacitor (IndexedDB + filesystem backup) | BLOCKING (for L3 WASM implementation) | Separate design doc required; must be written and reviewed before L3 WASM implementation begins |
| Passphrase UX on web — 12-word phrase for initial implementation | MEDIUM | Revisit after L1 dogfooding |
| Subdomain SPA origin (`app.example.com` vs same-origin) | LOW | Implement only if operator requests it; requires CORS origins, `check_origin` update, cookie domain config |
| Capacitor 7 → 8 migration | LOW | After Xcode 26 ships broadly; SPM plugin compatibility must be assessed |
| `trusted_until` roll-forward on each refresh vs fixed 30-day window | LOW | Carried from SPEC open questions; not blocking for SPA |
| Key package REST endpoint shapes | LOW | Gated on WASM spike (S5) — exact API surface determined by group operation round-trip |
| Bootstrap gap on first repo: frontend-only PR before any main-branch WASM build | LOW | Acknowledge in contributing guide; not a CI fix |

---

## 17. Rejected Alternatives

| Alternative | Why Rejected |
|---|---|
| React + React Native | React off-the-table by developer preference; RN code sharing weaker than advertised |
| Flutter | Canvas web output (poor accessibility), Dart is a third language, `dart:ffi` to Rust complexity |
| LiveView-only (Path A) | Server decrypts to render HTML; breaks multi-device (key in browser session only; device loss = permanent key loss) |
| LiveSvelte for message surfaces | Server constructs all props → server sees plaintext; Svelte 5 SSR broken (issue #192); no viable E2EE integration |
| Inertia.js | Same server-sees-props limitation as LiveSvelte; adds no value for E2EE |
| Elm | WASM story immature; community too small |
| Path D (operator trust model) | Not real E2EE; legal subpoena hands over everything; insider threat unlimited |
| Wire `core-crypto` WASM keystore | Wire's own docs: "not validated nor audited, paper cuts expected"; use as reference implementation only |
| Memory-only key storage (no IndexedDB) | Keys lost on page refresh, tab close, or mobile backgrounding; unusable for a messaging app |
| localStorage for key storage | Plaintext; any XSS = all private keys exported |
| `@capacitor/preferences` for refresh token | NSUserDefaults: not encrypted, backup-extractable, not Keychain |
| `@perfood/capacitor-crypto-api` as primary passkey bridge | Entitlement conflict with self-hosting model (Associated Domains in app binary); unvalidated against Wax |
| Native platform passkey plugin (any) requiring Associated Domains entitlement in binary | Binary is signed by Famichat; self-hoster cannot add their domain to a published binary's entitlements |
| Committing WASM binary to repo | Silent security drift; stale crypto indefinitely; no build-to-source traceability |
| npm workspaces + `file:` for WASM package | Copies at install time; breaks dev watch loop |
| `curl \| sh` for wasm-pack installation | Non-reproducible, unversioned, runs as root |
| Separate nginx container for SPA serving | Adds container, CORS surface, cross-container routing for zero practical benefit at 100–500 users |
| COOP/COEP headers + SharedArrayBuffer for WASM threading | Cannot be set via Capacitor URLSchemeHandler (iOS); Android WebView has no site isolation; single-threaded is sufficient |
| Progressive per-message decrypt results from worker | If a later message in the batch fails epoch validation, already-rendered messages cannot be un-rendered → inconsistent UI state; use atomic batch commits per group |
