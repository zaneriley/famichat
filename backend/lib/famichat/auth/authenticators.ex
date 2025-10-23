defmodule Famichat.Auth.Authenticators do
  @moduledoc """
  Bounded context placeholder for authenticator management (passkeys, etc.).
  """

  use Boundary,
    exports: [],
    deps: [
      Famichat.Auth.Identity,
      Famichat.Auth.Infra
    ]
end
