defmodule Famichat.ChatFixtures do
  @moduledoc """
  Test fixture factory for chat-related schemas.

  Provides functions to generate:
  - Families
  - Users (with automatic family association)
  - Conversations (with participants)
  - Timestamp helpers

  ## Usage

      alias Famichat.ChatFixtures

      family = ChatFixtures.family_fixture()
      user = ChatFixtures.user_fixture()
      conv = ChatFixtures.conversation_fixture()
  """

  alias Famichat.Chat.{Conversation}
  alias Famichat.Repo

  @doc """
  Generates a unique username with random suffix.

  ## Examples

      unique_user_username() # => "some username123"
  """
  def unique_user_username,
    do: "some username#{System.unique_integer([:positive])}"

  @doc """
  Generates a unique family name with random suffix.

  ## Examples

      unique_family_name() # => "Family 456"
  """
  def unique_family_name,
    do: "Family #{System.unique_integer([:positive])}"

  @doc """
  Creates a family fixture with valid attributes.

  ## Parameters
    - attrs: Optional map to override default attributes

  ## Returns
    - `Famichat.Chat.Family` struct

  ## Examples

      family_fixture(%{name: "Custom Family"})
  """
  def family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{
        name: unique_family_name()
      })
      |> Famichat.Chat.create_family()

    family
  end

  @doc """
  Creates a user fixture associated with a family.

  ## Parameters
    - attrs: Optional map to override:
      - `username`
      - `family_id`
      - `role`

  ## Returns
    - `Famichat.Chat.User` struct

  ## Side Effects
    - Automatically creates a family if not provided

  ## Examples

      user_fixture(%{username: "special_user"})
  """
  def user_fixture(attrs \\ %{}) do
    family = family_fixture()

    {:ok, user} =
      attrs
      |> Enum.into(%{
        username: unique_user_username(),
        family_id: family.id,
        role: :member
      })
      |> Famichat.Chat.create_user()

    user
  end

  @doc """
  Creates a conversation fixture with participants.

  ## Parameters
    - attrs: Optional map to override:
      - `family_id`
      - `conversation_type`
      - `metadata`

  ## Returns
    - `Famichat.Chat.Conversation` struct

  ## Side Effects
    - Creates associated family and user
    - Adds participant record via `ConversationParticipant`

  ## Examples

      conversation_fixture(%{conversation_type: :group})
  """
  def conversation_fixture(attrs \\ %{}) do
    family = family_fixture()
    user = user_fixture(%{family_id: family.id})

    conversation =
      %Conversation{}
      |> Conversation.changeset(
        Map.merge(
          %{
            family_id: family.id,
            conversation_type: :direct,
            metadata: %{}
          },
          attrs
        )
      )
      |> Repo.insert!()

    %Famichat.Chat.ConversationParticipant{}
    |> Famichat.Chat.ConversationParticipant.changeset(%{
      conversation_id: conversation.id,
      user_id: user.id
    })
    |> Repo.insert!()

    conversation
  end

  @doc """
  Generates a truncated UTC timestamp for consistent time testing.

  ## Parameters
    - offset_seconds: Integer seconds to add/subtract from now

  ## Returns
    - `DateTime.t` with microsecond precision

  ## Examples

      truncated_timestamp()      # Current time
      truncated_timestamp(-3600) # 1 hour ago
  """
  def truncated_timestamp(offset_seconds \\ 0)
      when is_integer(offset_seconds) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(offset_seconds, :second)
    |> NaiveDateTime.truncate(:microsecond)
    |> DateTime.from_naive!("Etc/UTC")
  end
end
