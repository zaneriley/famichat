# IA/DDD Boundary Guardrails

**Last Updated**: 2026-02-25
**Authority Inputs**: [ia-lexicon.md](ia-lexicon.md), [ENCRYPTION.md](ENCRYPTION.md), [ARCHITECTURE.md](ARCHITECTURE.md)

## Goal

Keep naming and ownership boundaries stable so implementation work does not drift across domains.

## Locked Core Domain Terms

1. `conversation`, `message`, `family` remain locked core entities.
2. Durable messaging crypto state term: `conversation security state`.
3. Chat-domain policy term: `conversation security policy`.

## Ownership Boundary

1. `Famichat.Chat` owns durable state and policy decisions.
2. `Famichat.Crypto.MLS` and `backend/infra/mls_nif` are adapters only.
3. Protocol (`mls`) is data, not a boundary prefix for Chat-owned modules/tables.

## Naming Guardrails

Use:
1. `Famichat.Chat.ConversationSecurityState`
2. `Famichat.Chat.ConversationSecurityStateStore`
3. `Famichat.Chat.ConversationSecurityPolicy`

Avoid in active docs/code:
1. `ConversationEncryptionPolicy`
2. `ConversationTypePolicy` for security-only behavior
3. `message security state` for durable conversation state naming
4. `MLSStateStore`

## Automated Drift Check

Run:

```bash
cd backend && ./run docs:boundary-check
```

This check is also wired into `./run ci:lint` and `./run lint:all`.

Current check scope (active docs):
1. `docs/ENCRYPTION.md`
2. `docs/ARCHITECTURE.md`
3. `docs/NOW.md`
4. `docs/sprints/CURRENT-SPRINT.md`
5. `docs/sprints/ROADMAP.md`
6. `docs/sprints/STATUS.md`

## Review Rule

Any new naming proposal that affects security/state/policy boundaries must:
1. update `docs/ia-lexicon.md` first,
2. pass `docs:boundary-check`,
3. then update implementation docs/code.
