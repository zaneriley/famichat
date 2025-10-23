defmodule Famichat.Auth.Households do
  @moduledoc """
  Bounded context placeholder for household membership and roles.
  """

  use Boundary,
    exports: [],
    deps: [Famichat.Auth.Infra]
end
