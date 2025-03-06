defmodule Famichat.Repo.Seed do
  import Ecto.UUID
  alias Famichat.Repo
  alias Famichat.Chat
  alias Famichat.Chat.{User, Family, Conversation, Message}

  # --- Helper functions (no changes here) ---
  def create_family(attrs) do
    %Family{}
    |> Family.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, family} ->
        IO.puts("Created family: #{family.id}")
        {:ok, family}

      {:error, changeset} ->
        IO.puts("Error creating family:")
        IO.inspect(changeset.errors)
        {:error, changeset}
    end
  end

  def create_user(family_id, attrs) do
    user_attrs = Map.merge(%{family_id: family_id}, attrs)

    case Chat.create_user(user_attrs) do
      {:ok, user} ->
        IO.puts("Created user: #{user.username} (ID: #{user.id})")
        {:ok, user}

      {:error, changeset} ->
        IO.puts("Error creating user:")
        IO.inspect(changeset.errors)
        {:error, changeset}

      {:error, :invalid_input} ->
        IO.puts("Invalid input for user creation.")
        {:error, :invalid_input}
    end
  end

  defp create_conversation(
         family_id,
         conversation_type,
         metadata \\ %{},
         opts \\ %{}
       ) do
    conversation_attrs =
      if conversation_type == :direct do
        # Expect opts to have :user1_id and :user2_id for direct conversations
        direct_key =
          Conversation.compute_direct_key(
            opts[:user1_id],
            opts[:user2_id],
            family_id
          )

        %{
          family_id: family_id,
          conversation_type: conversation_type,
          direct_key: direct_key,
          metadata: metadata
        }
      else
        %{
          family_id: family_id,
          conversation_type: conversation_type,
          metadata: metadata
        }
      end

    case Conversation.create_changeset(%Conversation{}, conversation_attrs)
         |> Repo.insert() do
      {:ok, conversation} ->
        IO.puts("Created #{conversation_type} conversation: #{conversation.id}")
        {:ok, conversation}

      {:error, changeset} ->
        IO.puts("Error creating conversation:")
        IO.inspect(changeset.errors)
        {:error, changeset}
    end
  end

  defp add_users_to_conversation(conversation, user_ids) do
    Enum.each(user_ids, fn user_id ->
      attrs = %{conversation_id: conversation.id, user_id: user_id}

      case %Famichat.Chat.ConversationParticipant{}
           |> Famichat.Chat.ConversationParticipant.changeset(attrs)
           |> Repo.insert(on_conflict: :nothing) do
        {:ok, _participant} ->
          IO.puts("  Added user #{user_id} to conversation #{conversation.id}")

        {:error, changeset} ->
          IO.puts(
            "  Error adding user #{user_id} to conversation #{conversation.id}:"
          )

          IO.inspect(changeset.errors)
      end
    end)
  end

  defp create_message(
         conversation_id,
         sender_id,
         message_type,
         content,
         metadata \\ %{},
         timestamp \\ DateTime.utc_now()
       ) do
    message_attrs = %{
      conversation_id: conversation_id,
      sender_id: sender_id,
      message_type: message_type,
      content: content,
      metadata: metadata,
      timestamp: timestamp
    }

    case Message.changeset(%Message{}, message_attrs) |> Repo.insert() do
      {:ok, message} ->
        IO.puts(
          "  Created message (type: #{message_type}) in conversation #{conversation_id} from sender #{sender_id}"
        )

        {:ok, message}

      {:error, changeset} ->
        IO.puts("Error creating message:")
        IO.inspect(changeset.errors)
        {:error, changeset}
    end
  end

  # --- Seed Data Creation ---
  def run do
    IO.puts("Starting seed data creation...")

    # --- Families ---
    IO.puts("\n--- Creating Families ---")
    {:ok, homelab_family} = create_family(%{"name" => "Homelab"})
    {:ok, mclaws_family} = create_family(%{"name" => "Mclaws"})
    {:ok, li_family} = create_family(%{"name" => "Li"})
    {:ok, sample_family} = create_family(%{"name" => "Sample"})

    # --- Users ---
    IO.puts("\n--- Creating Users ---")

    {:ok, zane_user} =
      create_user(homelab_family.id, %{
        username: "Zane",
        role: "admin",
        email: "zane@example.com"
      })

    {:ok, naho_user} =
      create_user(homelab_family.id, %{
        username: "Naho",
        role: "member",
        email: "naho@example.com"
      })

    {:ok, jacob_user} =
      create_user(mclaws_family.id, %{
        username: "Jacob",
        role: "admin",
        email: "jacob@example.com"
      })

    {:ok, shae_user} =
      create_user(mclaws_family.id, %{
        username: "Shae",
        role: "member",
        email: "shae@example.com"
      })

    {:ok, katharine_user} =
      create_user(li_family.id, %{
        username: "Katharine",
        role: "admin",
        email: "katharine@example.com"
      })

    {:ok, yuka_user} =
      create_user(li_family.id, %{
        username: "Yuka",
        role: "member",
        email: "yuka@example.com"
      })

    {:ok, chelsey_user} =
      create_user(sample_family.id, %{
        username: "Chelsey",
        role: "admin",
        email: "chelsey@example.com"
      })

    {:ok, clayton_user} =
      create_user(sample_family.id, %{
        username: "Clayton",
        role: "member",
        email: "clayton@example.com"
      })

    {:ok, theo_user} =
      create_user(sample_family.id, %{
        username: "Theo",
        role: "member",
        email: "theo@example.com"
      })

    # --- Direct Conversations ---
    IO.puts("\n--- Creating Direct Conversations ---")

    {:ok, convo_zane_naho} =
      create_conversation(homelab_family.id, :direct, %{}, %{
        user1_id: zane_user.id,
        user2_id: naho_user.id
      })

    add_users_to_conversation(convo_zane_naho, [zane_user.id, naho_user.id])

    {:ok, convo_jacob_shae} =
      create_conversation(mclaws_family.id, :direct, %{}, %{
        user1_id: jacob_user.id,
        user2_id: shae_user.id
      })

    add_users_to_conversation(convo_jacob_shae, [jacob_user.id, shae_user.id])

    {:ok, convo_katharine_yuka} =
      create_conversation(li_family.id, :direct, %{}, %{
        user1_id: katharine_user.id,
        user2_id: yuka_user.id
      })

    add_users_to_conversation(convo_katharine_yuka, [
      katharine_user.id,
      yuka_user.id
    ])

    {:ok, convo_chelsey_clayton} =
      create_conversation(sample_family.id, :direct, %{}, %{
        user1_id: chelsey_user.id,
        user2_id: clayton_user.id
      })

    add_users_to_conversation(convo_chelsey_clayton, [
      chelsey_user.id,
      clayton_user.id
    ])

    {:ok, convo_chelsey_theo} =
      create_conversation(sample_family.id, :direct, %{}, %{
        user1_id: chelsey_user.id,
        user2_id: theo_user.id
      })

    add_users_to_conversation(convo_chelsey_theo, [
      chelsey_user.id,
      theo_user.id
    ])

    # --- Group Conversation (within Sample family) ---
    IO.puts("\n--- Creating Group Conversation ---")

    {:ok, convo_sample_group} =
      create_conversation(
        sample_family.id,
        :group,
        %{
          "name" => "Sample Family Group Chat"
        },
        %{}
      )

    add_users_to_conversation(convo_sample_group, [
      chelsey_user.id,
      clayton_user.id,
      theo_user.id
    ])

    # --- Messages ---
    IO.puts("\n--- Creating Messages ---")
    # Conversation Zane & Naho
    create_message(
      convo_zane_naho.id,
      zane_user.id,
      :text,
      "Hey Naho, everything good?"
    )

    create_message(
      convo_zane_naho.id,
      naho_user.id,
      :text,
      "Yeah, just working from home today. You?"
    )

    # Conversation Jacob & Shae
    create_message(
      convo_jacob_shae.id,
      jacob_user.id,
      :text,
      "Shae, can you pick up groceries later?"
    )

    create_message(
      convo_jacob_shae.id,
      shae_user.id,
      :text,
      "Sure, what do we need?"
    )

    # Conversation Katharine & Yuka
    create_message(
      convo_katharine_yuka.id,
      katharine_user.id,
      :text,
      "Yuka, did you book the flights?"
    )

    create_message(
      convo_katharine_yuka.id,
      yuka_user.id,
      :text,
      "Almost done, just confirming dates."
    )

    # Conversation Chelsey & Clayton
    create_message(
      convo_chelsey_clayton.id,
      chelsey_user.id,
      :text,
      "Clayton, Theo's soccer practice is at 4pm."
    )

    create_message(
      convo_chelsey_clayton.id,
      clayton_user.id,
      :text,
      "Got it, thanks for the reminder."
    )

    # Conversation Chelsey & Theo
    create_message(
      convo_chelsey_theo.id,
      chelsey_user.id,
      :text,
      "Theo, how was school today?"
    )

    create_message(
      convo_chelsey_theo.id,
      theo_user.id,
      :text,
      "It was fun! We learned about space."
    )

    # Group Conversation (Sample Family)
    create_message(
      convo_sample_group.id,
      chelsey_user.id,
      :text,
      "Hi everyone, quick update on the family trip."
    )

    create_message(
      convo_sample_group.id,
      clayton_user.id,
      :text,
      "Sounds good, Chelsey! Looking forward to it."
    )

    create_message(
      convo_sample_group.id,
      theo_user.id,
      :text,
      "Are we there yet?"
    )

    IO.puts("\nSeed data creation completed!")
  end
end

# Execute the seed run
Famichat.Repo.Seed.run()
