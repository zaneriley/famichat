import Config

config :famichat, environment: config_env()

url_host = System.fetch_env!("URL_HOST")

config :famichat, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

config :famichat, FamichatWeb.Endpoint,
  url: [
    scheme: System.get_env("URL_SCHEME", "https"),
    host: url_host,
    port: System.get_env("URL_PORT", "443")
  ],
  static_url: [
    host: System.get_env("URL_STATIC_HOST", url_host)
  ],
  http: [port: System.get_env("PORT", "8001")],
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
  # It is completely safe to hard code and use this salt value.
  live_view: [signing_salt: "k4yfnQW4r"]

db_user = System.get_env("POSTGRES_USER", "famichat")
database = System.get_env("POSTGRES_DB", db_user)

database =
  if config_env() == :test do
    "#{database}_test#{System.get_env("MIX_TEST_PARTITION")}"
  else
    database
  end

config :famichat, Famichat.Repo,
  url: System.get_env("DATABASE_URL"),
  username: db_user,
  password: System.get_env("POSTGRES_PASSWORD", "password"),
  database: database,
  hostname: System.get_env("POSTGRES_HOST", "postgres"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  pool_size: String.to_integer(System.get_env("POSTGRES_POOL", "15"))

config :famichat, :github_token, System.get_env("GITHUB_TOKEN")

config :famichat,
  github_webhook_secret: System.get_env("GITHUB_WEBHOOK_SECRET")

config :famichat, content_repo_url: System.get_env("CONTENT_REPO_URL")

if config_env() == :prod do
  config :famichat, content_base_path: "app/priv/content"
else
  config :famichat, content_base_path: "priv/content"
end

content_base_path = Application.get_env(:famichat, :content_base_path)

config :famichat, Famichat.Content.FileManagement.Watcher,
  paths: [System.get_env("CONTENT_BASE_PATH", "priv/content")]
