# Famichat - API Design Principles

**Last Updated**: 2025-10-05

---

## Response Format Standards

### Uniform Tuple Pattern
All service functions return simple status tuples:

```elixir
{:ok, result} | {:error, reason}
```

**Benefits**:
- Predictable pattern matching
- Clear separation of business logic from telemetry
- Reduced cognitive overhead

**Examples**:
```elixir
# Success
{:ok, message} = MessageService.send_message(attrs)

# Error
{:error, :no_shared_family} = ConversationService.create_direct_conversation(user1, user2)
```

---

## Error Handling

### Error Reasons
Errors use atoms for programmatic handling:

```elixir
:not_found
:no_shared_family
:unauthorized
:invalid_conversation_type
:last_admin_cannot_be_removed
```

### Changeset Errors
Validation errors return changeset:

```elixir
{:error, %Ecto.Changeset{}} = MessageService.send_message(invalid_attrs)
```

---

## Telemetry Integration

### Separation of Concerns
- Business logic returns simple tuples
- Telemetry emitted separately via `:telemetry.span/3`
- No metadata mixed with return values

**Example**:
```elixir
def send_message(attrs) do
  :telemetry.span([:famichat, :message, :send], %{}, fn ->
    result = do_send_message(attrs)
    {result, %{status: elem(result, 0)}}
  end)
end
```

---

## API Versioning

**Current**: No versioning (pre-1.0)
**Planned**: URL-based versioning (`/api/v1/`, `/api/v2/`)

**Breaking Changes**:
- Will bump major version
- Maintain backward compatibility for 1 major version
- Deprecation warnings before removal

---

## Related Documentation

- [backend/guides/messaging-implementation.md](../backend/guides/messaging-implementation.md)
- [backend/guides/telemetry.md](../backend/guides/telemetry.md)

---

**Last Updated**: 2025-10-05
