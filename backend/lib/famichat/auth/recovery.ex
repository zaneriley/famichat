defmodule Famichat.Auth.Recovery do
  @moduledoc """
  Bounded context placeholder for recovery and containment workflows.
  """

  use Boundary,
    exports: [],
    deps: [
      Famichat.Auth.Identity,
      Famichat.Auth.Households,
      Famichat.Auth.Sessions,
      Famichat.Auth.Authenticators,
      Famichat.Auth.Infra
    ]
end
