import Config

config :famichat, FamichatWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

config :logger, :console,
  format: {LogfmtEx, :format},
  metadata: :all,
  level: :info

config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: Famichat.Finch

config :famichat, Famichat.Content.FileManagement.Watcher,
  paths: ["app/priv/content"]

# You can't use mix.env in release builds, so setting this
# let's us check for the environment in the application
config :famichat, environment: :prod

config :famichat, :cache, disabled: true

config :famichat, :csp, report_only: false
