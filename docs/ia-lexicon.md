# Famichat IA Lexicon

**Last Updated**: 2026-02-25
**Scope**: Canonical product and engineering terms used across roadmap, architecture, and sprint docs.

---

## Canonical Terms

### Product Language

1. `conversation security state`
   - The durable security state needed to encrypt/decrypt messages for a conversation.
   - This wording is the default in product-facing docs.

### Engineering Language

1. `conversation security state record`
   - Durable engineering record used to persist and restore conversation security state.
2. `MLS protocol state`
   - Protocol-qualified term for implementation details when the active protocol is MLS.
3. `state conflict`
   - An optimistic-lock write conflict where persisted state changed before the current write completed.
4. `fail-closed recovery`
   - Recovery behavior that returns explicit errors instead of silently falling back to plaintext or stale state.

---

## Policy Terms (New)

1. `conversation security policy`
   - Chat-domain policy that decides whether a conversation requires encrypted message handling and fail-closed behavior.
2. `conversation security requirement`
   - The policy decision outcome for a conversation context (`required` or `not_required`).
3. Canonical module naming for this boundary: `Famichat.Chat.ConversationSecurityPolicy`.
4. Compatibility note: legacy API wording like `requires_encryption?/1` can remain for compatibility, but docs should describe this as conversation security policy behavior.

---

## Ownership Terms

1. `Famichat.Chat` is the write owner for durable conversation security state.
2. `Famichat.Crypto.MLS` and `backend/infra/mls_nif` are crypto adapters only and do not own persistence tables.
3. `Famichat.Chat.MessageService` orchestrates state load/persist through Chat-owned boundaries.

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
5. Enforcement command: `cd backend && ./run docs:boundary-check` (see `docs/ia-boundary-guardrails.md`).

---

## Naming Contract (Planned Sprint 9 Hardening)

1. Table: `conversation_security_states`
2. Schema module: `Famichat.Chat.ConversationSecurityState`
3. Store boundary module: `Famichat.Chat.ConversationSecurityStateStore`
4. Protocol remains data, not boundary naming (for example: `protocol = "mls"`).
