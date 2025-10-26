defmodule Famichat.Auth.Runtime.Instrumentation do
  @moduledoc """
  Null-op instrumentation scaffold for authentication contexts.
  """

  @doc """
  Placeholder span macro. Wraps the provided block without telemetry.
  """
  defmacro span(_event, _metadata, do: block) do
    quote do
      unquote(block)
    end
  end
end
