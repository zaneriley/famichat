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
    same_site: "Lax",
    secure: true
  ]

  socket "/socket", FamichatWeb.UserSocket,
    websocket: [
      serializer: [
        {Phoenix.Socket.V1.JSONSerializer, "~> 1.0.0"},
        {FamichatWeb.Socket.SafeV2JSONSerializer, "~> 2.0.0"}
      ]
    ],
    longpoll: false

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :famichat,
    gzip: true,
    only: FamichatWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :famichat

    plug Phoenix.LiveDashboard.RequestLogger,
      param_key: "request_logger",
      cookie_key: "request_logger"
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  plug :strip_server_header

  plug FamichatWeb.Router

  defp strip_server_header(conn, _opts) do
    register_before_send(conn, fn conn ->
      delete_resp_header(conn, "server")
    end)
  end

  defp log_request(conn, _opts) do
    Logger.debug(fn ->
      "Request received in Endpoint: #{inspect(conn.method)} #{inspect(conn.request_path)}"
    end)

    conn
  end
end
