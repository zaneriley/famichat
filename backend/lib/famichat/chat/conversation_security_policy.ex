defmodule Famichat.Chat.ConversationSecurityPolicy do
  @moduledoc """
  Canonical conversation-type encryption policy.

  This module owns whether a given conversation type requires encryption and
  exposes a stable status string used by telemetry surfaces.
  """

  @type conversation_type :: :direct | :group | :family | :self

  @spec requires_encryption?(atom()) :: boolean()
  def requires_encryption?(:direct), do: true
  def requires_encryption?(:group), do: true
  def requires_encryption?(:family), do: true
  def requires_encryption?(:self), do: true
  def requires_encryption?(_), do: false

  @spec status(atom()) :: String.t()
  def status(conversation_type) do
    if requires_encryption?(conversation_type) do
      "enabled"
    else
      "disabled"
    end
  end
end
