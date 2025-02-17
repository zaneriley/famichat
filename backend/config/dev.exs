import Config

config :famichat, FamichatWeb.Endpoint,
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [],
  live_reload: [
    web_console_logger: false,
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/famichat_web/(controllers|live|components)/.*(ex|heex)$",
      ~r"#{String.trim_trailing("priv/content", "/")}/.+\.md$"
    ]
  ],
  token_salt: System.get_env("DEV_TOKEN_SALT")

# Updating dev
# You can't use mix.env in release builds, so setting this
# let's us check for the environment in the application
config :famichat, environment: :dev

config :famichat, dev_routes: true

config :famichat, Famichat.Repo, show_sensitive_data_on_connection_error: true

config :famichat, :csp, report_only: true

config :famichat, :cache,
  ttl: :timer.seconds(5),
  limit: 100,
  policy: Cachex.Policy.LRU

# Optionally, to disable caching in development:
config :famichat, :cache, disabled: true

config :logger, :console,
  format: {Famichat.LoggerFormatter, :format},
  metadata: [
    :request_id,
    :user_id,
    :duration,
    :module,
    :function,
    :line,
    :changeset
  ],
  level: :debug,
  colors: [enabled: true]

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :famichat, Famichat.Content.FileManagement.Watcher,
  paths: ["priv/content"]

# Include HEEx debug annotations as HTML comments in rendered markup.
config :phoenix_live_view, :debug_heex_annotations, true
