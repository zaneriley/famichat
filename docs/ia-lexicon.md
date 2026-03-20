# Famichat IA Lexicon

**Last Updated**: 2026-03-20
**Scope**: Canonical product and engineering terms used across roadmap, architecture, and sprint docs.

---

## Scope and Role Terms

1. `family`
   - The primary daily-use scope. A family is the unit users live inside: their home, their conversations, their members.
   - Use `family` in all user-facing copy, daily-use surfaces, and product docs.
   - Do not use `household` as the primary product noun. `household` survives only in legacy code module names (`Famichat.Auth.Households`, `HouseholdMembership`) and in the role label `household admin` — see below.
   - **Copy guidance**: "Your families" is the canonical switcher panel header label for multi-family users. "Add a family" is the canonical CTA label for community admin creating a new family.
2. `community`
   - The trust/admin scope. A community is the operator-level deployment that may contain one or more families.
   - Use `community` only where the scope genuinely spans families or requires operator-level trust decisions: community admin surfaces, multi-family trust docs, admin recovery.
   - Do not promote `community` as the main product surface or daily-use home.
3. `community admin` (role)
   - A user with operator-level powers: can create families, assign first household admins, perform deployment-wide emergency actions.
4. `household admin` (role)
   - An admin scoped to a single family: invites members, approves pending devices, manages that family's participation.
   - Note: the code uses `household` here (`Famichat.Auth.Households`, `HouseholdMembership`, `revoke_all_for_household`). This is a legacy naming artifact, not a canonical product term.
5. `neighborhood`
   - Deferred product framing. Not used in the MLP. Do not introduce this term in new product or engineering docs until dogfood proves it is understood by users.

---

## Canonical Terms

### Product Language

1. `conversation security state`
   - The durable security state needed to encrypt/decrypt messages for a conversation.
   - This wording is the default in product-facing docs.

1. `family setup link`
   - The canonical term for the URL generated from a `:family_setup` token. Used when a community admin creates a new family and shares the link privately with the intended first family admin. Do not use "family invite link" (which conflates it with the member invite flow).
   - **Guardrail**: "Set up your family space" is shown on the public front door as a secondary action when `self_service_enabled` is `true` (the default). Self-service auto-generates a `:family_setup` token internally; the token model is the same, but the issuance path differs (`"initiated_by" => "self"` vs `"initiated_by" => <admin_uuid>`). The operator can disable self-service via toggle, reverting the front door to invite-only. See `ia-boundary-guardrails.md` item 5.

### Engineering Language

1. `conversation security state record`
   - Durable engineering record used to persist and restore conversation security state.
2. `MLS protocol state`
   - Protocol-qualified term for implementation details when the active protocol is MLS.
3. `state conflict`
   - An optimistic-lock write conflict where persisted state changed before the current write completed.
4. `fail-closed recovery`
   - Recovery behavior that returns explicit errors instead of silently falling back to plaintext or stale state.
5. `boot context`
   - The session-scoped data payload delivered to the SPA at cold start. Contains `user_id`, `username`, `device_id`, `locale`, `active_family_id`, `active_family_name`, `channel_token`. Assembled by `FamichatWeb.BootContext.for_conn/1` (Web-layer aggregator). Delivered via HTML `<script>` embed on first load (zero round-trip) and `GET /api/v1/boot` for refresh/Capacitor cold start. The JS global `window.__FAMICHAT_BOOT__` is an implementation detail; components use `getBootContext()` from `$lib/auth/boot.ts`.
6. `channel_token`
   - A short-lived Phoenix.Token authorizing WebSocket channel joins. Issued by `POST /api/v1/auth/channel_tokens` (plural). The internal token kind atom is `:channel_token`. The signing salt `"channel_bootstrap_v1"` is preserved for backward compatibility. Replaces `channel_bootstrap_token`.
7. `SPA shell page`
   - The server-rendered HTML page served by `SpaController` at `/app/*`. Contains the `<script>` tag with boot context, CSS/JS asset links, and locale-switching logic. Loads before Svelte mounts. Use "SPA shell page" in docs, not "boot page."
8. `session_terminated`
   - Channel event delivered via `system:user:{user_id}` when a device's session is ended (revocation, admin action). Replaces the proposed `device_revoked` event name, which collides with MLS group revocation. Payload includes `reason` field (`"device_revoked"`, `"user_revoked"`).
9. `ApiAuth`
   - `FamichatWeb.Plugs.ApiAuth`. Authenticates API requests by checking the session cookie first (same-origin SPA), falling back to Bearer header (Capacitor). Replaces the proposed `CookieOrBearerAuth` name. Delegates to `Sessions.verify_access_token/1`.
10. `SpaCSPHeader`
    - `FamichatWeb.Plugs.SpaCSPHeader`. Scoped CSP plug for the `:spa` pipeline only. Adds `wasm-unsafe-eval` to `script-src` and `worker-src 'self' blob:`. Must not be applied globally — LiveView paths do not need WASM permissions.

---

## Policy Terms (New)

1. `conversation security policy`
   - Chat-domain policy that decides whether a conversation requires encrypted message handling and fail-closed behavior.
2. `conversation security requirement`
   - The policy decision outcome for a conversation context (`required` or `not_required`).
3. Requirement-decision policy module: `Famichat.Chat.ConversationSecurityPolicy`.
4. Current client-inventory lifecycle policy module (legacy implementation name): `Famichat.Chat.ConversationSecurityKeyPackagePolicy`.
5. Planned client-inventory lifecycle policy rename target: `Famichat.Chat.ConversationSecurityClientInventoryPolicy`.
6. Compatibility note: legacy API wording like `requires_encryption?/1` can remain for compatibility, but docs should describe this as conversation security policy behavior.

## Client Inventory Terms

1. `conversation security client inventory`
   - Chat-owned pool of one-time cryptographic intro objects used to add/re-add clients safely.
2. `client inventory entry`
   - One consumable entry from that inventory.
3. `conversation security client inventory policy`
   - Policy/lifecycle boundary for ensure, consume, and stale-rotation behavior of client inventory.
   - Current implementation module: `ConversationSecurityKeyPackagePolicy`
   - Planned module rename target: `ConversationSecurityClientInventoryPolicy`
4. Mechanism note: `key_package` remains valid in MLS adapter/internal payload terminology, but not as a Chat-facing boundary/API noun.

---

## Ownership Terms

1. `Famichat.Chat` is the write owner for durable conversation security state.
2. `Famichat.Crypto.MLS` and `backend/infra/mls_nif` are crypto adapters only and do not own persistence tables.
3. `Famichat.Chat.MessageService` orchestrates state load/persist through Chat-owned boundaries.
4. `FamichatWeb.BootContext` is the Web-layer aggregator for SPA boot data. It depends on Auth and Accounts but does not belong to either — it lives in the Web layer to avoid circular dependencies.
5. `FamichatWeb.Plugs.ApiAuth` handles SPA/Capacitor API authentication. Delegates to `Famichat.Auth.Sessions.verify_access_token/1`.

---

## Client Bounded Context

The **Client** is the trust boundary peer to the server. It holds private key material in IndexedDB, maintains MLS epoch state the server cannot overwrite, and controls two persistent stores. "Client" wins over "Browser" (too platform-specific — Capacitor runs in a WebView), "Device" (collides with Auth domain `device`), and "Frontend" (directory name, not a domain concept).

### Client-Side Modules

1. `ConversationCrypto`
   - Domain-facing crypto interface for components. File: `frontend/src/lib/crypto/conversation-crypto.ts`. Interface: `encrypt(conversationId, plaintext)`, `decrypt(conversationId, ciphertext)`, `restoreSession(conversationId)`, `decryptBatch(conversationId, ciphertexts)`. Components import `ConversationCrypto` only — never `CryptoWorkerManager` or `MlsWorkerApi`.
2. `CryptoWorkerManager`
   - Lifecycle owner of the WASM Web Worker. File: `frontend/src/lib/crypto/crypto-worker-manager.ts`. Owns worker spawn, restart, health check, `initWrappingKey`. Non-conversation operations live here, not on `ConversationCrypto`.
3. `MlsWorkerApi`
   - Protocol-level Comlink contract running inside the Web Worker. The client-side analog of `Famichat.Crypto.MLS`. Components must not import this directly.
4. Import hierarchy: `ConversationCrypto` > `CryptoWorkerManager` > `MlsWorkerApi`. This mirrors the server-side pattern where `MessageService` (domain) is distinct from `Famichat.Crypto.MLS` (adapter).

### Client-Side Stores

1. `famichat_mls_keystore`
   - IndexedDB database for MLS signing keys and group state. The `mls` prefix is intentional: the store is exclusively MLS content, and renaming a deployed IndexedDB database requires a data migration. This asymmetry with the server-side naming guardrail (which discourages `mls` prefixes on Chat-owned modules) is acceptable and documented.
2. `famichat_messages`
   - IndexedDB database for decrypted message cache, conversation previews, and sync cursors. Managed by Dexie.js.

### Web-Layer Modules (Server-Side, Supporting Client)

1. `FamichatWeb.BootContext`
   - Web-layer aggregator that assembles the boot context payload. Depends on `Sessions` (Auth) and `FamilyContext` (Accounts). Lives in the Web layer because it crosses domain boundaries — `Sessions` must not depend on `Accounts`.
2. `FamichatWeb.SystemChannel`
   - Phoenix Channel on `system:user:{user_id}` for lifecycle events. Delivers `session_terminated` with `reason` payload. `handle_out` filters by `device_id` so only the target device receives the event.

---

## Migration Language Policy

1. `session snapshot` is a compatibility-only term and must not be used as the primary canonical label in new docs.
2. Existing metadata-envelope wording should be marked transitional until dedicated state-store migration is complete.

---

## Anti-Drift Naming Guardrails

1. Avoid `ConversationEncryptionPolicy` as the primary boundary name (too crypto-implementation-centric for Chat-domain policy).
2. Avoid `ConversationTypePolicy` for security-only decisions (too broad and likely to absorb unrelated type rules).
3. Avoid `message security state` when referring to durable group/session state; use `conversation security state`.
4. Avoid protocol-coupled store naming such as `MLSStateStore`; use `ConversationSecurityStateStore` and keep protocol as data.
5. Treat `ConversationSecurityKeyPackagePolicy` as a legacy implementation name until rename migration is complete; avoid introducing additional `key_package`-based Chat boundary names.
6. Target name for migration: `ConversationSecurityClientInventoryPolicy`.
7. Avoid `key_package` in new Chat-facing module/function names; keep `key_package` terminology scoped to `Famichat.Crypto.MLS` and internal inventory payload fields.
8. Enforcement command: `cd backend && ./run docs:boundary-check` (see `docs/ia-boundary-guardrails.md`).
9. Avoid `CookieOrBearerAuth` as a plug name — renamed to `ApiAuth`; names the capability, not the mechanism.
10. Avoid `CryptoService` as a client-side interface name — the `Service` suffix implies domain authority; use `ConversationCrypto` for the domain interface and `MlsWorkerApi` for the protocol interface.
11. Avoid `WorkerSupervisor` for the WASM worker lifecycle manager — collides with OTP `Supervisor`; use `CryptoWorkerManager`.
12. Avoid `boot token` / `boot_token` / `__boot_token` in new documents — superseded by `boot context`; the `sessionStorage.__boot_token` handoff from ADR 012 is replaced by cookie-based auth + `FamichatWeb.BootContext`.
13. Avoid `channel_bootstrap_token` — canonical term is `channel_token`; endpoint is `POST /api/v1/auth/channel_tokens`.
14. Avoid `device_revoked` as a channel event name — collides with MLS group revocation; use `session_terminated` for the system channel event.

---

## Naming Contract (Planned Sprint 9 Hardening)

1. Table: `conversation_security_states`
2. Schema module: `Famichat.Chat.ConversationSecurityState`
3. Store boundary module: `Famichat.Chat.ConversationSecurityStateStore`
4. Protocol remains data, not boundary naming (for example: `protocol = "mls"`).

---

## Research Concepts Under Consideration

> **These are NOT canonical product or engineering terms.** Do not use them in code,
> module names, UI copy, or boundary naming. They are here so that future design work
> on governance, federation, and multi-family admission has a shared vocabulary to
> reference, and so that research context is not lost between sessions.
>
> **Origin:** Phase 1 peer review (Review 4: Governance Model Fit) identified missing
> governance primitives as a friction point for L5 readiness. A subsequent research
> pass drew on Ford & Strauss (accountable pseudonyms), Ford (digital personhood),
> Borge et al. (proof-of-personhood tokens and federation), Adler et al. (personhood
> credentials), and Merino et al. (in-person credentialing under coercion). The
> concepts below distill what is relevant to Famichat's trust hierarchy. None have
> been validated through dogfooding or accepted into the product roadmap.

1. **sponsor endorsement**
   - An existing member (or household) vouching for a newcomer's admission. Distinguished from an admin-issued invite: sponsorship is a social signal of trust, not an administrative action. The peer review recommends recording `sponsored_by_user_id` on membership records and in setup token payloads so the provenance chain is traceable.
   - Related open question: should full membership require two distinct sponsor households, or is one sufficient at L1–L3 scale?

2. **provisional membership**
   - A graduated admission state where a newcomer has limited participation rights until a secondary condition is met (e.g., second sponsor, elapsed objection window, or attendance at a credentialing event). Distinct from the existing device `trust_state: :pending`, which is about device approval — provisional membership is about the person's standing in the community.

3. **ceremony epoch**
   - A renewable credentialing cycle. In the research literature, periodic physical-world events ("pseudonym parties") produce time-bounded, one-person-one-token credentials. The peer review suggests nullable `communities.ceremony_epoch` and `communities.signing_public_key` columns as zero-cost L5 readiness scaffolding. The concept matters because it separates "is this one real human, counted once, recently?" from "is this person legally resident here?" or "is this a good neighbor?" — those are distinct claims that should not collapse into a single credential.

4. **service-scoped pseudonym**
   - A privacy-preserving identity model where the same person holds one pseudonym per participating space (e.g., per family), unlinkable across spaces by the public, while the system still enforces one-person-per-space. Relevant to multi-family contexts where abuse resistance matters but a global real-name layer is undesirable. No current Famichat design addresses whether identity is global across families or scoped per family.

5. **governance procedure**
   - A formalized decision-making process for community-level actions: membership disputes, content moderation appeals, rule changes. The research suggests bicameral models (one-household-one-vote for participation issues, one-adult-one-vote or random jury for moderation/appeals, double majority for constitutional changes). Famichat currently has no governance procedures beyond admin unilateral action.

6. **coercion resistance (household boundary)**
   - The principle that neighborhood-level or community-level rights should not flow exclusively through a single household admin. The research warns that the home environment should not be assumed trustworthy for credentialing — household administration and adult community agency are structurally different concerns. Relevant to SPEC.md's L4 teen autonomy work but also applies to adult members in coercive domestic situations.

7. **federation ladder**
   - A graduated trust topology: household → block → neighborhood → broader community, where each layer can start independently and later federate with peers. In the research, local groups run independent credentialing events and then cross-recognize credentials under an anytrust assumption (at least one organizer per event is honest). Famichat's current trust hierarchy (`deployment → community → family → user → device`) is single-deployment only; this concept describes how multiple deployments might interoperate. Deferred past L5 per SPEC.md anti-patterns ("Federation before L3 validation").
