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

db_password =
  case {config_env(), System.get_env("POSTGRES_PASSWORD")} do
    {:prod, nil} ->
      raise "environment variable POSTGRES_PASSWORD is required in production"

    {:prod, "password"} ->
      raise "POSTGRES_PASSWORD must not be the default value \"password\" in production"

    {_, nil} ->
      "password"

    {_, value} ->
      value
  end

repo_config =
  [
    url: System.get_env("DATABASE_URL"),
    username: db_user,
    password: db_password,
    database: database,
    hostname: System.get_env("POSTGRES_HOST", "postgres"),
    port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
    pool_size: String.to_integer(System.get_env("POSTGRES_POOL", "15"))
  ]
  |> then(fn config ->
    if config_env() == :test do
      Keyword.put(config, :pool, Ecto.Adapters.SQL.Sandbox)
    else
      config
    end
  end)

config :famichat, Famichat.Repo, repo_config

if config_env() == :test do
  config :famichat, Famichat.Repo, pool: Ecto.Adapters.SQL.Sandbox
end

unique_conversation_key_salt =
  case {config_env(), System.get_env("UNIQUE_CONVERSATION_KEY_SALT")} do
    {:prod, nil} ->
      raise "environment variable UNIQUE_CONVERSATION_KEY_SALT is required in production"

    {_, nil} ->
      # Deterministic salt for dev/test only. DO NOT use in production.
      "famichat-dev-conversation-key-salt!!"

    {_, value} ->
      value
  end

config :famichat, :unique_conversation_key_salt, unique_conversation_key_salt

mls_snapshot_hmac_key_raw =
  case {config_env(), System.get_env("MLS_SNAPSHOT_HMAC_KEY")} do
    {:prod, nil} ->
      raise "environment variable MLS_SNAPSHOT_HMAC_KEY is required in production"

    {_, nil} ->
      # Deterministic 32-byte key for dev/test only. DO NOT use in production.
      "famichat-dev-snapshot-hmac-key!!"

    {_, value} ->
      value
  end

mls_snapshot_hmac_key =
  case Base.decode64(mls_snapshot_hmac_key_raw) do
    {:ok, decoded} when byte_size(decoded) >= 32 ->
      decoded

    {:ok, _short} ->
      raise "MLS_SNAPSHOT_HMAC_KEY must decode to at least 32 bytes"

    :error ->
      # Treat as raw bytes (not base64) — must be at least 32 bytes long.
      if byte_size(mls_snapshot_hmac_key_raw) >= 32 do
        mls_snapshot_hmac_key_raw
      else
        raise "MLS_SNAPSHOT_HMAC_KEY must be at least 32 bytes (or base64-encoded 32+ bytes)"
      end
  end

config :famichat, :mls_snapshot_hmac_key, mls_snapshot_hmac_key

webauthn_origin =
  case {config_env(), System.get_env("WEBAUTHN_ORIGIN")} do
    {:prod, nil} ->
      raise "environment variable WEBAUTHN_ORIGIN is required in production"

    {_, nil} ->
      # Dev/test default. DO NOT use in production.
      "http://localhost:9000"

    {_, value} ->
      value
  end

webauthn_rp_id =
  case {config_env(), System.get_env("WEBAUTHN_RP_ID")} do
    {:prod, nil} ->
      raise "environment variable WEBAUTHN_RP_ID is required in production"

    {_, nil} ->
      # Dev/test default. DO NOT use in production.
      "localhost"

    {_, value} ->
      value
  end

webauthn_rp_name = System.get_env("WEBAUTHN_RP_NAME") || "Famichat"

config :famichat, :webauthn,
  origin: webauthn_origin,
  rp_id: webauthn_rp_id,
  rp_name: webauthn_rp_name

case System.get_env("FAMICHAT_MLS_ENFORCEMENT") do
  nil ->
    :ok

  value ->
    enabled? =
      value
      |> String.trim()
      |> String.downcase()
      |> then(&(&1 in ["1", "true", "yes", "on"]))

    config :famichat, mls_enforcement: enabled?
end

vault_key_base64 =
  case {config_env(), System.get_env("FAMICHAT_VAULT_KEY")} do
    {:prod, nil} ->
      raise "environment variable FAMICHAT_VAULT_KEY is required in production"

    {_, nil} ->
      # Deterministic key for dev/test; DO NOT use in production.
      "l5sL7dYvF9h2NfGpaPUNYegF8Xfyy7b+PZjv+uN9n2A="

    {_, value} ->
      value
  end

vault_key =
  case Base.decode64(vault_key_base64) do
    {:ok, decoded} when byte_size(decoded) == 32 ->
      decoded

    {:ok, _other_size} ->
      raise "FAMICHAT_VAULT_KEY must decode to 32 bytes"

    :error ->
      raise "FAMICHAT_VAULT_KEY must be valid base64"
  end

config :famichat, Famichat.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: vault_key}
  ]
