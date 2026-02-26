# Messaging API v1.1

**Status:** Draft (ready for implementation)
**Audience:** Backend & client engineers
**Base URL:** Environment‑specific (e.g., `https://api.example.com`)
**Versioning:** URL‑based (`/v1`)

## 0) High‑level scope

* **Resources:** Conversations, Threads, Messages, Reactions, Read State, Event Streams
* **Modalities:** REST (JSON) + WebSocket / SSE for real‑time events
* **Auth:** `Authorization: Bearer <token>` (user bound)
* **Formats:** Request/response JSON uses `snake_case` keys

---

## 1) Cross‑cutting rules (DX contract)

**Timestamps**

* Resources: `created_at`, `updated_at` (RFC 3339 UTC)
* Events: `emitted_at` (RFC 3339 UTC)

**Identifiers & Ordering**

* `message_seq` – `int64`, strictly increasing per **conversation**
* `event_offset` – `int64`, strictly increasing per **conversation** event stream
* Do not assume gap‑free sequences.

**Pagination (ordered streams)**

* For messages/threads lists:
  `?after_message_seq=…&before_message_seq=…&limit=…&order=asc|desc` (exclusive bounds)
* For events:
  `?after_event_offset=…&limit=…` (exclusive bound)
* For conversations list (no total order): cursor pagination `?cursor=…&limit=…`.

**Includes**

* `?include=aggregates,permissions` (server may ignore unknown keys)

**Concurrency & Idempotency**

* All `GET` return `ETag`.
* `PATCH/PUT/DELETE` require `If-Match: <ETag>` → `412` on mismatch.
* `POST` supports `Idempotency-Key` (scoped to `(method, path, user)`, 24h TTL). Replays return `200` with original body.

**Device identity (optional)**

* `X-Device-Id: <opaque>` enables per‑device read pointers; otherwise pointers are per user.

**Errors**

* Shape:

  ```json
  { "error": { "code": "message.validation.mime_type_unsupported", "message": "…", "trace_id": "req-…" } }
  ```
* Use conventional HTTP statuses.

**Privacy/telemetry**

* No message bodies or file bytes in logs/telemetry. IDs, sizes, and types only.

---

## 2) Resource model

```
Conversation (dm|room)
 ├─ Thread (first‑class; anchored by root_message_id)
 │   └─ Messages (each with conversation‑wide message_seq; may belong to thread)
 ├─ Messages (unthreaded/top‑level)
 ├─ Reactions (aggregated on messages)
 └─ Read State (conversation‑ and thread‑level pointers)
```

---

## 3) Schemas (canonical shapes)

### Conversation

```json
{
  "id": "c_123",
  "type": "dm" | "room",
  "title": "string|null",
  "member_ids": ["u_1", "u_2"],
  "created_by": "u_1",
  "created_at": "2025-01-01T12:00:00Z",
  "updated_at": "2025-01-01T12:00:00Z",
  "retention": { "mode": "keep" | "ephemeral", "ttl_hours": 24 },
  "deletion": { "mode": "soft" | "hard" },
  "aggregates": {
    "unread_count": 12,
    "message_count": 349
  }
}
```

### Thread

```json
{
  "id": "t_9",
  "conversation_id": "c_123",
  "root_message_id": "m_100",
  "subject": "string|null",
  "created_at": "2025-01-01T12:05:00Z",
  "updated_at": "2025-01-01T12:05:00Z",
  "aggregates": {
    "reply_count": 17,
    "last_message_seq": 341
  },
  "membership": {
    "muted_at": "2025-01-03T20:00:00Z|null",
    "last_read_seq": 330
  }
}
```

### Message

```json
{
  "id": "m_101",
  "conversation_id": "c_123",
  "thread_id": "t_9|null",
  "message_seq": 321,
  "author_id": "u_2",
  "in_reply_to_id": "m_100|null",
  "content": {
    "mime_type": "text/markdown" | "text/plain" |
                 "application/card+json" | "image/*" | "application/octet-stream",
    "body_text": "string|null",
    "body_json": { } | null,
    "body_bytes_base64": "string|null",
    "size_bytes": 0
  },
  "created_at": "2025-01-01T12:06:00Z",
  "updated_at": "2025-01-01T12:06:00Z",
  "deleted": false,
  "aggregates": {
    "replies": { "count": 3 },
    "reactions": [
      { "emoji_id": "u+1f44d", "count": 5, "me": true },
      { "emoji_id": "u+1f389", "count": 2, "me": false }
    ]
  }
}
```

**Content rules**

* Exactly one of `body_text` / `body_json` / `body_bytes_base64` MUST be non‑null.
* `text/*` → use `body_text`.
* `application/*+json` (e.g., `application/card+json`) → use `body_json`.
* Binary/attachments → `body_bytes_base64` + `size_bytes`.

### Event (WS/SSE)

```json
{
  "type": "message.created" | "message.updated" | "message.deleted" |
          "reaction.updated" | "thread.created" | "read_state.updated" |
          "system.keepalive" | "system.snapshot_marker",
  "event_offset": 4567,
  "emitted_at": "2025-01-01T12:06:01Z",
  "conversation_id": "c_123",
  "data": { ... }   // primary resource doc or minimal delta
}
```

---

## 4) Endpoints

### 4.1 Conversations

**Create conversation**
`POST /v1/conversations`
Headers: `Authorization`, `Idempotency-Key`
Body:

```json
{ "type": "dm", "member_ids": ["u_1", "u_2"], "title": null }
```

* DM idempotency: same two members → returns existing DM (or `409 conversation.conflict.dm_exists` if `force_new=true` is provided and disallowed).
* Returns: `200` Conversation + `ETag`.

**Get conversation**
`GET /v1/conversations/{conversation_id}?include=aggregates`
Returns: Conversation (+ aggregates if requested). Includes `ETag`.

**List conversations (cursor)**
`GET /v1/conversations?cursor=…&limit=50`
Returns:

```json
{ "items": [Conversation...], "next_cursor": "…" }
```

### 4.2 Threads

**Create thread**
`POST /v1/conversations/{conversation_id}/threads`
Headers: `Idempotency-Key`
Body:

```json
{ "root_message_id": "m_100", "subject": "optional" }
```

Returns: `200` Thread; emits `thread.created`.

**Get thread**
`GET /v1/threads/{thread_id}`
Returns: Thread (including caller’s `membership` block).

**Update thread** (rename, mute/unmute)
`PATCH /v1/threads/{thread_id}`
Headers: `If-Match`
Body:

```json
{ "subject": "New title", "muted": true }
```

Returns: updated Thread.

**List threads (by recent activity)**
`GET /v1/conversations/{conversation_id}/threads?after_message_seq=…&before_message_seq=…&limit=50&order=desc`

* Ordered by `last_message_seq` (desc default).

### 4.3 Messages

**Send message**
`POST /v1/conversations/{conversation_id}/messages`
Headers: `Idempotency-Key`
Body:

```json
{
  "thread_id": "t_9|null",
  "in_reply_to_id": "m_100|null",
  "content": { "mime_type": "text/markdown", "body_text": "**Hi**!" }
}
```

Returns: `200` Message (server assigns `message_seq`); emits `message.created`.

**Get message**
`GET /v1/messages/{message_id}`
Returns: Message.

**List messages**
`GET /v1/conversations/{conversation_id}/messages?after_message_seq=300&limit=50&order=asc&thread_id=t_9&include=aggregates`
Returns: windowed list, exclusive of bounds.

**Edit message**
`PATCH /v1/messages/{message_id}`
Headers: `If-Match`
Body:

```json
{ "content": { "mime_type": "text/markdown", "body_text": "Edited **text**" } }
```

Returns: updated Message; emits `message.updated`.

**Delete message**
`DELETE /v1/messages/{message_id}`
Headers: `If-Match`
Semantics: soft vs hard based on conversation policy.
Returns: updated Message (for soft) or empty (for hard); emits `message.deleted`.

### 4.4 Reactions

**Add/replace my reaction**
`PUT /v1/messages/{message_id}/reactions/{emoji}`

* `{emoji}`: shortcode (`:thumbsup:`) or Unicode id (`u+1f44d`, `u+1f3f3_u+fe0f_u+200d_u+1f308`)
  Returns: **updated Message**; emits `reaction.updated`.

**Remove my reaction**
`DELETE /v1/messages/{message_id}/reactions/{emoji}`
Returns: **updated Message**; emits `reaction.updated`.

**Emoji mapping**
`GET /v1/emojis` → `{ "<shortcode>": "<emoji_id>" }`

### 4.5 Read State

**Get conversation read state**
`GET /v1/conversations/{conversation_id}/read_state`
Optional header: `X-Device-Id`
Returns:

```json
{ "last_read_seq": 321, "updated_at": "…" }
```

**Advance conversation read state**
`PATCH /v1/conversations/{conversation_id}/read_state`
Body: `{ "last_read_seq": 333 }` (must be ≥ current)
Returns: updated pointer; emits `read_state.updated`.

**Get/Advance thread read state**
`GET /v1/threads/{thread_id}/read_state` /
`PATCH /v1/threads/{thread_id}/read_state` (same semantics)

### 4.6 Event Streams (real time)

**WebSocket**
`GET /v1/conversations/{conversation_id}/events.ws?after_event_offset=4566`

* Protocol: JSON messages per event (same schema as below)
* Keepalive: `system.keepalive` ~25s
* If client is too far behind (compaction), server closes with code mapped to `stream.offset_expired`—client must re‑sync via REST and reconnect.

**Server‑Sent Events (SSE)**
`GET /v1/conversations/{conversation_id}/events.sse?after_event_offset=4566`

* `Content-Type: text/event-stream`
* Data lines are JSON event payloads (see Event schema).
* On compaction: `410 GONE` with error body `stream.offset_expired`.

**Snapshot start**

* If `after_event_offset` is absent, server picks a recent consistent offset and emits a `system.snapshot_marker` event first.

---

## 5) Permissions & security (summary)

* Caller must be a member of the target conversation to read or post (except future public channels).
* `type=dm` creation enforces exactly two distinct users.
* Thread creation requires `root_message_id` in the same conversation.
* Reaction & read state endpoints require membership and visibility to the target message/thread.

---

## 6) Error catalog (non‑exhaustive)

* `conversation.conflict.dm_exists` (409)
* `conversation.not_found` (404)
* `message.validation.mime_type_unsupported` (422)
* `message.validation.body_missing` (422)
* `message.not_found` (404)
* `message.concurrency.etag_mismatch` (412)
* `thread.validation.root_not_in_conversation` (422)
* `thread.not_found` (404)
* `reaction.validation.emoji_unknown` (422)
* `read_state.validation.non_monotonic` (422)
* `stream.offset_expired` (410 for SSE; WS close with mapped reason)
* `rate_limited` (429)

---

## 7) Examples

### 7.1 Send a message (idempotent)

```
POST /v1/conversations/c_123/messages
Authorization: Bearer <token>
Idempotency-Key: 5037bf2e-…

{
  "content": { "mime_type": "text/markdown", "body_text": "**Hi**!" },
  "in_reply_to_id": "m_100"
}
```

**200**

```
ETag: "m_101:8b1a9953…"
{
  "id": "m_101",
  "conversation_id": "c_123",
  "thread_id": "t_9",
  "message_seq": 321,
  ...
}
```

### 7.2 List messages (window)

```
GET /v1/conversations/c_123/messages?after_message_seq=300&limit=50&order=asc&include=aggregates
Authorization: Bearer <token>
```

**200**

```json
{ "items": [ { "id": "m_301", ... }, ... ] }
```

### 7.3 React to a message

```
PUT /v1/messages/m_101/reactions/:thumbsup
Authorization: Bearer <token>
```

**200** → updated `Message.aggregates.reactions` (counts + `me`)

### 7.4 Advance read pointer (per device)

```
PATCH /v1/conversations/c_123/read_state
Authorization: Bearer <token>
X-Device-Id: iphone-13-pro

{ "last_read_seq": 321 }
```

**200**

```json
{ "last_read_seq": 321, "updated_at": "…" }
```

### 7.5 WebSocket subscription

```
GET /v1/conversations/c_123/events.ws?after_event_offset=4566
Sec-WebSocket-Protocol: chat.v1
```

**Server emits**

```json
{ "type": "system.keepalive", "event_offset": 4567, "emitted_at": "…" }
{ "type": "message.created",  "event_offset": 4568, "emitted_at": "…", "conversation_id":"c_123", "data": { "id":"m_101", "message_seq":321, ... } }
```

---

## 8) Implementation notes (server)

* **Thread backfill:** derive `thread_id` by traversing `in_reply_to_id` to the root for existing data.
* **`message_seq` allocator:** per‑conversation DB sequence or gap‑tolerant generator; assign on commit.
* **Emoji normalization:** accept path `{emoji}` as shortcode or Unicode, normalize to canonical `emoji_id` (`u+…(_u+…)*`) at write time; store canonical only.
* **Aggregates:** compute lazily; return only when `include=aggregates`.
* **Streams:** keep an append‑only event log with compaction; enforce `offset_expired` contract.

---

## 9) Minimal OpenAPI 3.1 (excerpt)

> This is an **excerpt** to guide codegen and linting. Fill in auth, components, and error responses similarly for all endpoints.

```yaml
openapi: 3.1.0
info:
  title: Messaging API
  version: "1.1"
servers:
  - url: https://api.example.com/v1
paths:
  /conversations:
    post:
      summary: Create a conversation
      operationId: createConversation
      parameters:
        - in: header
          name: Idempotency-Key
          schema: { type: string }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [type, member_ids]
              properties:
                type: { type: string, enum: [dm, room] }
                member_ids: { type: array, items: { type: string }, minItems: 2 }
                title: { type: [string, "null"] }
      responses:
        "200":
          description: Conversation created or returned (idempotent)
          headers:
            ETag: { schema: { type: string } }
          content:
            application/json:
              schema: { $ref: "#/components/schemas/Conversation" }
  /conversations/{conversation_id}:
    get:
      summary: Get conversation
      operationId: getConversation
      parameters:
        - in: path
          name: conversation_id
          required: true
          schema: { type: string }
        - in: query
          name: include
          schema: { type: string }
      responses:
        "200":
          description: OK
          headers:
            ETag: { schema: { type: string } }
          content:
            application/json:
              schema: { $ref: "#/components/schemas/Conversation" }
  /conversations/{conversation_id}/messages:
    get:
      summary: List messages
      operationId: listMessages
      parameters:
        - in: path
          name: conversation_id
          required: true
          schema: { type: string }
        - in: query
          name: after_message_seq
          schema: { type: integer, format: int64 }
        - in: query
          name: before_message_seq
          schema: { type: integer, format: int64 }
        - in: query
          name: limit
          schema: { type: integer, minimum: 1, maximum: 200, default: 50 }
        - in: query
          name: order
          schema: { type: string, enum: [asc, desc], default: asc }
        - in: query
          name: thread_id
          schema: { type: string }
        - in: query
          name: include
          schema: { type: string }
      responses:
        "200":
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  items:
                    type: array
                    items: { $ref: "#/components/schemas/Message" }
    post:
      summary: Send message
      operationId: sendMessage
      parameters:
        - in: header
          name: Idempotency-Key
          schema: { type: string }
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: "#/components/schemas/SendMessageRequest" }
      responses:
        "200":
          description: Created
          content:
            application/json:
              schema: { $ref: "#/components/schemas/Message" }
  /messages/{message_id}/reactions/{emoji}:
    put:
      summary: Add/replace my reaction
      operationId: putReaction
      parameters:
        - in: path
          name: message_id
          required: true
          schema: { type: string }
        - in: path
          name: emoji
          required: true
          schema: { type: string }
      responses:
        "200":
          description: Updated message with reaction aggregates
          content:
            application/json:
              schema: { $ref: "#/components/schemas/Message" }
    delete:
      summary: Remove my reaction
      operationId: deleteReaction
      parameters:
        - in: path
          name: message_id
          required: true
          schema: { type: string }
        - in: path
          name: emoji
          required: true
          schema: { type: string }
      responses:
        "200":
          description: Updated message with reaction aggregates
          content:
            application/json:
              schema: { $ref: "#/components/schemas/Message" }
components:
  schemas:
    Conversation:
      type: object
      properties:
        id: { type: string }
        type: { type: string, enum: [dm, room] }
        title: { type: [string, "null"] }
        member_ids: { type: array, items: { type: string } }
        created_by: { type: string }
        created_at: { type: string, format: date-time }
        updated_at: { type: string, format: date-time }
        retention:
          type: object
          properties:
            mode: { type: string, enum: [keep, ephemeral] }
            ttl_hours: { type: integer }
        deletion:
          type: object
          properties:
            mode: { type: string, enum: [soft, hard] }
    Message:
      type: object
      properties:
        id: { type: string }
        conversation_id: { type: string }
        thread_id: { type: ["string","null"] }
        message_seq: { type: integer, format: int64 }
        author_id: { type: string }
        in_reply_to_id: { type: ["string","null"] }
        content:
          type: object
          properties:
            mime_type: { type: string }
            body_text: { type: ["string","null"] }
            body_json: { type: ["object","null"] }
            body_bytes_base64: { type: ["string","null"] }
            size_bytes: { type: integer }
        created_at: { type: string, format: date-time }
        updated_at: { type: string, format: date-time }
        deleted: { type: boolean }
    SendMessageRequest:
      type: object
      required: [content]
      properties:
        thread_id: { type: ["string","null"] }
        in_reply_to_id: { type: ["string","null"] }
        content:
          type: object
          properties:
            mime_type: { type: string }
            body_text: { type: ["string","null"] }
            body_json: { type: ["object","null"] }
            body_bytes_base64: { type: ["string","null"] }
            size_bytes: { type: integer }
```

---

## 10) Open questions (tracked)

* Should we expose **message edit history** in v1.2 (e.g., `GET /messages/{id}/history`)?
* Do we need **per‑user reaction rosters** (privacy & fan‑out implications)?
* Attachment upload service contract (pre‑signed URLs vs managed upload route).

---

**This is the reference** for server implementation and client SDKs. If you’d like, I can generate a full OpenAPI bundle (all endpoints, components, and error responses) or a Postman collection from this spec.
