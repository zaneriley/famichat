defmodule Famichat.ChatTest do
  use Famichat.DataCase

  alias Famichat.Chat

  describe "users" do
    alias Famichat.Chat.User

    import Famichat.ChatFixtures

    @invalid_attrs %{username: nil, family_id: nil}

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Chat.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Chat.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      family = family_fixture()

      valid_attrs = %{
        username: "some username",
        family_id: family.id,
        role: :member
      }

      assert {:ok, %User{} = user} = Chat.create_user(valid_attrs)
      assert user.username == "some username"
      assert user.family_id == family.id
      assert user.role == :member
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Chat.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()
      update_attrs = %{username: "some updated username"}

      assert {:ok, %User{} = user} = Chat.update_user(user, update_attrs)
      assert user.username == "some updated username"
    end

    test "update_user/2 with invalid data returns error changeset" do
      user = user_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Chat.update_user(user, @invalid_attrs)

      assert user == Chat.get_user!(user.id)
    end

    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Chat.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Chat.get_user!(user.id) end
    end

    test "change_user/1 returns a user changeset" do
      user = user_fixture()
      assert %Ecto.Changeset{} = Chat.change_user(user)
    end
  end
end
