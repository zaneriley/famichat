defmodule Famichat.Auth.TokensTest do
  use Famichat.DataCase, async: true

  alias Famichat.Accounts.User
  alias Famichat.Auth.Tokens
  alias Famichat.Repo

  describe "issue/3 for ledgered kinds" do
    test "applies default ttl and context" do
      payload = %{"family_id" => Ecto.UUID.generate(), "role" => "member"}

      assert {:ok, raw, record} = Tokens.issue(:invite, payload)
      assert is_binary(raw)
      assert record.context == "invite"

      diff = DateTime.diff(record.expires_at, record.inserted_at)
      assert_in_delta diff, 7 * 24 * 60 * 60, 2
    end

    test "allows overriding ttl" do
      payload = %{"family_id" => Ecto.UUID.generate(), "role" => "member"}

      assert {:ok, _raw, record} = Tokens.issue(:invite, payload, ttl: 120)
      diff = DateTime.diff(record.expires_at, record.inserted_at)
      assert_in_delta diff, 120, 2
    end
  end

  describe "issue/3 for signed kinds" do
    test "returns signed Phoenix tokens" do
      payload = %{"invite_token_id" => Ecto.UUID.generate()}

      assert {:ok, token} = Tokens.issue(:invite_registration, payload)
      assert {:ok, ^payload} = Tokens.verify(:invite_registration, token)
    end
  end

  describe "issue/3 for OTP" do
    test "requires a context override" do
      payload = %{"user_id" => Ecto.UUID.generate(), "code" => "123456"}

      assert_raise ArgumentError, fn ->
        Tokens.issue(:otp, payload)
      end

      assert {:ok, _raw, record} =
               Tokens.issue(:otp, payload, context: "otp:test", ttl: 30)

      assert record.context == "otp:test"
    end
  end

  describe "fetch/3" do
    test "delegates to the underlying token helpers" do
      user = insert_user(%{username: "alice"})
      payload = %{"user_id" => user.id}

      {:ok, raw, issued} =
        Tokens.issue(:magic_link, payload, user_id: user.id)

      assert {:ok, fetched} = Tokens.fetch(:magic_link, raw)
      assert fetched.id == issued.id
    end
  end

  defp insert_user(attrs) do
    defaults = %{username: "user-" <> Ecto.UUID.generate()}

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
