defmodule Famichat.Auth.Runtime do
  @moduledoc """
  Runtime utilities shared across authentication contexts.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Auth.Tokens
    ]
end
