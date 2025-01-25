alias Famichat.Repo
alias Famichat.Chat.{User, Message}

# Create test users
{:ok, naho} = %User{username: "naho"} |> Repo.insert()
{:ok, zane} = %User{username: "zane"} |> Repo.insert()

# Create some test messages
messages = [
  %{
    sender_id: naho.id,
    message_type: "text",
    content: "Hello everyone!",
    metadata: %{reactions: []}
  },
  %{
    sender_id: zane.id,
    message_type: "text",
    content: "Hi naho!",
    metadata: %{reactions: []}
  },
  %{
    sender_id: naho.id,
    message_type: "image",
    content: "Check out this photo!",
    media_url: "/uploads/test/sample.jpg",
    metadata: %{
      dimensions: %{width: 800, height: 600},
      size: 1024567,
      mime_type: "image/jpeg"
    }
  }
]

Enum.each(messages, fn message ->
  %Message{}
  |> Message.changeset(message)
  |> Repo.insert!()
end)
