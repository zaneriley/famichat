import Config

config :famichat, environment: config_env()

# ── Batch missing-var check (production only) ──────────────────────
# Catches ALL missing required vars in one error so operators fix
# everything in a single container restart instead of twelve.
if config_env() == :prod do
  required = ~w(
    URL_HOST
    SECRET_KEY_BASE
    POSTGRES_PASSWORD
    UNIQUE_CONVERSATION_KEY_SALT
    MLS_SNAPSHOT_HMAC_KEY
    WEBAUTHN_ORIGIN
    WEBAUTHN_RP_ID
    FAMICHAT_VAULT_KEY
  )

  missing = Enum.filter(required, &is_nil(System.get_env(&1)))

  if missing != [] do
    vars = Enum.map_join(missing, "\n", &"  • #{&1}")

    raise """

    ── Missing required environment variables ─────────────────────

    #{vars}

    These must be set in your .env.production file before starting.
    See .env.production.example for documentation and generation commands.

    Quick start:
      cp .env.production.example .env.production
      # Then edit the file — each variable has a generation command in its comment.
    """
  end
end

# After the batch check, all required vars are guaranteed present in prod.
# Dev/test use inline defaults.

config :famichat, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

url_host = System.get_env("URL_HOST") || "localhost"
url_scheme = System.get_env("URL_SCHEME", "https")
url_port = System.get_env("URL_PORT", "443")

secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    "famichat-dev-only-secret-key-base-that-is-long-enough-for-64-chars-do-not-use-in-production!!"

if config_env() == :prod and byte_size(secret_key_base) < 64 do
  raise """

  ── SECRET_KEY_BASE too short ────────────────────────────────────

  Expected: at least 64 characters
  Got: #{byte_size(secret_key_base)} characters

  A short key weakens session cookie HMAC signatures.
  Generate a proper key: openssl rand -base64 64
  """
end

endpoint_config = [
  url: [
    scheme: url_scheme,
    host: url_host,
    port: url_port
  ],
  static_url: [
    host: System.get_env("URL_STATIC_HOST", url_host)
  ],
  http: [port: System.get_env("PORT", "8001")],
  secret_key_base: secret_key_base,
  # It is completely safe to hard code and use this salt value.
  live_view: [signing_salt: "k4yfnQW4r"]
]

endpoint_config =
  if config_env() == :prod do
    origin_port = if url_port in ["80", "443"], do: "", else: ":#{url_port}"
    Keyword.put(endpoint_config, :check_origin, ["#{url_scheme}://#{url_host}#{origin_port}"])
  else
    endpoint_config
  end

config :famichat, FamichatWeb.Endpoint, endpoint_config

# ── Database ───────────────────────────────────────────────────────

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
      # Unreachable after batch check, but kept as defense-in-depth.
      raise """

      ── POSTGRES_PASSWORD not set ────────────────────────────────────

      Set it in your .env.production file.
      Generate with: openssl rand -base64 32
      """

    {:prod, ""} ->
      raise """

      ── POSTGRES_PASSWORD is empty ───────────────────────────────────

      The variable is set but has no value. Provide a real password.
      Generate with: openssl rand -base64 32
      """

    {:prod, "password"} ->
      raise """

      ── POSTGRES_PASSWORD is the default value ───────────────────────

      "password" is rejected as a safeguard. Use a generated password.
      Generate with: openssl rand -base64 32
      """

    {_, nil} ->
      "password"

    {_, value} ->
      value
  end

repo_config = [
  url: System.get_env("DATABASE_URL"),
  username: db_user,
  password: db_password,
  database: database,
  hostname: System.get_env("POSTGRES_HOST", "postgres"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  pool_size: String.to_integer(System.get_env("POSTGRES_POOL", "15"))
]

config :famichat, Famichat.Repo, repo_config

if config_env() == :test do
  config :famichat, Famichat.Repo, pool: Ecto.Adapters.SQL.Sandbox
end

# ── Application secrets ────────────────────────────────────────────

unique_conversation_key_salt =
  case {config_env(), System.get_env("UNIQUE_CONVERSATION_KEY_SALT")} do
    {:prod, nil} ->
      # Unreachable after batch check.
      raise "UNIQUE_CONVERSATION_KEY_SALT is required in production"

    {_, nil} ->
      # Deterministic salt for dev/test only. DO NOT use in production.
      "famichat-dev-conversation-key-salt!!"

    {_, value} ->
      value
  end

config :famichat, :unique_conversation_key_salt, unique_conversation_key_salt

# ── MLS snapshot HMAC key ──────────────────────────────────────────

mls_snapshot_hmac_key_raw =
  case {config_env(), System.get_env("MLS_SNAPSHOT_HMAC_KEY")} do
    {:prod, nil} ->
      # Unreachable after batch check.
      raise "MLS_SNAPSHOT_HMAC_KEY is required in production"

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

    {:ok, decoded} ->
      raise """

      ── MLS_SNAPSHOT_HMAC_KEY too short ──────────────────────────────

      Decoded to #{byte_size(decoded)} bytes, need at least 32.
      Generate with: openssl rand -base64 32
      """

    :error ->
      # Not base64 — treat as raw bytes.
      if byte_size(mls_snapshot_hmac_key_raw) >= 32 do
        mls_snapshot_hmac_key_raw
      else
        raise """

        ── MLS_SNAPSHOT_HMAC_KEY invalid ──────────────────────────────────

        Not valid base64 and too short for raw bytes (#{byte_size(mls_snapshot_hmac_key_raw)} bytes, need 32+).
        Generate with: openssl rand -base64 32
        """
      end
  end

config :famichat, :mls_snapshot_hmac_key, mls_snapshot_hmac_key

# ── WebAuthn ───────────────────────────────────────────────────────

webauthn_origin =
  case {config_env(), System.get_env("WEBAUTHN_ORIGIN")} do
    {:prod, nil} ->
      # Unreachable after batch check.
      raise "WEBAUTHN_ORIGIN is required in production"

    {_, nil} ->
      # Dev/test default. DO NOT use in production.
      "http://localhost:9000"

    {_, value} ->
      value
  end

if config_env() == :prod and not String.starts_with?(webauthn_origin, "https://") do
  IO.warn("""
  ── WEBAUTHN_ORIGIN does not use https:// ────────────────────────

  Current value: #{webauthn_origin}

  Passkeys require a secure context (https://) in most browsers.
  If you're behind a reverse proxy with TLS, set WEBAUTHN_ORIGIN
  to the https:// URL your users visit.
  """)
end

webauthn_rp_id =
  case {config_env(), System.get_env("WEBAUTHN_RP_ID")} do
    {:prod, nil} ->
      # Unreachable after batch check.
      raise "WEBAUTHN_RP_ID is required in production"

    {_, nil} ->
      # Dev/test default. DO NOT use in production.
      "localhost"

    {_, value} ->
      value
  end

webauthn_rp_name =
  System.get_env("WEBAUTHN_RP_NAME") || Application.get_env(:famichat, :app_name, "Famichat")

config :famichat, :webauthn,
  origin: webauthn_origin,
  rp_id: webauthn_rp_id,
  rp_name: webauthn_rp_name

# ── MLS enforcement (optional) ─────────────────────────────────────

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

# ── Vault encryption key ───────────────────────────────────────────

vault_key_base64 =
  case {config_env(), System.get_env("FAMICHAT_VAULT_KEY")} do
    {:prod, nil} ->
      # Unreachable after batch check.
      raise "FAMICHAT_VAULT_KEY is required in production"

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

    {:ok, decoded} ->
      raise """

      ── FAMICHAT_VAULT_KEY wrong size ────────────────────────────────

      Decoded to #{byte_size(decoded)} bytes, need exactly 32.
      Generate with: openssl rand -base64 32
      """

    :error ->
      raise """

      ── FAMICHAT_VAULT_KEY is not valid base64 ───────────────────────

      The value could not be decoded. It must be a base64-encoded 32-byte key.
      Generate with: openssl rand -base64 32
      """
  end

config :famichat, Famichat.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: vault_key}
  ]
