defmodule Famichat.Auth.Runtime do
  @moduledoc """
  Runtime utilities shared across authentication contexts.
  """

  use Boundary,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Auth.Tokens
    ]
end
