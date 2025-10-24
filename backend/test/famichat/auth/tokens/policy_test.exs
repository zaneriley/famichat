defmodule Famichat.Auth.Tokens.PolicyTest do
  use ExUnit.Case, async: true

  alias Famichat.Auth.Tokens.Policy
  alias Famichat.Auth.Tokens.Policy.Definition

  describe "policy!/1" do
    test "returns compile-time policy structs" do
      assert %Definition{
               kind: :invite,
               ttl: ttl,
               max_ttl: max,
               storage: :ledgered
             } =
               Policy.policy!(:invite)

      assert ttl > 0
      assert max >= ttl
    end

    test "raises for unknown kinds" do
      assert_raise KeyError, fn -> Policy.policy!(:unknown) end
    end
  end

  describe "default_ttl/1 + max_ttl/1" do
    test "return positive values" do
      assert Policy.default_ttl(:magic_link) > 0

      assert Policy.max_ttl(:magic_link) >=
               Policy.default_ttl(:magic_link)
    end
  end
end
