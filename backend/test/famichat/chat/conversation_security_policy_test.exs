defmodule Famichat.Chat.ConversationSecurityPolicyTest do
  use ExUnit.Case, async: true

  alias Famichat.Chat.{ConversationSecurityPolicy, MessageService}

  test "known conversation types require encryption" do
    for type <- [:direct, :group, :family, :self] do
      assert ConversationSecurityPolicy.requires_encryption?(type)
    end
  end

  test "unknown types do not require encryption" do
    refute ConversationSecurityPolicy.requires_encryption?(:unknown)
    refute ConversationSecurityPolicy.requires_encryption?(:legacy)
  end

  test "status maps to enabled/disabled consistently" do
    for type <- [:direct, :group, :family, :self] do
      assert ConversationSecurityPolicy.status(type) == "enabled"
    end

    assert ConversationSecurityPolicy.status(:unknown) == "disabled"
  end

  test "message service wrapper delegates to canonical policy" do
    for type <- [:direct, :group, :family, :self, :unknown] do
      assert MessageService.requires_encryption?(type) ==
               ConversationSecurityPolicy.requires_encryption?(type)
    end
  end
end
