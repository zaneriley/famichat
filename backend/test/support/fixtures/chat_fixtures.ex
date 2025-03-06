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

  alias Famichat.Chat.{Conversation, ConversationParticipant}
  alias Famichat.Repo

  @doc """
  Generates a unique username with random suffix.

  ## Examples

      unique_user_username() # => "some username123"
  """
  def unique_user_username,
    do: "some username#{System.unique_integer([:positive])}"

  @doc """
  Generates a unique email with random suffix.

  ## Examples

      unique_user_email() # => "user1234@example.com"
  """
  def unique_user_email,
    do: "user#{System.unique_integer([:positive])}@example.com"

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
        email: unique_user_email(),
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
      - `conversation_type` - Defaults to :direct
      - `metadata`
      - `user1` - (optional) first participant (a %User{} struct)
      - `user2` - (optional) second participant (a %User{} struct)
      - `direct_key` - (optional) direct conversation key. If not provided, it is computed.

  ## Returns
    - `Famichat.Chat.Conversation` struct

  ## Examples

      conversation_fixture(%{conversation_type: :group})
      conversation_fixture(%{conversation_type: :direct})
  """
  def conversation_fixture(attrs \\ %{}) do
    attrs = prepare_conversation_attrs(attrs)
    create_conversation_by_type(attrs)
  end

  # Private helper functions

  defp prepare_conversation_attrs(attrs) do
    family = Map.get(attrs, :family) || family_fixture()

    attrs
    |> Map.put_new(:family_id, family.id)
    |> Map.put_new(:conversation_type, :direct)
    |> Map.put_new(:metadata, %{})
    |> Map.put(:family, family)
  end

  defp create_conversation_by_type(%{conversation_type: :direct} = attrs) do
    # Create two distinct users or accept overrides via attrs
    user1 =
      Map.get(attrs, :user1) || user_fixture(%{family_id: attrs.family_id})

    user2 =
      Map.get(attrs, :user2) || user_fixture(%{family_id: attrs.family_id})

    # Compute direct_key if not already provided
    direct_key =
      Map.get(attrs, :direct_key) ||
        Famichat.Chat.Conversation.compute_direct_key(
          user1.id,
          user2.id,
          attrs.family_id
        )

    attrs = Map.put(attrs, :direct_key, direct_key)

    conversation = create_base_conversation(attrs)

    # Add both participants
    add_participant(conversation.id, user1.id)
    add_participant(conversation.id, user2.id)

    conversation
  end

  defp create_conversation_by_type(attrs) do
    # For other conversation types (group, etc.)
    user = user_fixture(%{family_id: attrs.family_id})

    conversation = create_base_conversation(attrs)
    add_participant(conversation.id, user.id)

    conversation
  end

  defp create_base_conversation(attrs) do
    # Extract only the needed attributes for conversation creation
    conversation_attrs =
      attrs
      |> Map.take([:family_id, :conversation_type, :metadata, :direct_key])
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    %Conversation{}
    |> Conversation.create_changeset(conversation_attrs)
    |> Repo.insert!()
  end

  defp add_participant(conversation_id, user_id) do
    %ConversationParticipant{}
    |> ConversationParticipant.changeset(%{
      conversation_id: conversation_id,
      user_id: user_id
    })
    |> Repo.insert!()
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
