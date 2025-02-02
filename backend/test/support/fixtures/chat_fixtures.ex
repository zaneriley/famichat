defmodule Famichat.ChatFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Famichat.Chat` context.
  """

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
end
