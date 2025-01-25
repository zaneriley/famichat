defmodule FamichatWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :famichat

  require Logger

  plug :log_request

  @session_options [
    store: :cookie,
    key: "_famichat_key",
    # It is completely safe to hard code and use these salt values.
    signing_salt: "XCu9aYUeZ",
    encryption_salt: "jIOxYIG2l",
    same_site: "Lax"
  ]

  plug GitHubWebhook,
    secret: "V/cR1ORkr+Fi5FHCzmzoEtgud7Tjdg/7ZS+DTOdzX2qm+LEwve3XkKwqoXAfTvCH",
    path: "/api/v1/content/push",
    action: {FamichatWeb.ContentWebhookController, :handle_webhook}

  socket "/socket", FamichatWeb.UserSocket,
    websocket: true,
    longpoll: false

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :famichat,
    gzip: false,
    only: FamichatWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :famichat
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  plug CORSPlug,
    origin: ["http://localhost:3000", "http://127.0.0.1:3000"],
    methods: ["GET", "POST"]

  plug FamichatWeb.Router

  defp log_request(conn, _opts) do
    Logger.warning(
      "Request received in Endpoint: #{inspect(conn.method)} #{inspect(conn.request_path)}"
    )

    conn
  end

  def get_github_webhook_secret do
    Application.get_env(:famichat, :github_webhook_secret) ||
      raise "GitHub webhook secret is not configured!"
  end
end
