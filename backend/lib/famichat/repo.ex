defmodule Famichat.Repo do
  use Ecto.Repo,
    otp_app: :famichat,
    adapter: Ecto.Adapters.Postgres
end
