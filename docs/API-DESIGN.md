# Famichat - API Design Principles

**Last Updated**: 2025-10-14

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

## Accounts API Notes (Auth Hardening – Oct 2025)

- `POST /api/v1/auth/invites/accept` consumes the one-time invite token and returns the sanitized payload plus a 10‑minute `registration_token` (also mirrored in the `x-test-token` header during tests).
- `POST /api/v1/auth/invites/complete` now requires a Bearer `registration_token` header; the invite token itself is no longer accepted once consumed.
- Invite completion still returns a `passkey_register_token`; clients must exchange that token for a WebAuthn registration challenge before enrolling a credential.
- Usernames are persisted case-preserving but stored alongside a deterministic fingerprint; lookups must remain case-insensitive by routing through `Famichat.Accounts.get_user_by_username/1`.
- `POST /api/v1/auth/passkeys/register/challenge` accepts either a `register_token` (fresh invite flow) or a trusted session (bearer token) to request a challenge.
- `POST /api/v1/auth/pairings` (reissue) is intentionally admin-only; document its usage when regenerating QR/admin codes for an outstanding invite.
- Magic-link redemption records `enrollment_required_since` when a user without active passkeys logs in; registering a passkey clears the state.
- Magic-link, OTP, and recovery endpoints emit `x-test-token` headers only in `MIX_ENV=test` to keep raw tokens out of fixtures/logs.
- Passkey flows are still returning minimal `{challenge, challenge_token}` payloads. Full WebAuthn `PublicKeyCredentialCreationOptions`/`PublicKeyCredentialRequestOptions` must be surfaced once the Wax integration lands.

---

**Last Updated**: 2025-10-13
