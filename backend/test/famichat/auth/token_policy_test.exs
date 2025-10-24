defmodule Famichat.Auth.TokenPolicyTest do
  use ExUnit.Case, async: true

  alias Famichat.Auth.TokenPolicy
  alias Famichat.Auth.TokenPolicy.Policy

  describe "policy!/1" do
    test "returns compile-time policy structs" do
      assert %Policy{kind: :invite, ttl: ttl, max_ttl: max, storage: :ledgered} =
               TokenPolicy.policy!(:invite)

      assert ttl > 0
      assert max >= ttl
    end

    test "raises for unknown kinds" do
      assert_raise KeyError, fn -> TokenPolicy.policy!(:unknown) end
    end
  end

  describe "default_ttl/1 + max_ttl/1" do
    test "return positive values" do
      assert TokenPolicy.default_ttl(:magic_link) > 0

      assert TokenPolicy.max_ttl(:magic_link) >=
               TokenPolicy.default_ttl(:magic_link)
    end
  end
end
