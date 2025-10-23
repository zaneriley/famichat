defmodule Famichat.Accounts do
  @moduledoc """
  Thin façade delegating to the legacy accounts implementation.

  Phase 0 keeps behavior identical by forwarding all calls to
  `Famichat.Accounts.Legacy`.
  """

  alias Famichat.Accounts.Legacy

  for {name, arity} <- Legacy.__info__(:functions) do
    args = Macro.generate_arguments(arity, __MODULE__)
    defdelegate unquote(name)(unquote_splicing(args)), to: Legacy
  end
end
