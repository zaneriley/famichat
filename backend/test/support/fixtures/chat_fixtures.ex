defmodule Famichat.ChatFixtures do
  @moduledoc """
  Test fixtures for Chat context entities
  """
  alias Famichat.Chat.{Conversation, ConversationParticipant}
  alias Famichat.Repo

  @doc """
  Generate a unique user username.
  """
  def unique_user_username,
    do: "some username#{System.unique_integer([:positive])}"

  @doc """
  Generate a unique family name.
  """
  def unique_family_name,
    do: "Family #{System.unique_integer([:positive])}"

  @doc """
  Generate a family.
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
  Generate a user.
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
  Generate a conversation.
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
  Returns a current UTC DateTime with microsecond precision,
  offset by the given number of seconds.
  """
  def truncated_timestamp(offset_seconds \\ 0)
      when is_integer(offset_seconds) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(offset_seconds, :second)
    |> NaiveDateTime.truncate(:microsecond)
    |> DateTime.from_naive!("Etc/UTC")
  end
end
