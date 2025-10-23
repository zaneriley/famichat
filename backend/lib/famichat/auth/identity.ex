defmodule Famichat.Auth.Identity do
  @moduledoc """
  Bounded context placeholder for user identity concerns.
  """

  use Boundary,
    exports: [],
    deps: [Famichat.Auth.Infra]
end
