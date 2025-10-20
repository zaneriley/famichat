defmodule Famichat.Accounts.UsernameTest do
  use Famichat.DataCase, async: true

  alias Famichat.Accounts.Username

  describe "sanitize/1" do
    test "trims whitespace" do
      assert Username.sanitize("  Alice  ") == "Alice"
    end

    test "returns nil for blank strings" do
      assert Username.sanitize("   ") == nil
    end
  end

  describe "fingerprint/1" do
    test "is case insensitive" do
      assert Username.fingerprint("Alice") == Username.fingerprint("alice")
    end

    test "returns nil for blank input" do
      assert Username.fingerprint("   ") == nil
    end
  end

  describe "maybe_suffix/2" do
    test "keeps original username when unique" do
      {candidate, fingerprint, assigned, changed?} =
        Username.maybe_suffix("Alice", MapSet.new())

      assert candidate == "Alice"
      refute changed?
      assert MapSet.member?(assigned, fingerprint)
    end

    test "appends suffix when collision occurs" do
      {_, fingerprint, assigned, _} =
        Username.maybe_suffix("Alice", MapSet.new())

      {candidate, new_fingerprint, _, changed?} =
        Username.maybe_suffix("alice", assigned)

      assert candidate == "alice_2"
      assert changed?
      refute fingerprint == new_fingerprint
    end
  end
end
