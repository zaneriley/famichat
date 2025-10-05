# ADR 001: Immutable Conversation Types

**Date**: 2025-02-15
**Status**: Accepted

---

## Context

We need to decide whether conversation types (direct, self, group, family) can change after creation.

## Decision

Conversation types are **immutable** after creation.

## Rationale

1. **Clear User Mental Models**: Users expect direct messages to stay 1:1, not suddenly become group chats
2. **Simplified Authorization**: Each type has different permission rules; changing types complicates security
3. **Privacy Concerns**: Upgrading direct→group could expose past 1:1 messages to new participants
4. **Industry Standard**: WhatsApp, Signal, iMessage all treat conversation types as immutable

## Implementation

- Separate `create_changeset/2` and `update_changeset/2` in Conversation schema
- `update_changeset` excludes `:conversation_type` field
- Type-specific creation functions enforce validation

## Consequences

### Positive
- Clear, predictable behavior for users
- Simpler authorization logic
- Prevents privacy leaks

### Negative
- Cannot upgrade direct→group (must create new conversation)
- Slight UX friction if users want to "add people" to existing chat

## Alternatives Considered

1. **Allow type changes**: Rejected due to privacy and complexity
2. **Conversation forking**: Create new conversation from old, copy history - Deferred to future

---

**Related**: [Conversation schema](../../backend/lib/famichat/chat/conversation.ex)
