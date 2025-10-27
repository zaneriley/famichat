defmodule FamichatWeb.Router do
  use FamichatWeb, :router
  alias FamichatWeb.Plugs.SetLocale
  alias FamichatWeb.Plugs.LocaleRedirection
  alias FamichatWeb.Plugs.CommonMetadata
  alias FamichatWeb.Plugs.CSPHeader
  import Phoenix.LiveView.Router
  import Phoenix.LiveDashboard.Router
  require Logger

  pipeline :locale do
    plug SetLocale
    plug LocaleRedirection
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
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
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_authenticated do
    plug FamichatWeb.Plugs.BearerAuth
  end

  scope "/api/v1", FamichatWeb do
    pipe_through :api

    get "/hello", HelloController, :index
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

  scope "/api/v1", FamichatWeb.API do
    pipe_through [:api, :api_authenticated]

    get "/me/conversations", ChatReadController, :index_me_conversations
    get "/conversations/:id/messages", ChatReadController, :index_messages
  end

  # Enables LiveDashboard only for development.
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # Conditional block for development-only routes
  # We're defining these first as to not trigger the :locale redirection pipeline.
  if Application.compile_env(:famichat, :environment) in [:dev, :test] do
    scope "/admin", FamichatWeb do
      pipe_through [:admin]

      live_session :admin, on_mount: {FamichatWeb.LiveHelpers, :admin} do
        # Add the new message testing route
        live "/message-test", MessageTestLive, :index
      end

      # Keep non-LiveView routes outside the live_session
      live_dashboard "/dashboard", metrics: FamichatWeb.Telemetry
    end
  end

  scope "/", FamichatWeb do
    pipe_through :browser
    get "/up", UpController, :index
    get "/up/databases", UpController, :databases
  end

  scope "/", FamichatWeb do
    pipe_through [:browser, :locale]

    # Temporarily point root to HelloController
    get "/", HelloController, :index
    # And locale route as well
    get "/:locale", HelloController, :index
  end

  scope "/:locale", FamichatWeb do
    pipe_through [:browser, :locale]

    live_session :default, on_mount: FamichatWeb.LiveHelpers do
      live "/", HomeLive, :index
    end
  end

  # Other scopes may use custom stacks.
  scope "/api", FamichatWeb do
    pipe_through :api

    scope "/test" do
      post "/broadcast", MessageTestController, :broadcast
      # Add new CLI test endpoint for testing channel events
      post "/test_events", TestBroadcastController, :trigger
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:new, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FamichatWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
