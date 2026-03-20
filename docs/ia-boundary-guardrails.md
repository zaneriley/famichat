# IA/DDD Boundary Guardrails

**Last Updated**: 2026-03-20
**Authority Inputs**: [ia-lexicon.md](ia-lexicon.md), [ENCRYPTION.md](ENCRYPTION.md), [ARCHITECTURE.md](ARCHITECTURE.md)

## Goal

Keep naming and ownership boundaries stable so implementation work does not drift across domains.

## Locked Core Domain Terms

1. `conversation`, `message`, `family` remain locked core entities.
2. Durable messaging crypto state term: `conversation security state`.
3. Chat-domain policy term: `conversation security policy`.
4. Chat-domain client inventory term: `conversation security client inventory`.

## Ownership Boundary

1. `Famichat.Chat` owns durable state and policy decisions.
2. `Famichat.Crypto.MLS` and `backend/infra/mls_nif` are adapters only.
3. Protocol (`mls`) is data, not a boundary prefix for Chat-owned modules/tables.

4. `Famichat.Accounts.FamilyContext` owns active-family resolution. It depends on Accounts schemas and Repo only; it does NOT depend on `Famichat.Auth` (to avoid circular dependencies). It is not part of `Famichat.Chat` or `Famichat.Auth`.
5. "Set up your family space" is shown on the public front door as a secondary action (below the sign-in button) when the instance is bootstrapped and `self_service_enabled` is `true`. Self-service family creation is rate-limited (3 per IP per hour) and creates isolated family spaces; it does not grant access to existing families. The URL itself is the admission gate -- the operator chose to share the server address, and that is a trust decision. An operator toggle (`self_service_enabled`, default `true`) controls whether this CTA appears; when `false`, the front door reverts to invite-only. This toggle is planned as a boolean at MLP, evolving to a tri-state (`:open`, `:approval_required`, `:closed`) at L3.
6. **Client** is a trust boundary peer to the server. It owns private key material (`famichat_mls_keystore`), decrypted message cache (`famichat_messages`), and MLS epoch state. The server cannot overwrite Client-owned state without Client consent.
7. `FamichatWeb.BootContext` is a Web-layer aggregator. It depends on `Famichat.Auth.Sessions` and `Famichat.Accounts.FamilyContext` but belongs to neither domain. Placing it in `Sessions` would create an Auth → Accounts dependency.
8. `FamichatWeb.Plugs.ApiAuth` authenticates SPA/Capacitor API requests. It delegates to `Sessions.verify_access_token/1`. The existing `BearerAuth` plug remains for the `:api_authenticated` pipeline.
9. `FamichatWeb.SystemChannel` delivers lifecycle events (`session_terminated`) to specific devices. It does not read conversation data or MLS state.
10. Client-side import hierarchy: Components → `ConversationCrypto` → `CryptoWorkerManager` → `MlsWorkerApi`. Components must NOT import `MlsWorkerApi` or `CryptoWorkerManager` directly.

## Naming Guardrails

Use:
1. `Famichat.Chat.ConversationSecurityState`
2. `Famichat.Chat.ConversationSecurityStateStore`
3. `Famichat.Chat.ConversationSecurityPolicy`
4. `conversation security client inventory policy` (domain wording)
5. `Famichat.Chat.ConversationSecurityKeyPackagePolicy` as the current implementation name (planned rename target: `Famichat.Chat.ConversationSecurityClientInventoryPolicy`)
6. `FamichatWeb.Plugs.ApiAuth` for SPA/Capacitor API authentication
7. `ConversationCrypto` as the client-side domain-facing crypto interface
8. `CryptoWorkerManager` as the WASM worker lifecycle owner
9. `session_terminated` as the channel event for device session end
10. `channel_token` as the canonical term for WebSocket auth tokens; endpoint `POST /api/v1/auth/channel_tokens`
11. `boot context` as the session-scoped data payload for SPA cold start; assembled by `FamichatWeb.BootContext.for_conn/1`

Avoid in active docs/code:
1. `ConversationEncryptionPolicy`
2. `ConversationTypePolicy` for security-only behavior
3. `message security state` for durable conversation state naming
4. `MLSStateStore`
5. introducing additional `key_package`-based Chat boundary names beyond the current legacy implementation module
6. `key_package` in new Chat-facing module/function names (allowed in `Famichat.Crypto.MLS` and internal inventory payload terminology)
7. `CookieOrBearerAuth` — renamed to `ApiAuth`
8. `CryptoService` — use `ConversationCrypto` (domain interface) or `MlsWorkerApi` (protocol interface)
9. `WorkerSupervisor` — use `CryptoWorkerManager`; avoids OTP `Supervisor` collision
10. `boot token` / `boot_token` / `__boot_token` in new documents — superseded by `boot context`
11. `channel_bootstrap_token` — canonical term is `channel_token`
12. `device_revoked` as a channel event name — use `session_terminated`

## Automated Drift Check

### Naming drift (grep-based)

Run:

```bash
cd backend && ./run docs:boundary-check
```

This check is also wired into `./run ci:lint` and `./run lint:all`.

### Compile-time boundary enforcement

Run:

```bash
cd backend && ./run cmd mix compile
```

The `boundary` hex package (`:boundary` compiler, `mix.exs` line 83) validates all `use Boundary` annotations at compile time. It checks that every cross-module call respects declared `deps` and `exports`. Violations appear as compiler warnings. The `:boundary` compiler is active for all non-test builds (`compilers/1` in `mix.exs` line 38).

Current check scope (active docs):
1. `docs/SPEC.md`
2. `docs/ia-lexicon.md`
3. `docs/ia-boundary-guardrails.md`
4. `docs/NOW.md`
5. `docs/BACKLOG.md`
6. `docs/E2EE_INTEGRATION.md`

## Deferred Terms (do not introduce in code or product copy)

These terms are tracked here so the drift check can flag premature introduction.
They are not canonical product terms. See `ia-lexicon.md` § "Research Concepts
Under Consideration" for definitions and provenance.

1. `neighborhood` — Deferred product framing per `ia-lexicon.md`. Do not introduce
   in new product, engineering, or boundary docs until dogfood proves it is understood
   by users. The word is ambiguous (geographic vs trust-based) and its governance
   implications are unresolved. (Phase 1 peer review, Review 4, recommendation #5.)

## Review Rule

Any new naming proposal that affects security/state/policy boundaries must:
1. update `docs/ia-lexicon.md` first,
2. pass `docs:boundary-check`,
3. then update implementation docs/code.
