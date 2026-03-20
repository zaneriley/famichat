defmodule Famichat do
  @moduledoc """
  Root boundary for core application contexts.
  """

  use Boundary,
    deps: [],
    exports: [
      Cache,
      Ecto.Pagination,
      Mailer,
      Repo,
      Schema.Validations,
      TelemetryHandler,
      Vault
    ]
end
