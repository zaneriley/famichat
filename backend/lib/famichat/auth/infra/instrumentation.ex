defmodule Famichat.Auth.Infra.Instrumentation do
  @moduledoc "Deprecated alias; use `Famichat.Auth.Runtime.Instrumentation`."

  @deprecated "use Famichat.Auth.Runtime.Instrumentation.span/3"
  defmacro span(event, metadata, do: block) do
    quote do
      Famichat.Auth.Runtime.Instrumentation.span unquote(event),
                                                 unquote(metadata) do
        unquote(block)
      end
    end
  end
end
