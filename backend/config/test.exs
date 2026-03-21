import Config

config :famichat, FamichatWeb.Endpoint,
  token_salt: System.get_env("DEV_TOKEN_SALT"),
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

config :famichat, Famichat.Auth.Tokens.Storage,
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

config :famichat, Famichat.Repo, pool: Ecto.Adapters.SQL.Sandbox

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :changeset,
    :topic,
    :reason,
    :conversation_id,
    :revocation_ref,
    :error_code,
    :details,
    :device_id,
    :timeout_ms,
    :summary,
    :conversation_count,
    :error,
    :invite_error,
    :code
  ],
  level: :warning

config :famichat, Famichat.Mailer, adapter: Swoosh.Adapters.Test

# You can't use mix.env in release builds, so setting this
# let's us check for the environment in the application
config :famichat, environment: :test

config :famichat,
  content_base_path: "test/support/fixtures"

config :famichat, :admin_basic_auth,
  username: "test-admin",
  password: "test-secret"

# MLS enforcement off by default in tests. Tests that exercise MLS paths
# opt in via Application.put_env(:famichat, :mls_enforcement, true) + on_exit cleanup.
config :famichat, mls_enforcement: false
