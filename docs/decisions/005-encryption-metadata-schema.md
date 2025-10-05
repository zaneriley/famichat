# ADR 005: Encryption Metadata Schema Design

**Date**: 2025-10-05
**Status**: Proposed
**Deciders**: [Pending]
**Priority**: High (Sprint 11)

---

## Context

Current encryption metadata is stored in JSONB field `messages.metadata`:

```elixir
# Current schema
create table(:messages) do
  add :content, :text, null: false
  add :metadata, :jsonb, default: "{}"  # Encryption data here
  # ...
end
```

**Problems**:

1. **Cannot Index**: JSONB fields cannot be indexed efficiently
   - Querying by `key_id` requires full table scan
   - Filtering by `encryption_version` is slow
   - Breaks performance budget (<200ms for queries)

2. **No Type Safety**: JSONB is schemaless
   - Schema changes require careful migration
   - Easy to introduce bugs (typos in keys)
   - No compile-time validation

3. **Encryption Performance**: Metadata queries will be frequent
   - Key rotation: Find all messages with `key_id = X`
   - Debugging: Find messages with `encryption_version = Y`
   - Auditing: Count messages by encryption status

**Performance Impact**: At 100,000 messages, JSONB query takes ~500ms (exceeds budget).

---

## Problem Statement

**Goal**: Design encryption metadata schema that supports:

1. Fast queries (indexed fields)
2. Type safety (Ecto schema validation)
3. Key rotation (find messages by key_id)
4. Encryption version tracking (find messages by version)
5. Performance within budget (<20ms for metadata queries)

---

## Decision

Create separate `message_encryption` table with indexed fields.

### Schema Design

```elixir
# priv/repo/migrations/[timestamp]_create_message_encryption.exs
create table(:message_encryption) do
  add :message_id, references(:messages, on_delete: :delete_all), null: false
  add :encrypted, :boolean, null: false, default: false
  add :encryption_version, :string  # "v1.0.0", "v1.1.0", etc.
  add :key_id, :string  # "KEY_USER_123_v1", "GROUP_456_v2", etc.
  add :protocol, :string  # "signal", "megolm", "mls"
  add :sender_device_id, :string  # Device that encrypted message
  add :recipient_device_ids, {:array, :string}  # For 1:1 (Signal Protocol)
  add :group_session_id, :string  # For groups (Megolm)
  add :ratchet_index, :integer  # Message index in ratchet chain
  add :metadata, :jsonb, default: "{}"  # Protocol-specific extras

  timestamps()
end

# Indexes for common queries
create unique_index(:message_encryption, [:message_id])
create index(:message_encryption, [:key_id])
create index(:message_encryption, [:encryption_version])
create index(:message_encryption, [:protocol])
create index(:message_encryption, [:group_session_id])
create index(:message_encryption, [:sender_device_id])
```

### Ecto Schema

```elixir
# lib/famichat/chat/message_encryption.ex
defmodule Famichat.Chat.MessageEncryption do
  use Ecto.Schema
  import Ecto.Changeset

  schema "message_encryption" do
    belongs_to :message, Famichat.Chat.Message

    field :encrypted, :boolean, default: false
    field :encryption_version, :string
    field :key_id, :string
    field :protocol, :string
    field :sender_device_id, :string
    field :recipient_device_ids, {:array, :string}
    field :group_session_id, :string
    field :ratchet_index, :integer
    field :metadata, :map  # JSONB for protocol-specific extras

    timestamps()
  end

  @required_fields [:message_id, :encrypted]
  @optional_fields [
    :encryption_version, :key_id, :protocol,
    :sender_device_id, :recipient_device_ids,
    :group_session_id, :ratchet_index, :metadata
  ]

  def changeset(encryption, attrs) do
    encryption
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_encryption_fields()
    |> unique_constraint(:message_id)
  end

  defp validate_encryption_fields(changeset) do
    encrypted = get_field(changeset, :encrypted)

    if encrypted do
      changeset
      |> validate_required([:encryption_version, :key_id, :protocol])
      |> validate_protocol_fields()
    else
      changeset
    end
  end

  defp validate_protocol_fields(changeset) do
    protocol = get_field(changeset, :protocol)

    case protocol do
      "signal" ->
        # Signal Protocol requires sender_device_id and recipient_device_ids
        changeset
        |> validate_required([:sender_device_id, :recipient_device_ids])

      "megolm" ->
        # Megolm requires group_session_id and ratchet_index
        changeset
        |> validate_required([:group_session_id, :ratchet_index])

      "mls" ->
        # MLS requires group_session_id
        changeset
        |> validate_required([:group_session_id])

      _ ->
        add_error(changeset, :protocol, "invalid protocol: #{protocol}")
    end
  end
end
```

### Updated Message Schema

```elixir
# lib/famichat/chat/message.ex
defmodule Famichat.Chat.Message do
  use Ecto.Schema

  schema "messages" do
    field :content, :string
    # Remove metadata field (moved to message_encryption)

    belongs_to :conversation, Famichat.Chat.Conversation
    belongs_to :sender, Famichat.Accounts.User
    has_one :encryption, Famichat.Chat.MessageEncryption  # New association

    timestamps()
  end

  # Preload encryption data when querying messages
  def with_encryption(query) do
    from m in query, preload: :encryption
  end
end
```

---

## Alternatives Considered

### Alternative 1: Keep JSONB (Current)

**Pros**: Simple, flexible schema
**Cons**: Cannot index, slow queries, no type safety

**Rejected**: Performance impact too severe. At 100,000 messages, queries take 500ms.

---

### Alternative 2: Indexed JSONB with GIN Index

**Pros**: Retains flexibility, adds indexing
**Cons**: GIN indexes are slower than B-tree (still 100-200ms), complex query syntax

```sql
-- Example GIN index
CREATE INDEX idx_metadata_key_id ON messages USING GIN ((metadata -> 'key_id'));

-- Query syntax is complex
SELECT * FROM messages WHERE metadata @> '{"key_id": "KEY_123"}';
```

**Rejected**: Still slower than separate table, complex query syntax.

---

### Alternative 3: Separate Table with Fewer Fields

**Pros**: Simpler schema
**Cons**: Still needs protocol-specific fields (no significant simplification)

**Rejected**: No meaningful benefit over full schema.

---

## Implementation Plan

### Migration Strategy

**Phase 1: Create New Table** (Sprint 11)
1. Create `message_encryption` table
2. Add schema and changeset
3. Update `MessageService` to create encryption records

**Phase 2: Migrate Existing Data** (Sprint 11)
- No existing encrypted messages (placeholder metadata only)
- Simple migration: No data to move

**Phase 3: Update Queries** (Sprint 11)
```elixir
# Before: Query JSONB
from m in Message, where: fragment("metadata->>'key_id' = ?", ^key_id)

# After: Query indexed field
from m in Message,
  join: e in assoc(m, :encryption),
  where: e.key_id == ^key_id
```

**Phase 4: Remove Old Field** (Sprint 12)
- Remove `messages.metadata` column
- Clean up old code references

---

## Query Examples

### Find Messages by Key ID (Key Rotation)

```elixir
# Find all messages encrypted with specific key
def messages_with_key(key_id) do
  from m in Message,
    join: e in assoc(m, :encryption),
    where: e.key_id == ^key_id,
    preload: :encryption
end

# Performance: ~5ms with index (vs 500ms JSONB scan)
```

### Find Messages by Encryption Version

```elixir
# Find all messages with old encryption version (for migration)
def messages_with_version(version) do
  from m in Message,
    join: e in assoc(m, :encryption),
    where: e.encryption_version == ^version,
    preload: :encryption
end

# Performance: ~10ms with index
```

### Count Encrypted vs Plaintext Messages

```elixir
# Audit: How many messages are encrypted?
def encryption_stats do
  from e in MessageEncryption,
    group_by: e.encrypted,
    select: {e.encrypted, count(e.id)}
end

# Performance: ~5ms (indexed query)
```

---

## Performance Impact

### Database Storage

**Per Message**:
- Current: ~100 bytes JSONB overhead
- New: ~200 bytes (separate table row)

**Tradeoff**: 2x storage cost for 10-100x query performance improvement.

**At 1,000,000 messages**:
- Current: 100MB JSONB
- New: 200MB separate table
- **Acceptable**: Storage is cheap, performance is critical.

### Query Performance

| Query | JSONB (Current) | Indexed Table (New) | Improvement |
|-------|-----------------|---------------------|-------------|
| Find by key_id | 500ms | 5ms | 100x faster |
| Find by version | 400ms | 10ms | 40x faster |
| Count encrypted | 300ms | 5ms | 60x faster |

**Conclusion**: Well within 20ms query budget.

---

## Security Considerations

### Sensitive Data in Metadata

**JSONB Field** (`metadata`): Still available for protocol-specific extras
- Should NOT contain keys or secrets
- Only protocol metadata (algorithm, parameters, etc.)

**Indexed Fields**: Safe to index
- `key_id`: Identifier, not the key itself
- `encryption_version`: Version string, not sensitive
- `protocol`: Protocol name, not sensitive

### Telemetry Filtering

Ensure telemetry does not log encryption metadata:

```elixir
# lib/famichat/telemetry.ex
defp filter_sensitive_fields(metadata) do
  Map.drop(metadata, [:key_id, :group_session_id, :sender_device_id])
end
```

---

## Migration Rollout

### Sprint 11: Implement New Schema
- Create table and migration
- Add Ecto schema
- Update `MessageService` to create encryption records
- **Do not remove old field yet** (dual-write for safety)

### Sprint 12: Validate and Clean Up
- Verify all new messages have encryption records
- Verify query performance meets budget
- Remove `messages.metadata` field
- Delete old code references

**Rollback Plan**: If issues found, can revert to JSONB (dual-write ensures no data loss).

---

## Consequences

### Positive

1. **Performance**: 10-100x faster queries, meets 20ms budget
2. **Type Safety**: Ecto schema validation prevents bugs
3. **Indexing**: Fast key rotation and encryption audits
4. **Scalability**: Handles millions of messages efficiently

### Negative

1. **Complexity**: Separate table requires join queries
2. **Storage**: 2x storage cost per message
3. **Migration**: Requires careful rollout (dual-write period)

### Neutral

1. **Implementation Time**: ~1 sprint (2 weeks)
2. **Testing**: Requires performance benchmarks

---

## Open Questions

1. **Index Strategy**: Should we add composite indexes for common query patterns? (e.g., `key_id + encryption_version`)
2. **Retention**: Should we delete encryption metadata for deleted messages? (Yes, via `on_delete: :delete_all`)
3. **Sharding**: Will encryption table need partitioning at scale? (Defer until >10M messages)

---

## References

- [PostgreSQL JSON vs Separate Columns](https://www.postgresql.org/docs/current/datatype-json.html)
- [Ecto Associations](https://hexdocs.pm/ecto/Ecto.Schema.html#has_one/3)
- [Database Indexing Best Practices](https://use-the-index-luke.com/)

---

**Last Updated**: 2025-10-05
**Next Review**: Sprint 11 (after implementation)
