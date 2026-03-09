# IA/DDD Boundary Guardrails

**Last Updated**: 2026-03-08
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

## Naming Guardrails

Use:
1. `Famichat.Chat.ConversationSecurityState`
2. `Famichat.Chat.ConversationSecurityStateStore`
3. `Famichat.Chat.ConversationSecurityPolicy`
4. `conversation security client inventory policy` (domain wording)
5. `Famichat.Chat.ConversationSecurityKeyPackagePolicy` as the current implementation name (planned rename target: `Famichat.Chat.ConversationSecurityClientInventoryPolicy`)

Avoid in active docs/code:
1. `ConversationEncryptionPolicy`
2. `ConversationTypePolicy` for security-only behavior
3. `message security state` for durable conversation state naming
4. `MLSStateStore`
5. introducing additional `key_package`-based Chat boundary names beyond the current legacy implementation module
6. `key_package` in new Chat-facing module/function names (allowed in `Famichat.Crypto.MLS` and internal inventory payload terminology)

## Automated Drift Check

Run:

```bash
cd backend && ./run docs:boundary-check
```

This check is also wired into `./run ci:lint` and `./run lint:all`.

Current check scope (active docs):
1. `docs/SPEC.md`
2. `docs/ia-lexicon.md`
3. `docs/ia-boundary-guardrails.md`

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
