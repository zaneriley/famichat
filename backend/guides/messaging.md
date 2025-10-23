# Messaging Implementation Guide

This guide documents the implementation details of Famichat's messaging system, providing developers with a comprehensive reference for working with messages and conversations.

## Current Implementation Status

The following messaging features are currently implemented:

- **Basic Message Sending**: Core functionality for sending text messages
- **Self-Messaging**: Users can message themselves as a personal notepad
- **Family-Based Messaging**: Messaging between users is allowed only when they share a common family

## Core Messaging Concepts

### Message Types and Structure

Messages in Famichat follow a consistent structure:

```elixir
defmodule Famichat.Chat.Message do
  # Message structure
  schema "messages" do
    field :content, :string
    field :message_type, Ecto.Enum, values: [:text], default: :text
    field :status, Ecto.Enum, values: [:sent, :delivered, :read], default: :sent
    
    belongs_to :conversation, Famichat.Chat.Conversation
    belongs_to :sender, Famichat.Chat.User
    
    timestamps()
  end
end
```

### Conversation Types

Famichat supports multiple conversation types:

- `:direct` - Conversations between exactly two users
- `:self` - Personal conversations for a single user (like a notepad)
- `:group` - Multi-user conversations (future implementation)
- `:family` - Family-wide conversations (future implementation)

## Using the Message Service

### Sending Messages

To send a message:

```elixir
# Send a message in a conversation
{:ok, message} = MessageService.send_message(sender_id, conversation_id, "Hello world!")

# The function returns:
# - {:ok, message} on success with the created message
# - {:error, changeset} on validation failure
```

### Message Retrieval

To retrieve messages in a conversation:

```elixir
# Get all messages for a conversation
{:ok, messages} = MessageService.get_conversation_messages(conversation_id)

# The function returns:
# - {:ok, messages} with messages ordered by insertion time
# - {:ok, []} for a conversation with no messages
# - {:error, :not_found} if the conversation doesn't exist
```

## Working with Conversations

### Creating Conversations

#### Self Conversations

Users can create conversations with themselves for note-taking:

```elixir
# Create a self-conversation
{:ok, conversation} = ConversationService.create_self_conversation(user_id)
```

#### Direct Conversations

Direct conversations between users require they share a family:

```elixir
# Create a direct conversation (succeeds only if users share a family)
{:ok, conversation} = ConversationService.create_direct_conversation(user1_id, user2_id)

# If a conversation already exists between these users, the existing one is returned
```

### Listing Conversations

To list a user's conversations:

```elixir
# List all direct conversations for a user
{:ok, direct_conversations} = ConversationService.list_user_conversations(user_id)

# List self-conversations for a user
{:ok, self_conversations} = ConversationService.list_user_self_conversations(user_id)
```

## Business Rules

### Family-Based Authorization

Users can only create conversations with other users if they share at least one common family. This rule is enforced at the service level:

```elixir
# This will return {:error, :no_shared_family} if users don't share a family
{:error, :no_shared_family} = ConversationService.create_direct_conversation(user1_id, user3_id)
```

### Message Status Tracking

All messages are created with a default status of `:sent`. Future implementations will support `:delivered` and `:read` statuses.

## Telemetry Integration

All message service operations are instrumented with telemetry for performance monitoring:

```elixir
# Example of how telemetry spans wrap key functions
:telemetry.span([:famichat, :message_service, :get_conversation_messages], %{conversation_id: id}, fn ->
  # Message retrieval logic
  {{:ok, messages}, %{count: length(messages)}}
end)
```

For more details on telemetry, see the [Telemetry & Performance](telemetry.html) guide.

## Real-Time MessageChannel

Phoenix Channels deliver real-time updates once a message has been accepted by the backend.
The `FamichatWeb.MessageChannel` exposes conversation-type-aware topics using the format
`message:<type>:<conversation_id>` where `type` is one of `self`, `direct`, `group`, or `family`.

### Authentication and Subscription

1. Create an access token via the Accounts session API:
   ```elixir
   {:ok, session} =
     Famichat.Accounts.start_session(user, %{
       id: "browser-session-uuid",
       user_agent: "Famichat Web",
       ip: "127.0.0.1"
     })

   token = session.access_token
   ```
2. Connect the socket with the bearer token and join a channel:
   ```javascript
   const socket = new Socket("/socket", {params: {token}});
   socket.connect();

   const channel = socket.channel(`message:direct:${conversationId}`);
   channel.join()
     .receive("ok", () => console.log("joined"))
     .receive("error", (err) => console.error("join failed", err));
   ```

Tokens are verified on connect via `Accounts.verify_access_token/1`; if verification fails the
socket connection is rejected.

### Broadcast Payloads and Telemetry

Each `new_msg` push is rebroadcast with the payload:

```json
{
  "body": "...",
  "user_id": "<sender-id>",
  "version_tag": "...",        // present only for encrypted messages
  "encryption_flag": true,     // present only for encrypted messages
  "key_id": "..."              // present only for encrypted messages
}
```

Telemetry accompanies every broadcast and acknowledgment:

| Event                                         | Metadata highlights                                                  |
|-----------------------------------------------|----------------------------------------------------------------------|
| `[:famichat, :message_channel, :broadcast]`   | `:user_id`, `:conversation_type`, `:conversation_id`, `:message_size`, `:encryption_status` |
| `[:famichat, :message_channel, :ack]`         | `:user_id`, `:conversation_type`, `:conversation_id`, `:message_id`  |

Sensitive encryption metadata (`key_id`, `version_tag`, `encryption_flag`) is filtered before
telemetry emission, while the raw payload delivered to subscribers retains the fields intact.

### Manual Smoke Tests

Use the ChannelCase helpers or IEx to send ad-hoc broadcasts:

```elixir
topic = "message:direct:#{conversation_id}"
payload = %{"body" => "hello world"}

FamichatWeb.Endpoint.broadcast!(topic, "new_msg", payload)
```

Attach a temporary telemetry handler to inspect metadata during debugging:

```elixir
handler_id = "debug-broadcast-#{System.unique_integer()}"

:telemetry.attach(handler_id, [:famichat, :message_channel, :broadcast],
  fn _event, measurements, metadata, _ ->
    IO.inspect({measurements, metadata}, label: "broadcast")
  end,
  nil
)
```

See `test/famichat_web/channels/message_channel_test.exs` for comprehensive examples that assert
payload content and telemetry for self, direct, group, and family conversations.

> Note: Mobile platforms aggressively limit background WebSocket activity. Expect iOS to suspend
> connections after roughly 30 seconds and Android Doze mode to delay background delivery. Clients
> should reconnect when returning to the foreground.
