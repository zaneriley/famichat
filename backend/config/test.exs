import Config

config :famichat, FamichatWeb.Endpoint,
  token_salt: System.get_env("DEV_TOKEN_SALT"),
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

config :famichat, Famichat.Repo, pool: Ecto.Adapters.SQL.Sandbox

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :changeset],
  level: :warning

config :famichat, Famichat.Mailer, adapter: Swoosh.Adapters.Test

# You can't use mix.env in release builds, so setting this
# let's us check for the environment in the application
config :famichat, environment: :test

config :famichat,
  content_base_path: "test/support/fixtures"

config :famichat, Famichat.Content.FileSystemWatcher,
  paths: [
    Application.get_env(:famichat, :content_base_path)
  ]
