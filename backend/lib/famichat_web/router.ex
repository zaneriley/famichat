defmodule FamichatWeb.Router do
  use FamichatWeb, :router
  alias FamichatWeb.Plugs.SetLocale
  alias FamichatWeb.Plugs.LocaleRedirection
  alias FamichatWeb.Plugs.CommonMetadata
  alias FamichatWeb.Plugs.CSPHeader
  alias FamichatWeb.Plugs.SessionRefresh
  import Phoenix.LiveView.Router
  import Phoenix.LiveDashboard.Router
  import Plug.BasicAuth
  require Logger

  pipeline :locale do
    plug SetLocale
    plug LocaleRedirection
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug SessionRefresh
    plug :fetch_live_flash
    plug :put_root_layout, {FamichatWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug CSPHeader
    plug CommonMetadata
  end

  pipeline :admin do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {FamichatWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; connect-src 'self' ws: wss:; img-src 'self' data:;"
    }

    plug CommonMetadata
    # Do not include the LocaleRedirection plug here

    plug :basic_auth, Application.compile_env(:famichat, :admin_basic_auth)
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
  end

  pipeline :api_authenticated do
    plug FamichatWeb.Plugs.BearerAuth
  end

  scope "/api/v1", FamichatWeb do
    pipe_through :api

    get "/hello", HelloController, :index
    get "/health", HealthController, :index
    post "/setup", AuthController, :bootstrap_admin
    post "/auth/invites", AuthController, :issue_invite
    post "/auth/invites/accept", AuthController, :accept_invite
    post "/auth/invites/complete", AuthController, :complete_invite
    post "/auth/pairings", AuthController, :reissue_pairing
    post "/auth/pairings/redeem", AuthController, :redeem_pairing

    post "/auth/passkeys/register/challenge",
         AuthController,
         :passkey_register_challenge

    post "/auth/passkeys/register", AuthController, :passkey_register

    post "/auth/passkeys/assert/challenge",
         AuthController,
         :passkey_assert_challenge

    post "/auth/passkeys/assert", AuthController, :passkey_assert
    post "/auth/sessions/refresh", AuthController, :refresh_session
    delete "/auth/devices/:device_id", AuthController, :revoke_device
    post "/auth/magic_link", AuthController, :issue_magic_link
    post "/auth/magic_link/redeem", AuthController, :redeem_magic_link
    post "/auth/otp/request", AuthController, :issue_otp
    post "/auth/otp/verify", AuthController, :verify_otp
    post "/auth/recovery", AuthController, :issue_recovery
    post "/auth/recovery/redeem", AuthController, :redeem_recovery
  end

  scope "/api/v1", FamichatWeb do
    pipe_through [:api, :api_authenticated]

    get "/me", UserController, :me
  end

  scope "/api/v1", FamichatWeb.API do
    pipe_through [:api, :api_authenticated]

    get "/me/conversations", ChatReadController, :index_me_conversations
    post "/conversations", ConversationController, :create
    get "/conversations/:id/messages", ChatReadController, :index_messages
    post "/conversations/:id/messages", ChatWriteController, :create_message

    post "/conversations/:id/security/recover",
         ChatWriteController,
         :recover_security_state
  end

  # Enables LiveDashboard only for development.
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # Conditional block for development-only routes
  # We're defining these first as to not trigger the :locale redirection pipeline.
  if Application.compile_env(:famichat, :environment) in [:dev, :test] do
    scope "/api/test", FamichatWeb do
      pipe_through [:api, :api_authenticated]

      post "/broadcast", MessageTestController, :broadcast
      post "/test_events", MessageTestController, :broadcast_alias

      post "/conversation_security/recover",
           MessageTestController,
           :recover_conversation_security_state

      post "/conversation_security/reset_state",
           MessageTestController,
           :reset_conversation_security_state
    end

    scope "/admin", FamichatWeb do
      pipe_through [:admin]

      live_session :admin, on_mount: {FamichatWeb.LiveHelpers, :admin} do
        live "/spike", SpikeStartLive, :index
        # Canonical message QA route
        live "/message", MessageTestLive, :index
        # Compatibility alias retained for existing links/scripts
        live "/message-test", MessageTestLive, :index
      end

      # Keep non-LiveView routes outside the live_session
      live_dashboard "/dashboard", metrics: FamichatWeb.Telemetry
    end

  end

  scope "/", FamichatWeb do
    pipe_through :browser
    get "/", RootRedirectController, :index
    get "/up", UpController, :index
    get "/up/databases", UpController, :databases
  end

  pipeline :validate_invite do
    plug FamichatWeb.Plugs.ValidateInviteToken
  end

  # Invite route — validated at HTTP layer before LiveView mounts.
  scope "/:locale", FamichatWeb do
    pipe_through [:browser, :locale, :validate_invite]

    live_session :invite_session, on_mount: FamichatWeb.LiveHelpers do
      live "/invites/:token", AuthLive.InviteLive, :index
    end
  end

  # First-run admin setup — no auth required, locale-prefixed.
  # The LiveView itself gates on "admin already exists" and redirects away.
  scope "/:locale", FamichatWeb do
    pipe_through [:browser, :locale]

    live_session :admin_setup, on_mount: {FamichatWeb.LiveHelpers, :default} do
      live "/setup", AdminLive.SetupLive, :index
    end
  end

  # All other locale-scoped routes.
  scope "/:locale", FamichatWeb do
    pipe_through [:browser, :locale]

    live_session :default, on_mount: FamichatWeb.LiveHelpers do
      live "/", HomeLive, :index
      live "/login", AuthLive.LoginLive, :index
    end

    # Redirect any unknown locale-scoped GET path to login rather than showing
    # the debug page (dev) or a 500 (prod). Only GET is handled because
    # POST/PUT/DELETE to unknown paths are not reachable via browser navigation.
    get "/*path", LocaleCatchAllController, :redirect_to_login
  end

  # API catch-all must be last so it does not shadow any /api/v1 routes defined
  # above. Phoenix matches routes in declaration order.
  scope "/api", FamichatWeb do
    pipe_through :api
    match :*, "/*path", FallbackController, :not_found
  end
end
