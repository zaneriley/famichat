defmodule Famichat.Chat.FamilyTest do
  use Famichat.DataCase, async: true

  alias Famichat.Chat.Family

  describe "changeset/2" do
    test "valid with a name" do
      cs = Family.changeset(%Family{}, %{name: "The Rileys"})
      assert cs.valid?
    end

    test "requires name" do
      cs = Family.changeset(%Family{}, %{})
      refute cs.valid?
      assert %{name: ["can't be blank"]} = errors_on(cs)
    end

    test "rejects name longer than 100 characters" do
      long_name = String.duplicate("a", 101)
      cs = Family.changeset(%Family{}, %{name: long_name})
      refute cs.valid?
      assert %{name: [msg]} = errors_on(cs)
      assert msg =~ "should be at most 100 character"
    end

    test "accepts name of exactly 100 characters" do
      name = String.duplicate("a", 100)
      cs = Family.changeset(%Family{}, %{name: name})
      assert cs.valid?
    end
  end
end
