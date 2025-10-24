defmodule Famichat.Auth.TokensTest do
  use Famichat.DataCase, async: true

  alias Famichat.Accounts.User
  alias Famichat.Auth.Tokens
  alias Famichat.Auth.Tokens.Issue
  alias Famichat.Repo

  describe "issue/3 for ledgered kinds" do
    test "applies default ttl and populates ledger metadata" do
      payload = %{"family_id" => Ecto.UUID.generate(), "role" => "member"}

      assert {:ok, %Issue{} = issued} = Tokens.issue(:invite, payload)
      assert issued.class == :ledgered
      assert issued.record.context == "invite"
      assert issued.record.kind == "invite"
      assert issued.record.audience == "invitee"
      assert is_binary(issued.raw)
      assert issued.record.subject_id == nil

      diff = DateTime.diff(issued.expires_at, issued.issued_at)
      assert_in_delta diff, Tokens.default_ttl(:invite), 2
    end

    test "allows overriding ttl" do
      payload = %{"family_id" => Ecto.UUID.generate(), "role" => "member"}

      assert {:ok, %Issue{} = issued} = Tokens.issue(:invite, payload, ttl: 120)

      diff = DateTime.diff(issued.expires_at, issued.issued_at)
      assert_in_delta diff, 120, 2
    end
  end

  describe "issue/3 for signed kinds" do
    test "returns signed Phoenix tokens" do
      payload = %{"invite_token_id" => Ecto.UUID.generate()}

      assert {:ok, %Issue{} = issued} =
               Tokens.issue(:invite_registration, payload)

      assert issued.class == :signed
      assert issued.audience == :invitee

      assert {:ok, ^payload} =
               Tokens.verify(:invite_registration, issued.raw)
    end
  end

  describe "issue/3 for OTP" do
    test "requires a context override" do
      user = insert_user(%{})
      email = "otp-test@example.com"
      normalized = String.downcase(email)

      fingerprint =
        :crypto.hash(:sha256, normalized)
        |> Base.encode16(case: :lower)

      payload = %{
        "user_id" => user.id,
        "code" => "123456",
        "email_fingerprint" => fingerprint
      }

      assert_raise ArgumentError, fn ->
        Tokens.issue(:otp, payload)
      end

      assert {:ok, %Issue{} = issued} =
               Tokens.issue(:otp, payload,
                 context: "otp:" <> fingerprint,
                 ttl: 30
               )

      assert issued.record.context == "otp:" <> fingerprint
      assert issued.record.kind == "otp"
      assert issued.record.subject_id == fingerprint
      assert issued.record.audience == "user"
      diff = DateTime.diff(issued.expires_at, issued.issued_at)
      assert_in_delta diff, 30, 2
    end
  end

  describe "fetch/3" do
    test "delegates to the underlying token helpers" do
      user = insert_user(%{username: "alice"})
      payload = %{"user_id" => user.id}

      {:ok, %Issue{raw: raw, record: record}} =
        Tokens.issue(:magic_link, payload, context: "magic_link")

      assert {:ok, fetched} = Tokens.fetch(:magic_link, raw)
      assert fetched.id == record.id
      assert fetched.kind == "magic_link"
      assert fetched.audience == "user"
      assert fetched.subject_id == user.id
    end
  end

  defp insert_user(attrs) do
    defaults = %{username: "user-" <> Ecto.UUID.generate()}

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
