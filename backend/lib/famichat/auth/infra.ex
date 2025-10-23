defmodule Famichat.Auth.Infra do
  @moduledoc """
  Infrastructure utilities shared across authentication contexts.
  """

  use Boundary,
    exports: :all,
    deps: [Famichat]
end
