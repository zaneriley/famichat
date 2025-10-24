defmodule Famichat.Auth.Tokens.StorageTest do
  use ExUnit.Case, async: true

  alias Famichat.Auth.Tokens.Storage

  describe "issue_device_secret/1" do
    test "returns raw value and matching hash" do
      assert {:ok, raw, hash} = Storage.issue_device_secret()
      assert byte_size(raw) > 0
      assert hash == Storage.hash(raw)
    end
  end

  describe "generate_refresh/0" do
    test "delegates to issue_device_secret/1" do
      assert {:ok, raw, hash} = Storage.generate_refresh()
      assert byte_size(raw) > 0
      assert hash == Storage.hash(raw)
    end
  end

  describe "sign/3 and verify/3" do
    test "round-trips payloads with the supplied salt" do
      payload = %{"user_id" => Ecto.UUID.generate()}
      salt = "test-salt"

      token = Storage.sign(payload, salt)

      assert {:ok, ^payload} = Storage.verify(token, salt)
    end
  end
end
