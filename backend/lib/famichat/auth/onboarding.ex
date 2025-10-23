defmodule Famichat.Auth.Onboarding do
  @moduledoc """
  Bounded context placeholder for invite and registration orchestration.
  """

  use Boundary,
    exports: [],
    deps: [
      Famichat.Auth.Identity,
      Famichat.Auth.Households,
      Famichat.Auth.Infra
    ]
end
