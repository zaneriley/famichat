# Quick config test to debug pool configuration
import Config

config_env = :test

url_host = "localhost"
db_user = "famichat"
database = "famichat_test"

repo_config = [
  username: db_user,
  password: "password",
  database: database,
  hostname: "localhost",
  port: 5432,
  pool_size: 15
]
|> then(fn config ->
  if config_env == :test do
    Keyword.put(config, :pool, Ecto.Adapters.SQL.Sandbox)
  else
    config
  end
end)

IO.inspect(repo_config, label: "Repo config")
