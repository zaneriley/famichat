openapi: 3.1.0
info:
  title: Messaging API
  version: "1.1.0"
  description: |
    Messaging API with first-class threads, consistent ordered pagination, idempotent mutations,
    and real-time events. JSON uses snake_case keys.
servers:
  - url: https://api.example.com/v1
    description: Production
  - url: https://staging.api.example.com/v1
    description: Staging
tags:
  - name: Conversations
  - name: Threads
  - name: Messages
  - name: Reactions
  - name: Read State
  - name: Events
  - name: Emojis
security:
  - bearerAuth: []

paths:
  /conversations:
    get:
      tags: [Conversations]
      summary: List conversations (cursor pagination)
      operationId: listConversations
      parameters:
        - $ref: '#/components/parameters/Cursor'
        - $ref: '#/components/parameters/LimitCursor'
        - $ref: '#/components/parameters/Include'
      responses:
        '200':
          description: OK
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/CursorPage_Conversation'
        default: { $ref: '#/components/responses/ErrorDefault' }
    post:
      tags: [Conversations]
      summary: Create a conversation (DM or room)
      operationId: createConversation
      parameters:
        - $ref: '#/components/parameters/IdempotencyKey'
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateConversationRequest'
      responses:
        '200':
          description: Created or returned (idempotent)
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Conversation' }
        '409':
          $ref: '#/components/responses/Conflict'
        default: { $ref: '#/components/responses/ErrorDefault' }

  /conversations/{conversation_id}:
    get:
      tags: [Conversations]
      summary: Get conversation
      operationId: getConversation
      parameters:
        - $ref: '#/components/parameters/ConversationId'
        - $ref: '#/components/parameters/Include'
      responses:
        '200':
          description: OK
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Conversation' }
        '404': { $ref: '#/components/responses/NotFound' }
        default: { $ref: '#/components/responses/ErrorDefault' }

  /conversations/{conversation_id}/threads:
    get:
      tags: [Threads]
      summary: List threads in a conversation (ordered by last_message_seq)
      operationId: listThreads
      parameters:
        - $ref: '#/components/parameters/ConversationId'
        - $ref: '#/components/parameters/AfterMessageSeq'
        - $ref: '#/components/parameters/BeforeMessageSeq'
        - $ref: '#/components/parameters/LimitWindow'
        - $ref: '#/components/parameters/Order'
        - $ref: '#/components/parameters/Include'
      responses:
        '200':
          description: OK
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Window_Thread'
        '404': { $ref: '#/components/responses/NotFound' }
        default: { $ref: '#/components/responses/ErrorDefault' }
    post:
      tags: [Threads]
      summary: Create a thread
      operationId: createThread
      parameters:
        - $ref: '#/components/parameters/ConversationId'
        - $ref: '#/components/parameters/IdempotencyKey'
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/CreateThreadRequest' }
      responses:
        '200':
          description: Created
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Thread' }
        '422': { $ref: '#/components/responses/Unprocessable' }
        default: { $ref: '#/components/responses/ErrorDefault' }

  /threads/{thread_id}:
    get:
      tags: [Threads]
      summary: Get thread
      operationId: getThread
      parameters:
        - $ref: '#/components/parameters/ThreadId'
        - $ref: '#/components/parameters/Include'
      responses:
        '200':
          description: OK
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Thread' }
        '404': { $ref: '#/components/responses/NotFound' }
        default: { $ref: '#/components/responses/ErrorDefault' }
    patch:
      tags: [Threads]
      summary: Update thread (rename, mute)
      operationId: updateThread
      parameters:
        - $ref: '#/components/parameters/ThreadId'
        - $ref: '#/components/parameters/IfMatch'
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/UpdateThreadRequest' }
      responses:
        '200':
          description: Updated
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Thread' }
        '412': { $ref: '#/components/responses/PreconditionFailed' }
        default: { $ref: '#/components/responses/ErrorDefault' }

  /conversations/{conversation_id}/messages:
    get:
      tags: [Messages]
      summary: List messages (windowed, ordered)
      operationId: listMessages
      parameters:
        - $ref: '#/components/parameters/ConversationId'
        - $ref: '#/components/parameters/AfterMessageSeq'
        - $ref: '#/components/parameters/BeforeMessageSeq'
        - $ref: '#/components/parameters/LimitWindow'
        - $ref: '#/components/parameters/Order'
        - $ref: '#/components/parameters/ThreadIdQuery'
        - $ref: '#/components/parameters/Include'
      responses:
        '200':
          description: OK
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Window_Message'
        '404': { $ref: '#/components/responses/NotFound' }
        default: { $ref: '#/components/responses/ErrorDefault' }
    post:
      tags: [Messages]
      summary: Send message
      operationId: sendMessage
      parameters:
        - $ref: '#/components/parameters/ConversationId'
        - $ref: '#/components/parameters/IdempotencyKey'
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/SendMessageRequest' }
      responses:
        '200':
          description: Created
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Message' }
        '422': { $ref: '#/components/responses/Unprocessable' }
        default: { $ref: '#/components/responses/ErrorDefault' }

  /messages/{message_id}:
    get:
      tags: [Messages]
      summary: Get message
      operationId: getMessage
      parameters:
        - $ref: '#/components/parameters/MessageId'
        - $ref: '#/components/parameters/Include'
      responses:
        '200':
          description: OK
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Message' }
        '404': { $ref: '#/components/responses/NotFound' }
        default: { $ref: '#/components/responses/ErrorDefault' }
    patch:
      tags: [Messages]
      summary: Edit message
      operationId: editMessage
      parameters:
        - $ref: '#/components/parameters/MessageId'
        - $ref: '#/components/parameters/IfMatch'
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/EditMessageRequest' }
      responses:
        '200':
          description: Updated
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Message' }
        '412': { $ref: '#/components/responses/PreconditionFailed' }
        default: { $ref: '#/components/responses/ErrorDefault' }
    delete:
      tags: [Messages]
      summary: Delete message
      operationId: deleteMessage
      parameters:
        - $ref: '#/components/parameters/MessageId'
        - $ref: '#/components/parameters/IfMatch'
      responses:
        '200':
          description: Deleted (soft/hard per policy). For soft delete, returns updated message.
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Message' }
        '204':
          description: Deleted (hard) with no body
        '412': { $ref: '#/components/responses/PreconditionFailed' }
        default: { $ref: '#/components/responses/ErrorDefault' }

  /messages/{message_id}/reactions/{emoji}:
    put:
      tags: [Reactions]
      summary: Add or replace my reaction
      operationId: putReaction
      parameters:
        - $ref: '#/components/parameters/MessageId'
        - $ref: '#/components/parameters/EmojiPath'
      responses:
        '200':
          description: Updated message with reaction aggregates
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Message' }
        '422': { $ref: '#/components/responses/Unprocessable' }
        default: { $ref: '#/components/responses/ErrorDefault' }
    delete:
      tags: [Reactions]
      summary: Remove my reaction
      operationId: deleteReaction
      parameters:
        - $ref: '#/components/parameters/MessageId'
        - $ref: '#/components/parameters/EmojiPath'
      responses:
        '200':
          description: Updated message with reaction aggregates
          headers:
            ETag: { $ref: '#/components/headers/ETag' }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Message' }
        default: { $ref: '#/components/responses/ErrorDefault' }

  /conversations/{conversation_id}/read_state:
    get:
      tags: [Read State]
      summary: Get conversation read state (optionally per device)
      operationId: getConversationReadState
      parameters:
        - $ref: '#/components/parameters/ConversationId'
        - $ref: '#/components/parameters/DeviceId'
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/ReadState' }
        '404': { $ref: '#/components/responses/NotFound' }
        default: { $ref: '#/components/responses/ErrorDefault' }
    patch:
      tags: [Read State]
      summary: Advance conversation read state
      operationId: patchConversationReadState
      parameters:
        - $ref: '#/components/parameters/ConversationId'
        - $ref: '#/components/parameters/DeviceId'
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/AdvanceReadStateRequest' }
      responses:
        '200':
          description: Updated
          content:
            application/json:
              schema: { $ref: '#/components/schemas/ReadState' }
        '422': { $ref: '#/components/responses/Unprocessable' }
        default: { $ref: '#/components/responses/ErrorDefault' }

  /threads/{thread_id}/read_state:
    get:
      tags: [Read State]
      summary: Get thread read state
      operationId: getThreadReadState
      parameters:
        - $ref: '#/components/parameters/ThreadId'
        - $ref: '#/components/parameters/DeviceId'
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema: { $ref: '#/components/schemas/ReadState' }
        '404': { $ref: '#/components/responses/NotFound' }
        default: { $ref: '#/components/responses/ErrorDefault' }
    patch:
      tags: [Read State]
      summary: Advance thread read state
      operationId: patchThreadReadState
      parameters:
        - $ref: '#/components/parameters/ThreadId'
        - $ref: '#/components/parameters/DeviceId'
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/AdvanceReadStateRequest' }
      responses:
        '200':
          description: Updated
          content:
            application/json:
              schema: { $ref: '#/components/schemas/ReadState' }
        '422': { $ref: '#/components/responses/Unprocessable' }
        default: { $ref: '#/components/responses/ErrorDefault' }

  /conversations/{conversation_id}/events.sse:
    get:
      tags: [Events]
      summary: Subscribe to conversation events via SSE
      operationId: subscribeConversationEventsSSE
      parameters:
        - $ref: '#/components/parameters/ConversationId'
        - $ref: '#/components/parameters/AfterEventOffset'
      responses:
        '200':
          description: Server-Sent Events stream (lines with `data: <json>\n\n`)
          content:
            text/event-stream:
              schema:
                type: string
                description: Stream of Event JSON lines prefixed by `data: `
        '410':
          description: Offset expired; client must re-sync via REST and reconnect
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Error' }
        default: { $ref: '#/components/responses/ErrorDefault' }
      x-websocket-alternative:
        path: /conversations/{conversation_id}/events.ws
        subprotocol: chat.v1
        note: WebSocket stream emits Event JSON frames identical to SSE data payloads.

  /emojis:
    get:
      tags: [Emojis]
      summary: Emoji mapping (shortcode -> emoji_id)
      operationId: listEmojis
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                additionalProperties:
                  type: string
                  description: Canonical emoji_id (e.g., u+1f44d or compound ids)
        default: { $ref: '#/components/responses/ErrorDefault' }

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

  headers:
    ETag:
      description: Strong validator for concurrency control
      schema: { type: string }

  parameters:
    ConversationId:
      in: path
      name: conversation_id
      required: true
      schema: { type: string }
    ThreadId:
      in: path
      name: thread_id
      required: true
      schema: { type: string }
    MessageId:
      in: path
      name: message_id
      required: true
      schema: { type: string }
    EmojiPath:
      in: path
      name: emoji
      required: true
      description: Shortcode (e.g., :thumbsup) or Unicode id (e.g., u+1f44d)
      schema: { type: string }
    IdempotencyKey:
      in: header
      name: Idempotency-Key
      required: false
      schema: { type: string, minLength: 8, maxLength: 128 }
    IfMatch:
      in: header
      name: If-Match
      required: true
      schema: { type: string }
    DeviceId:
      in: header
      name: X-Device-Id
      required: false
      schema: { type: string, maxLength: 128 }
    AfterMessageSeq:
      in: query
      name: after_message_seq
      required: false
      description: Exclusive lower bound
      schema: { type: integer, format: int64, minimum: 0 }
    BeforeMessageSeq:
      in: query
      name: before_message_seq
      required: false
      description: Exclusive upper bound
      schema: { type: integer, format: int64, minimum: 0 }
    AfterEventOffset:
      in: query
      name: after_event_offset
      required: false
      description: Exclusive lower bound for event stream offset
      schema: { type: integer, format: int64, minimum: 0 }
    LimitWindow:
      in: query
      name: limit
      required: false
      schema: { type: integer, minimum: 1, maximum: 200, default: 50 }
    LimitCursor:
      in: query
      name: limit
      required: false
      schema: { type: integer, minimum: 1, maximum: 200, default: 50 }
    Order:
      in: query
      name: order
      required: false
      schema:
        type: string
        enum: [asc, desc]
        default: asc
    ThreadIdQuery:
      in: query
      name: thread_id
      required: false
      schema: { type: string }
    Cursor:
      in: query
      name: cursor
      required: false
      schema: { type: string }
    Include:
      in: query
      name: include
      required: false
      description: Comma-separated hints (e.g., aggregates,permissions)
      schema: { type: string }

  responses:
    NotFound:
      description: Resource not found
      content: { application/json: { schema: { $ref: '#/components/schemas/Error' } } }
    Conflict:
      description: Conflict (e.g., DM already exists)
      content: { application/json: { schema: { $ref: '#/components/schemas/Error' } } }
    PreconditionFailed:
      description: ETag precondition failed
      content: { application/json: { schema: { $ref: '#/components/schemas/Error' } } }
    Unprocessable:
      description: Validation failed
      content: { application/json: { schema: { $ref: '#/components/schemas/Error' } } }
    ErrorDefault:
      description: Error
      content: { application/json: { schema: { $ref: '#/components/schemas/Error' } } }

  schemas:
    Conversation:
      type: object
      required: [id, type, member_ids, created_by, created_at, updated_at]
      properties:
        id: { type: string }
        type: { type: string, enum: [dm, room] }
        title: { type: [ 'string', 'null' ] }
        member_ids:
          type: array
          items: { type: string }
          minItems: 2
        created_by: { type: string }
        created_at: { type: string, format: date-time }
        updated_at: { type: string, format: date-time }
        retention:
          type: object
          properties:
            mode: { type: string, enum: [keep, ephemeral] }
            ttl_hours: { type: integer, minimum: 1 }
        deletion:
          type: object
          properties:
            mode: { type: string, enum: [soft, hard] }
        aggregates:
          type: object
          properties:
            unread_count: { type: integer, minimum: 0 }
            message_count: { type: integer, minimum: 0 }

    Thread:
      type: object
      required: [id, conversation_id, root_message_id, created_at, updated_at]
      properties:
        id: { type: string }
        conversation_id: { type: string }
        root_message_id: { type: string }
        subject: { type: [ 'string', 'null' ] }
        created_at: { type: string, format: date-time }
        updated_at: { type: string, format: date-time }
        aggregates:
          type: object
          properties:
            reply_count: { type: integer, minimum: 0 }
            last_message_seq: { type: integer, format: int64, minimum: 0 }
        membership:
          type: object
          description: Per-caller membership data
          properties:
            muted_at: { type: [ 'string', 'null' ], format: date-time }
            last_read_seq: { type: integer, format: int64, minimum: 0 }

    Message:
      type: object
      required: [id, conversation_id, message_seq, author_id, content, created_at, updated_at, deleted]
      properties:
        id: { type: string }
        conversation_id: { type: string }
        thread_id: { type: [ 'string', 'null' ] }
        message_seq: { type: integer, format: int64, minimum: 0 }
        author_id: { type: string }
        in_reply_to_id: { type: [ 'string', 'null' ] }
        content:
          $ref: '#/components/schemas/MessageContent'
        created_at: { type: string, format: date-time }
        updated_at: { type: string, format: date-time }
        deleted: { type: boolean }
        aggregates:
          type: object
          properties:
            replies:
              type: object
              properties:
                count: { type: integer, minimum: 0 }
            reactions:
              type: array
              items:
                $ref: '#/components/schemas/ReactionAggregate'

    MessageContent:
      type: object
      description: One of body_text, body_json, or body_bytes_base64 must be non-null
      properties:
        mime_type:
          type: string
          description: e.g., text/markdown, text/plain, application/card+json, image/png
        body_text: { type: [ 'string', 'null' ] }
        body_json: { type: [ 'object', 'null' ] }
        body_bytes_base64: { type: [ 'string', 'null' ] }
        size_bytes: { type: integer, minimum: 0 }
      required: [mime_type]

    ReactionAggregate:
      type: object
      required: [emoji_id, count, me]
      properties:
        emoji_id: { type: string, description: Canonical id (e.g., u+1f44d) }
        count: { type: integer, minimum: 0 }
        me: { type: boolean }

    ReadState:
      type: object
      required: [last_read_seq, updated_at]
      properties:
        last_read_seq: { type: integer, format: int64, minimum: 0 }
        updated_at: { type: string, format: date-time }

    AdvanceReadStateRequest:
      type: object
      required: [last_read_seq]
      properties:
        last_read_seq: { type: integer, format: int64, minimum: 0 }

    CreateConversationRequest:
      type: object
      required: [type, member_ids]
      properties:
        type: { type: string, enum: [dm, room] }
        member_ids:
          type: array
          items: { type: string }
          minItems: 2
        title: { type: [ 'string', 'null' ] }
        force_new:
          type: boolean
          description: For type=dm, request a new DM even if one exists (may be disallowed by policy)

    CreateThreadRequest:
      type: object
      required: [root_message_id]
      properties:
        root_message_id: { type: string }
        subject: { type: [ 'string', 'null' ] }

    UpdateThreadRequest:
      type: object
      properties:
        subject: { type: [ 'string', 'null' ] }
        muted: { type: boolean }

    SendMessageRequest:
      type: object
      required: [content]
      properties:
        thread_id: { type: [ 'string', 'null' ] }
        in_reply_to_id: { type: [ 'string', 'null' ] }
        content: { $ref: '#/components/schemas/MessageContent' }

    EditMessageRequest:
      type: object
      required: [content]
      properties:
        content: { $ref: '#/components/schemas/MessageContent' }

    CursorPage_Conversation:
      type: object
      required: [items]
      properties:
        items:
          type: array
          items: { $ref: '#/components/schemas/Conversation' }
        next_cursor: { type: [ 'string', 'null' ] }

    Window_Message:
      type: object
      required: [items]
      properties:
        items:
          type: array
          items: { $ref: '#/components/schemas/Message' }

    Window_Thread:
      type: object
      required: [items]
      properties:
        items:
          type: array
          items: { $ref: '#/components/schemas/Thread' }

    Event:
      type: object
      required: [type, event_offset, emitted_at, conversation_id]
      properties:
        type:
          type: string
          enum:
            - message.created
            - message.updated
            - message.deleted
            - reaction.updated
            - thread.created
            - read_state.updated
            - system.keepalive
            - system.snapshot_marker
        event_offset: { type: integer, format: int64, minimum: 0 }
        emitted_at: { type: string, format: date-time }
        conversation_id: { type: string }
        data:
          description: Event payload (resource doc or delta)
          oneOf:
            - $ref: '#/components/schemas/Message'
            - $ref: '#/components/schemas/Thread'
            - $ref: '#/components/schemas/ReadState'
            - type: object

    Error:
      type: object
      required: [error]
      properties:
        error:
          type: object
          required: [code, message]
          properties:
            code: { type: string, example: message.validation.mime_type_unsupported }
            message: { type: string }
            trace_id: { type: string }

