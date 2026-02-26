# Famichat IA Lexicon

**Last Updated**: 2026-02-26
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

---

## Naming Contract (Planned Sprint 9 Hardening)

1. Table: `conversation_security_states`
2. Schema module: `Famichat.Chat.ConversationSecurityState`
3. Store boundary module: `Famichat.Chat.ConversationSecurityStateStore`
4. Protocol remains data, not boundary naming (for example: `protocol = "mls"`).
