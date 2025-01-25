# /srv/famichat/flutter/famichat/pubspec.yaml

```yaml
name: famichat
description: A minimal Flutter project to test connectivity with the Famichat Phoenix backend.
publish_to: "none"

environment:
  sdk: ">=2.17.0 <3.0.0"

dependencies:
  flutter:
    sdk: flutter
  http: ^0.13.5

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
  assets:
    - "config/app_settings.json"```

# /srv/famichat/project.md

```md
# Famichat Hello World - Project Plan

## Purpose
- Validate Docker-based Phoenix + Postgres.
- Confirm minimal SwiftUI iOS client can fetch data from the backend.
- Provide a foundation for future customizations and white-label features.

## Next Steps
1. Expand Ecto schemas for storing messages, user accounts.
2. Add theming endpoints to serve design tokens.
3. Implement actual mobile UI for messaging.

## Definition of Done
- `docker-compose up` shows a Phoenix "Hello World" message in a browser.
- The iOS app fetches and displays that message in a Text view.


---

About the Project:
This project is a self-hosted, white-label video and chat application designed specifically for families. It provides a secure and private digital space for families to stay connected through asynchronous messaging, occasional video calls, and unique "cozy" features inspired by games like Animal Crossing. The platform is highly customizable, allowing each family to tailor the experience, from branding to features, creating a truly personalized communication hub. It's built for families who value privacy, control over their data, and a more intimate, intentional way to connect with loved ones. It was originally built to meet a single family's needs for bilingiual, secure communication across continents, with a way to share photos, updates, and milestones. It is being made white-label so that others can use for their own families.

Core Functionality & Features:

    Asynchronous Communication: The primary mode of communication will be asynchronous, similar to text/group messages, with an emphasis on "slow" features like leaving "letters."
    Real-time Communication: Live video calls are a secondary need, accounting for approximately 15% of usage.
    "Cozy" Connection: Exploration of features inspired by games like Animal Crossing that foster a sense of ambient connection and shared experience, focusing on asynchronous interactions.
    Native iOS App: The primary platform will be a dedicated iOS app.
    Web Client: A secondary web client will provide accessibility from computers.
    Searchable Content: Robust search functionality to easily find past conversations, media, and other shared content is essential.
    Notifications: Standard iOS notification system will be used to alert users to new messages.
    Customizable Features: The ability to create bespoke features tailored to your family's needs (e.g., Japanese/English language support, Missouri/Tokyo weather, etc.) is a key advantage. The platform should support a high degree of customization for other families.

User Experience & Design:

    Family-Centric Design: The UX should be specifically designed with families in mind, incorporating features related to holidays, birthdays, kids' photos/galleries, addresses, etc.
    Aesthetic: You, as a designer, will handle the visual design for your family's instance. The platform should allow for easy aesthetic customization by other families.
    User Roles: The app will serve your nuclear family (wife, you, child) as well as extended family (parents, siblings, nieces). The platform should support different user roles and permissions.

Technical Considerations:

    Security: Top priority. End-to-end encryption, passcodes, and other robust security measures are non-negotiable. Security architecture must be adaptable to different family's instances.
    Reliability: While you acknowledge concerns about speed and reliability, the app needs to be stable and performant across all family instances.
    Maintenance: You will need to allocate time for ongoing development and maintenance. Consider the maintenance needs of other families using the platform.
    Self-Hosted: The app will be self-hosted, giving you full control over data and features. The platform should be easy for others to self-host.
    Scalability: The platform's architecture needs to be designed for easy deployment and scaling for multiple families.
    Containerization: To be considered for easier deployment.

Cultural & Family-Specific Needs:

    Bilingual Support: Japanese and English language options are needed for your family. The platform should allow for easy addition of new languages.
    Location-Specific Information: Missouri and Tokyo weather and potentially other location-based data is needed for your family.
    Family Traditions: Consider how to incorporate features that support or reflect your family's unique traditions and cultural background. The platform should be adaptable to other families' traditions.
    Privacy: Given the sensitive nature of family information, privacy must be carefully considered in all design and development decisions.

White-Label/Turnkey Considerations:

    Customization:
        Branding: Easy customization of the app's appearance (logos, colors, etc.).
        Features: A system for enabling/disabling features.
        Language: Easy addition of new language options.```

# /srv/famichat/flutter/famichat/config/app_settings.json

```json
{
  "appTitle": "Famichat",
  "apiUrl": "http://127.0.0.1:8001/api/v1/hello" 
} ```

# /srv/famichat/flutter/famichat/lib/main.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(const FamichatApp());
}

class FamichatApp extends StatefulWidget {
  const FamichatApp({super.key});

  @override
  State<FamichatApp> createState() => _FamichatAppState();
}

class _FamichatAppState extends State<FamichatApp> {
  String appTitle = 'Loading...';
  String apiUrl = 'http://127.0.0.1:4000/api/placeholder';

  @override
  void initState() {
    super.initState();
    _printAssetManifest();
    _loadConfig();
  }

  Future<void> _printAssetManifest() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      print('AssetManifest.json contents:\n$manifestContent');
    } catch (e) {
      print('Error loading AssetManifest.json: $e');
    }
  }

  Future<void> _loadConfig() async {
    final jsonString = await rootBundle.loadString('config/app_settings.json');
    final config = json.decode(jsonString);

    setState(() {
      appTitle = config['appTitle'] as String? ?? 'Famichat';
      apiUrl = config['apiUrl'] as String? ?? 'http://127.0.0.1:8001/api/v1/hello';
      print('API URL loaded from config: $apiUrl');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HelloScreen(apiUrl: apiUrl, title: appTitle),
    );
  }
}

class HelloScreen extends StatefulWidget {
  final String apiUrl;
  final String title;

  const HelloScreen({super.key, required this.apiUrl, required this.title});

  @override
  State<HelloScreen> createState() => _HelloScreenState();
}

class _HelloScreenState extends State<HelloScreen> {
  String message = 'Loading...';

  @override
  void initState() {
    super.initState();
    fetchGreeting();
  }

  Future<void> fetchGreeting() async {
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8001/api/v1/hello'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        setState(() {
          message = jsonResponse['message'] ?? 'No message received';
        });
      } else {
        setState(() {
          message = 'Error: ${response.statusCode}';
        });
      }
    } catch (e, stackTrace) {
      print('Network error: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        message = 'Network error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchGreeting,
          ),
        ],
      ),
      body: Center(
        child: Text(
          message,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
} ```

# /srv/famichat/config/design-tokens/base/spacing.json

```json
{
  "$schema": "https://json.schemastore.org/json",
  "comment": "Base spacing tokens e.g., grid widths, base spacing steps.",
  "spacing": {
    "gridMaxWidth": "1440px",
    "gridGutter": "3rem",
    "gridOuterMargins": "0.5rem",

    "spaceSizes": {
      "3xs": "var(--space-3xs)",
      "2xs": "var(--space-2xs)",
      "1xs": "var(--space-1xs)",
      "md": "var(--space-md)",
      "1xl": "var(--space-1xl)",
      "2xl": "var(--space-2xl)",
      "3xl": "var(--space-3xl)",
      "4xl": "var(--space-4xl)"
    }
  }
} ```

# /srv/famichat/config/design-tokens/base/typography.json

```json
{
  "$schema": "https://json.schemastore.org/json",
  "comment": "Base typography tokens for sizes and line-height references.",
  "typography": {
    "baseSize": "clamp(1.13rem, 0vi + 1.13rem, 1.13rem)",

    "fontSizes": {
      "2xs": "var(--fs-2xs)",
      "1xs": "var(--fs-1xs)",
      "md": "var(--fs-md)",
      "1xl": "var(--fs-1xl)",
      "2xl": "var(--fs-2xl)",
      "3xl": "var(--fs-3xl)",
      "4xl": "var(--fs-4xl)"
    },

    "lineHeight": {
      "normal": "1.5",
      "cjk": "calc(1em + 1rem)"
    }
  }
} ```

# /srv/famichat/config/design-tokens/base/colors.json

```json
{
  "$schema": "https://json.schemastore.org/json",
  "comment": "Base color tokens, including brand-agnostic primitives and base palette reference.",
  "colors": {
    "whiteAbsolute": "oklch(100% 0 0deg)",
    "blackAbsolute": "oklch(0% 0 0deg)",
    "whitePoint": "oklch(90.76% 0.0184 316.61deg)",
    "blackPoint": "oklch(11.47% 0 0deg)",

    "dusk": {
      "0": "{colors.whitePoint}",
      "100": "oklch(88.73% 0.056 324.15deg)",
      "200": "oklch(85.53% 0.072 314.14deg)",
      "300": "oklch(81.03% 0.086 303.13deg)",
      "400": "oklch(76.32% 0.1 291.05deg)",
      "500": "oklch(68.67% 0.095 276.77deg)",
      "600": "oklch(56.6% 0.07 263.77deg)",
      "700": "oklch(41.84% 0.038 261.51deg)",
      "800": "oklch(33.09% 0.022 259.38deg)",
      "900": "oklch(28.04% 0.012 264.36deg)",
      "1000": "oklch(25.26% 0.008 274.64deg)"
    },

    "neutral": {
      "0": "{colors.whitePoint}",
      "100": "oklch(78.23% 0.036 333.34deg)",
      "200": "#bd9ca6",
      "300": "oklch(77.77% 0.0704 75.85deg)"
    },

    "ochre": {
      "0": "oklch(77.77% 0.0704 75.85deg)"
    }
  }
} ```

# /srv/famichat/config/design-tokens/themes/animal-crossing/spacing.json

```json
{
  "$schema": "https://json.schemastore.org/json",
  "comment": "Animal Crossing inspired spacing with generous, friendly proportions",
  "spacing": {
    "gridMaxWidth": "1280px",
    "gridGutter": "2rem",
    "gridOuterMargins": "1rem",

    "spaceSizes": {
      "3xs": "0.25rem",
      "2xs": "0.5rem",
      "1xs": "0.75rem",
      "md": "1.25rem",
      "1xl": "2rem",
      "2xl": "3rem",
      "3xl": "4rem",
      "4xl": "6rem"
    },

    "borderRadius": {
      "small": "0.75rem",
      "medium": "1.25rem",
      "large": "2rem",
      "pill": "9999px"
    },

    "shadows": {
      "small": "0 2px 4px oklch(0% 0 0deg / 0.1)",
      "medium": "0 4px 8px oklch(0% 0 0deg / 0.12)",
      "large": "0 8px 16px oklch(0% 0 0deg / 0.15)"
    }
  }
} ```

# /srv/famichat/config/design-tokens/themes/animal-crossing/typography.json

```json
{
  "$schema": "https://json.schemastore.org/json",
  "comment": "Animal Crossing inspired typography with rounded, friendly characteristics",
  "typography": {
    "baseSize": "clamp(1.15rem, 0.2vi + 1.1rem, 1.2rem)",
    
    "fontFamilies": {
      "primary": ["FinkHeavy", "Baloo 2", "system-ui", "sans-serif"],
      "secondary": ["Seurat Pro", "M PLUS Rounded 1c", "system-ui", "sans-serif"],
      "body": ["M PLUS Rounded 1c", "system-ui", "sans-serif"]
    },

    "fontWeights": {
      "regular": "500",
      "medium": "600",
      "bold": "700"
    },

    "fontSizes": {
      "2xs": "0.85rem",
      "1xs": "1rem",
      "md": "1.15rem",
      "1xl": "1.35rem",
      "2xl": "1.75rem",
      "3xl": "2.25rem",
      "4xl": "3rem"
    },

    "lineHeight": {
      "normal": "1.6",
      "cjk": "calc(1.1em + 1rem)",
      "heading": "1.2"
    },

    "letterSpacing": {
      "normal": "0.02em",
      "loose": "0.05em",
      "tight": "0.01em"
    }
  }
} ```

# /srv/famichat/config/design-tokens/themes/animal-crossing/colors.json

```json
{
  "$schema": "https://json.schemastore.org/json",
  "comment": "Animal Crossing inspired theme with natural, cheerful colors",
  "colors": {
    "whitePoint": "oklch(98% 0.01 95deg)",
    "blackPoint": "oklch(25% 0.02 275deg)",

    "leaf": {
      "100": "oklch(95% 0.12 145deg)",
      "200": "oklch(90% 0.15 145deg)",
      "300": "oklch(85% 0.18 145deg)",
      "400": "oklch(80% 0.20 145deg)",
      "500": "oklch(75% 0.22 145deg)",
      "600": "oklch(70% 0.24 145deg)"
    },

    "sky": {
      "100": "oklch(95% 0.10 235deg)",
      "200": "oklch(90% 0.12 235deg)",
      "300": "oklch(85% 0.14 235deg)",
      "400": "oklch(80% 0.16 235deg)",
      "500": "oklch(75% 0.18 235deg)"
    },

    "sand": {
      "100": "oklch(95% 0.05 85deg)",
      "200": "oklch(90% 0.07 85deg)",
      "300": "oklch(85% 0.09 85deg)",
      "400": "oklch(80% 0.11 85deg)"
    },

    "peach": {
      "100": "oklch(95% 0.07 45deg)",
      "200": "oklch(90% 0.09 45deg)",
      "300": "oklch(85% 0.11 45deg)",
      "400": "oklch(80% 0.13 45deg)"
    },

    "textColor": {
      "main": "oklch(30% 0.02 275deg)",
      "callout": "oklch(25% 0.02 275deg)",
      "deemphasized": "oklch(45% 0.04 275deg)",
      "suppressed": "oklch(60% 0.06 275deg)",
      "accent": "oklch(65% 0.20 145deg)"
    },

    "background": {
      "primary": "oklch(98% 0.02 85deg)",
      "secondary": "oklch(95% 0.04 85deg)",
      "tertiary": "oklch(90% 0.06 85deg)",
      "accent": "oklch(85% 0.18 145deg)"
    }
  }
} ```

# /srv/famichat/config/design-tokens/themes/default/typography.json

```json
{
  "$schema": "https://json.schemastore.org/json",
  "comment": "Default theme references for typography—currently the same as base, but can override or extend as needed.",
  "typography": {
    "baseSize": "{typography.baseSize}",
    "fontSizes": "{typography.fontSizes}",
    "lineHeight": "{typography.lineHeight}"
  }
} ```

# /srv/famichat/config/design-tokens/themes/default/colors.json

```json
{
  "$schema": "https://json.schemastore.org/json",
  "comment": "Default theme references for color, with possible overrides from base.",
  "colors": {
    "textColor": {
      "main": "{colors.neutral.0}",
      "callout": "{colors.whiteAbsolute}",
      "deemphasized": "{colors.dusk.500}",
      "suppressed": "{colors.dusk.600}",
      "accent": "{colors.ochre.0}"
    }
  }
} ```

# /srv/famichat/backend/lib/famichat.ex

```ex
defmodule Famichat do
  @moduledoc """
  Famichat keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
end
```

# /srv/famichat/backend/lib/famichat_web.ex

```ex
defmodule FamichatWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, views, channels and so on.

  This can be used in your application as:

      use FamichatWeb, :controller
      use FamichatWeb, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """

  def static_paths,
    do:
      ~w(css fonts images js favicon.ico favicon-32x32.png favicon-16x16.png site.webmanifest mstile
        robots.txt 502.html maintenance.html
        apple-touch-icon.png android-chrome browserconfig manifest.json mstile
        safari-pinned-tab.svg)

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      import FamichatWeb.Gettext
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: FamichatWeb.Layouts]

      import Plug.Conn
      import FamichatWeb.Gettext

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {FamichatWeb.Layouts, :app}

      import FamichatWeb.LiveHelpers
      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      import FamichatWeb.CoreComponents
      import FamichatWeb.Gettext
      import FamichatWeb.Components.Typography

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: FamichatWeb.Endpoint,
        router: FamichatWeb.Router,
        statics: FamichatWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
```

# /srv/famichat/backend/lib/famichat_web/router.ex

```ex
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
      "content-security-policy" => "default-src 'self'"
    }

    plug CommonMetadata
    # Do not include the LocaleRedirection plug here
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api/v1", FamichatWeb do
    pipe_through :api

    get "/hello", HelloController, :index
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
        live "/notes/new", NoteLive.Index, :new
        live "/note/:url/edit", NoteLive.Index, :edit
        live "/note/:url/show/edit", NoteLive.Show, :edit

        live "/case-study/new", CaseStudyLive.Index, :new
        live "/case-study/:url/edit", CaseStudyLive.Index, :edit
        live "/case-study/:url", CaseStudyLive.Show, :show
        live "/case-study/:url/show/edit", CaseStudyLive.Show, :edit
      end

      # Keep non-LiveView routes outside the live_session
      get "/up/", UpController, :index
      get "/up/databases", UpController, :databases
      live_dashboard "/dashboard", metrics: FamichatWeb.Telemetry
    end
  end

  scope "/", FamichatWeb do
    pipe_through [:browser, :locale]

    live "/", HomeLive
  end

  # Catch-all route for unmatched paths
  scope "/", FamichatWeb do
    pipe_through :browser
    get "/up/", UpController, :index
    get "/up/databases", UpController, :databases
  end

  scope "/:locale", FamichatWeb do
    pipe_through [:browser, :locale]

    live_session :default, on_mount: FamichatWeb.LiveHelpers do
      live "/", HomeLive, :index
      live "/kitchen-sink", KitchenSinkLive, :index
      live "/case-studies", CaseStudyLive.Index, :index
      live "/case-study/:url", CaseStudyLive.Show, :show
      live "/notes", NoteLive.Index, :index
      live "/note/:url", NoteLive.Show, :show
      live "/self", AboutLive, :index
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
```

# /srv/famichat/backend/lib/famichat_web/endpoint.ex

```ex
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
```

# /srv/famichat/backend/lib/famichat_web/controllers/hello_controller.ex

```ex
defmodule FamichatWeb.HelloController do
  use FamichatWeb, :controller

  def index(conn, _params) do
    json(conn, %{message: "Hello from Famichat!"})
  end
end
```

# /srv/famichat/backend/lib/famichat_web/controllers/error_json.ex

```ex
defmodule FamichatWeb.ErrorJSON do
  @moduledoc """
  If you want to customize a particular status code,
  you may add your own clauses, such as:

  def render("500.json", _assigns) do
    %{errors: %{detail: "Internal Server Error"}}
  end

  By default, Phoenix returns the status message from
  the template name. For example, "404.json" becomes
  "Not Found".
  """
  def render(template, _assigns) do
    %{
      errors: %{
        detail: Phoenix.Controller.status_message_from_template(template)
      }
    }
  end
end
```

# /srv/famichat/backend/lib/famichat_web/controllers/error_html/500.html.heex

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <.live_title>
      <%= assigns[:page_title] ||
        "Zane Riley | Product Designer (Tokyo) | 10+ Years Experience" %>
    </.live_title>

    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <meta
      name="description"
      content={
        assigns[:page_description] ||
          ~c"Zane Riley: Tokyo Product Designer. 10+ yrs experience. Currently at Google. Worked in e-commerce, healthcare, and finance. Designed and built products for Google, Google Maps, and Google Search."
      }
    />

    <link
      rel="apple-touch-icon"
      sizes="180x180"
      href={url(~p"/apple-touch-icon.png")}
    />
    <link
      rel="icon"
      type="image/png"
      sizes="32x32"
      href={url(~p"/favicon-32x32.png")}
    />
    <link
      rel="icon"
      type="image/png"
      sizes="16x16"
      href={url(~p"/favicon-16x16.png")}
    />
    <link
      rel="mask-icon"
      href={url(~p"/safari-pinned-tab.svg")}
      color="#597099"
    />
    <link rel="manifest" href={url(~p"/site.webmanifest")} />
    <!-- Color definitions -->
    <meta name="msapplication-TileColor" content="#2b5797" />
    <meta name="theme-color" content="#343334" />
    <!-- Dynamic Schema Markup -->

    <!-- Dynamic OG Meta -->
    <%= if assigns[:og_meta] do %>
      <meta property="og:title" content={assigns[:og_meta][:title]} />
      <meta property="og:type" content={assigns[:og_meta][:type]} />
      <meta property="og:image" content={assigns[:og_meta][:image]} />
      <meta property="og:description" content={assigns[:og_meta][:description]} />
    <% end %>
    <link phx-track-static rel="stylesheet" href={url(~p"/css/critical.css")} />
    <!-- FUll CSS -->
    <link phx-track-static rel="stylesheet" href={url(~p"/css/app.css")} />
    <script
      defer
      phx-track-static
      type="text/javascript"
      src={url(~p"/js/app.js")}
    />
  </head>
  <body class="min-h-screen text-md">
    <a href="#main-content" class="sr-only" tabindex="0">
      <%= gettext("Skip to main content") %>
    </a>
    <div class="min-h-screen flex items-center justify-center">
      <div
        class=""
        style="filter: url('#waves');transform: translateY(-0.25rem) translateX(calc(0rem));"
      >
        /********************************************** <br />
        <a href="/" class="" aria-label="Return to homepage">
          <%= dynamic_home_url() %>
        </a>
        <h1>ERROR 500 <br /> INTERNAL SERVER ERROR</h1>
        * SYSTEM: Zane's Design Famichat <br />
        * STATUS: [SOMETHING WENT WRONG, BUT DON'T PANIC] <br />
        ***********************************************/ <br />
        <br /> GREETINGS,<br />
        <br /> THIS TERMINAL REGRETS TO INFORM YOU <br />
        THAT A CRITICAL ERROR HAS OCCURRED <br />
        <br /> RESILIENCE IS KEY, BUT EVEN MACHINES FALTER.<br />
        THIS TERMINAL WISHES YOU LUCK ON <br />
        YOUR CONTINUED EXPLORATION.<br />
        <br /> ≺system initiating self-reflection protocol≻<br />
        <p class=""><a href="/" class="pb-6 block">RETURN TO HOME</a></p>

        <svg
          class="waves absolute top-0 left-0"
          xmlns="http://www.w3.org/2000/svg"
          version="1.1"
        >
          <defs>
            <filter id="waves">
              <feturbulence
                baseFrequency="0.0015"
                numOctaves="5"
                result="noise"
                seed="2"
              >
              </feturbulence>
              <fedisplacementmap
                id="displacement"
                in="SourceGraphic"
                in2="noise"
                scale="50"
              >
              </fedisplacementmap>
            </filter>
          </defs>
        </svg>
      </div>
    </div>
  </body>
</html>
```

# /srv/famichat/backend/lib/famichat_web/controllers/error_html/404.html.heex

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <.live_title>
      <%= assigns[:page_title] ||
        "Zane Riley | Product Designer (Tokyo) | 10+ Years Experience" %>
    </.live_title>

    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <meta
      name="description"
      content={
        assigns[:page_description] ||
          ~c"Zane Riley: Tokyo Product Designer. 10+ yrs experience. Currently at Google. Worked in e-commerce, healthcare, and finance. Designed and built products for Google, Google Maps, and Google Search."
      }
    />

    <link
      rel="apple-touch-icon"
      sizes="180x180"
      href={url(~p"/apple-touch-icon.png")}
    />
    <link
      rel="icon"
      type="image/png"
      sizes="32x32"
      href={url(~p"/favicon-32x32.png")}
    />
    <link
      rel="icon"
      type="image/png"
      sizes="16x16"
      href={url(~p"/favicon-16x16.png")}
    />
    <link
      rel="mask-icon"
      href={url(~p"/safari-pinned-tab.svg")}
      color="#597099"
    />
    <link rel="manifest" href={url(~p"/site.webmanifest")} />
    <!-- Color definitions -->
    <meta name="msapplication-TileColor" content="#2b5797" />
    <meta name="theme-color" content="#343334" />
    <!-- Dynamic Schema Markup -->

    <!-- Dynamic OG Meta -->
    <%= if assigns[:og_meta] do %>
      <meta property="og:title" content={assigns[:og_meta][:title]} />
      <meta property="og:type" content={assigns[:og_meta][:type]} />
      <meta property="og:image" content={assigns[:og_meta][:image]} />
      <meta property="og:description" content={assigns[:og_meta][:description]} />
    <% end %>
    <!-- FUll CSS -->
    <link phx-track-static rel="stylesheet" href={url(~p"/css/app.css")} />
    <script
      defer
      phx-track-static
      type="text/javascript"
      src={url(~p"/js/app.js")}
    />
  </head>
  <body class="min-h-screen text-md">
    <a href="#main-content" class="sr-only" tabindex="0">
      <%= gettext("Skip to main content") %>
    </a>
    <div class="min-h-screen flex items-center justify-center">
      <div
        class=""
        style="filter: url('#waves');transform: translateY(-0.25rem) translateX(calc(0rem));"
      >
        /********************************************** <br />
        <a href="/" class="" aria-label={gettext("Return to homepage")}>
          <%= dynamic_home_url() %>
        </a>
        <h1>
          <%= gettext("ERROR 404") %> <br /> <%= gettext("DATA NOT FOUND") %>
        </h1>
        * <%= gettext("SYSTEM: Zane's Design Famichat") %> <br />
        * <%= gettext("STATUS: [CONFUSED BUT OPERATIONAL]") %> <br />
        ***********************************************/ <br />
        <br />

        <%= gettext("GREETINGS,") %><br />
        <br />

        <%= gettext("THE DATA YOU SEEK HAS EITHER") %> <br />
        <%= gettext("DISAPPEARED INTO THE VOID OR") %><br />
        <%= gettext("NEVER EXISTED IN THE FIRST PLACE") %><br />
        <br />

        <%= gettext("EVERY DEAD END IS JUST A NEW BEGINNING.") %><br />
        <%= gettext("THIS TERMINAL WISHES YOU LUCK ON") %> <br />
        <%= gettext("YOUR CONTINUED EXPLORATION.") %><br />
        <br /> ≺system initiating self-reflection protocol≻<br />
        <p class="">
          <a href="/" class="pb-6 block"><%= gettext("RETURN TO HOME") %></a>
        </p>

        <svg
          class="waves absolute top-0 left-0"
          xmlns="http://www.w3.org/2000/svg"
          version="1.1"
        >
          <defs>
            <filter id="waves">
              <feturbulence
                baseFrequency="0.0015"
                numOctaves="5"
                result="noise"
                seed="2"
              >
              </feturbulence>
              <fedisplacementmap
                id="displacement"
                in="SourceGraphic"
                in2="noise"
                scale="50"
              >
              </fedisplacementmap>
            </filter>
          </defs>
        </svg>
      </div>
    </div>
  </body>
</html>
```

# /srv/famichat/backend/lib/famichat_web/controllers/content_webhook_controller.ex

```ex
defmodule FamichatWeb.ContentWebhookController do
  @moduledoc """
  Handles incoming GitHub webhook payloads for content updates.

  This controller processes webhook payloads from GitHub,
  determines if they contain relevant changes to the content,
  and triggers content updates when necessary.
  """

  require Logger
  alias Famichat.Content.Remote.RemoteUpdateTrigger
  alias Famichat.Content.Types

  @type webhook_result ::
          {:ok, :updated | :no_relevant_changes} | {:error, String.t()}

  @spec handle_webhook(Plug.Conn.t(), map(), keyword()) :: webhook_result()
  def handle_webhook(_conn, payload, opts) do
    Logger.info("Processing webhook payload")

    with {:ok, event_type} <- extract_event_type(payload),
         :ok <- validate_push_event(event_type),
         {:ok, relevant_changes} <- extract_relevant_changes(payload) do
      case relevant_changes do
        [] ->
          Logger.info("No relevant file changes detected")
          {:ok, :no_relevant_changes}

        changes ->
          Logger.info("Relevant file changes detected: #{inspect(changes)}")
          trigger_update(opts)
      end
    else
      {:error, reason} ->
        Logger.warning("Error processing webhook: #{reason}")
        {:error, reason}
    end
  end

  @spec extract_event_type(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp extract_event_type(%{"commits" => _}) do
    {:ok, "push"}
  end

  defp extract_event_type(_) do
    {:error, "Invalid or unsupported event type"}
  end

  @spec validate_push_event(String.t()) :: :ok | {:error, String.t()}
  defp validate_push_event("push"), do: :ok
  defp validate_push_event(_), do: {:error, "Only push events are supported"}

  @spec extract_relevant_changes(map()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  defp extract_relevant_changes(%{"commits" => commits})
       when is_list(commits) do
    relevant_changes =
      commits
      |> Stream.flat_map(fn commit ->
        (commit["added"] || []) ++ (commit["modified"] || [])
      end)
      |> Stream.uniq()
      |> Stream.filter(&relevant_file_change?/1)
      |> Enum.to_list()

    {:ok, relevant_changes}
  end

  defp extract_relevant_changes(_), do: {:error, "Invalid payload structure"}

  @spec relevant_file_change?(String.t()) :: boolean()
  defp relevant_file_change?(path) do
    with true <- Path.extname(path) == ".md",
         true <- not String.starts_with?(Path.basename(path), "."),
         {:ok, _type} <- Types.get_type(path) do
      true
    else
      _ -> false
    end
  end

  @spec trigger_update(keyword()) :: webhook_result()
  defp trigger_update(opts) do
    Logger.info("Triggering update with RemoteUpdateTrigger")

    case RemoteUpdateTrigger.trigger_update(content_repo_url(opts)) do
      {:ok, _} ->
        Logger.info("RemoteUpdateTrigger completed successfully")
        {:ok, :updated}

      {:error, reason} ->
        Logger.error("RemoteUpdateTrigger failed: #{inspect(reason)}")
        {:error, "Update failed: #{inspect(reason)}"}
    end
  end

  @spec content_repo_url(keyword()) :: String.t()
  defp content_repo_url(opts) do
    Keyword.get(opts, :content_repo_url) ||
      Application.fetch_env!(:famichat, :content_repo_url)
  end
end
```

# /srv/famichat/backend/lib/famichat_web/controllers/up_controller.ex

```ex
defmodule FamichatWeb.UpController do
  use FamichatWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:ok, "")
  end

  def databases(conn, _params) do
    Ecto.Adapters.SQL.query!(Famichat.Repo, "SELECT 1")

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:ok, "")
  end
end
```

# /srv/famichat/backend/lib/famichat_web/controllers/error_html.ex

```ex
defmodule FamichatWeb.ErrorHTML do
  @moduledoc """
  If you want to customize your error pages,
  uncomment the embed_templates/1 call below
  and add pages to the error directory:

    * lib/famichat_web/controllers/error_html/404.html.heex
    * lib/famichat_web/controllers/error_html/500.html.heex

  The default is to render a plain text page based on
  the template name. For example, "404.html" becomes
  "Not Found".
  """
  use FamichatWeb, :html
  import FamichatWeb.Gettext

  embed_templates "error_html/*"

  # Return a 400 instead of raising an Exception if a request has
  # the wrong Mime format (e.g. "text")
  defimpl Plug.Exception, for: Phoenix.NotAcceptableError do
    def status(_exception), do: 400
    def actions(_exception), do: []
  end

  # Return a 400 instead of raising an Exception if a request has
  # an invalid CSRF token.
  defimpl Plug.Exception, for: Plug.CSRFProtection.InvalidCSRFTokenError do
    def status(_exception), do: 400
    def actions(_exception), do: []
  end

  def dynamic_home_url do
    scheme = Application.get_env(:famichat, :url_scheme, "http")
    host = Application.get_env(:famichat, :url_host, "localhost")
    port = Application.get_env(:famichat, :url_port, "8001")

    port_segment = if port in ["80", "443"], do: "", else: ":#{port}"
    "#{scheme}://#{host}#{port_segment}"
  end

  def render(embed_template, _assigns) do
    Phoenix.Controller.status_message_from_template(embed_template)
  end
end
```

# /srv/famichat/backend/lib/famichat_web/telemetry.ex

```ex
defmodule FamichatWeb.Telemetry do
  @moduledoc """
  Emit events at various stages of an application's lifecycle.
  """

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # SetLocale Plug Metrics
      summary("famichat.plug.set_locale.call.duration",
        unit: {:native, :millisecond},
        description: "The time spent in the SetLocale plug's call function"
      ),
      summary("famichat.plug.set_locale.extract_locale.duration",
        unit: {:native, :millisecond},
        description:
          "The time spent extracting the locale in the SetLocale plug"
      ),
      summary("famichat.plug.set_locale.set_locale.duration",
        unit: {:native, :millisecond},
        description: "The time spent setting the locale in the SetLocale plug"
      ),
      distribution("famichat.plug.set_locale.extract_locale.source",
        event_name: [:famichat, :plug, :set_locale, :extract_locale],
        measurement: :source,
        description: "Distribution of locale sources"
      ),

      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("famichat.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("famichat.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "Time spent decoding the data received from the database"
      ),
      summary("famichat.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "Time spent executing the query"
      ),
      summary("famichat.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "Time spent waiting for a database connection"
      ),
      summary("famichat.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "Time spent waiting for the conn to be checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {FamichatWeb, :count_users, []}
    ]
  end
end
```

# /srv/famichat/backend/lib/famichat_web/channels/user_socket.ex

```ex
defmodule FamichatWeb.UserSocket do
  use Phoenix.Socket
  require Logger

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  # defp verify_token_and_connect(token, socket) do
  #   salt = @salt

  #   case Phoenix.Token.verify(FamichatWeb.Endpoint, salt, token,
  #          max_age: 86_400
  #        ) do
  #     {:ok, user_id} ->
  #       Logger.debug("User connected with user_id: #{user_id}")
  #       {:ok, assign(socket, :user_id, user_id)}

  #     {:error, reason} ->
  #       Logger.error("User connection failed due to invalid token: #{reason}")
  #       {:error, %{reason: "invalid_token"}}
  #   end
  # end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     FamichatWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  def id(_socket), do: nil
end
```

# /srv/famichat/backend/lib/famichat_web/gettext.ex

```ex
defmodule FamichatWeb.Gettext do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext),
  your module gains a set of macros for translations, for example:

      import FamichatWeb.Gettext

      # Simple translation
      gettext("Here is the string to translate")

      # Plural translation
      ngettext("Here is the string to translate",
               "Here are the strings to translate",
               3)

      # Domain-based translation
      dgettext("errors", "Here is the error message to translate")

  See the [Gettext Docs](https://hexdocs.pm/gettext) for detailed usage.
  """
  use Gettext, otp_app: :famichat
end
```

# /srv/famichat/backend/lib/famichat_web/plugs/csp_header.ex

```ex
defmodule FamichatWeb.Plugs.CSPHeader do
  @moduledoc """
  Handles the construction and application of Content Security Policy headers.
  Provides dynamic CSP generation based on runtime configuration and environment.
  """
  import Plug.Conn
  require Logger

  @type csp_config :: %{
          scheme: String.t(),
          host: String.t(),
          port: String.t(),
          additional_hosts: list(String.t()),
          report_only: boolean()
        }
  @type report_only :: boolean()
  @env Application.compile_env(:famichat, :environment)
  @env_module if @env == :dev,
                do: FamichatWeb.Plugs.CSPHeader.Dev,
                else: FamichatWeb.Plugs.CSPHeader.Prod
  @report_only Application.compile_env(:famichat, [:csp, :report_only], false)
  @default_scheme "https"
  @default_port "443"
  @default_host "localhost"

  @spec generate_csp_for_testing(map()) :: String.t()
  def generate_csp_for_testing(config) do
    build_csp(config)
  end

  @spec init(keyword()) :: keyword()
  def init(opts) do
    Logger.debug(
      "CSPHeader init - Environment: #{@env}, Module: #{@env_module}"
    )

    opts
  end

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    conn
    |> get_csp_config()
    |> build_csp()
    |> apply_csp_header(conn)
  end

  defp apply_csp_header(csp, conn) do
    header_name =
      if @report_only,
        do: "content-security-policy-report-only",
        else: "content-security-policy"

    put_resp_header(conn, header_name, csp)
  end

  @spec get_csp_config(Plug.Conn.t()) :: csp_config()
  defp get_csp_config(conn) do
    %{
      scheme: System.get_env("URL_SCHEME", @default_scheme),
      host: get_host(conn),
      port: System.get_env("URL_PORT", @default_port),
      additional_hosts: parse_additional_hosts(),
      report_only: @report_only
    }
  end

  defp get_host(conn) do
    conn.host ||
      Application.get_env(:famichat, FamichatWeb.Endpoint)[:url][:host]
  end

  @spec parse_additional_hosts() :: list(String.t())
  defp parse_additional_hosts do
    (System.get_env("CSP_ADDITIONAL_HOSTS", "") <> ",localhost,0.0.0.0")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.uniq()
  end

  @spec build_csp(csp_config) :: String.t()
  defp build_csp(config) do
    ws_url = construct_url(config, :ws)
    all_hosts = get_all_hosts(config)

    [
      default_src: "'self' #{all_hosts}",
      script_src: "'self' #{all_hosts} 'unsafe-inline'",
      style_src: "'self' #{all_hosts} 'unsafe-inline'",
      img_src: "'self' #{all_hosts} data:",
      font_src: "'self' #{all_hosts}",
      connect_src: "'self' #{all_hosts} #{ws_url}",
      frame_src: @env_module.frame_src(),
      object_src: "'none'",
      base_uri: "'self'",
      form_action: "'self'",
      frame_ancestors: "'none'"
    ]
    |> @env_module.maybe_add_upgrade_insecure_requests()
    |> Enum.map_join("; ", fn {key, value} ->
      "#{key |> to_string() |> String.replace("_", "-")} #{value}"
    end)
  end

  @spec construct_url(csp_config, :base | :ws) :: String.t()
  defp construct_url(config, type) do
    scheme =
      if type == :ws and config.scheme == "https",
        do: "wss",
        else: config.scheme

    port = if config.port in ["80", "443"], do: "", else: ":#{config.port}"
    "#{scheme}://#{config.host}#{port}"
  end

  @spec get_all_hosts(csp_config) :: String.t()
  defp get_all_hosts(config) do
    [config.host, "localhost", "0.0.0.0" | config.additional_hosts]
    |> Enum.map_join(" ", &"#{config.scheme}://#{&1}:#{config.port}")
  end
end
```

# /srv/famichat/backend/lib/famichat_web/plugs/locale_redirection.ex

```ex
defmodule FamichatWeb.Plugs.LocaleRedirection do
  @moduledoc """
  A plug that handles locale-based redirections for incoming requests.

  This plug checks the initial segment of the request path to determine if it corresponds to a supported locale.
  If the locale is not supported or missing, it redirects the user to a path that includes their preferred locale.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]
  require Logger

  @supported_locales Application.compile_env!(:famichat, :supported_locales)
  @default_locale Application.compile_env!(:famichat, :default_locale)
  @max_redirects 4

  @type locale :: String.t()
  @type path :: String.t()

  def init(opts), do: opts

  @spec call(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def call(conn, _opts) do
    log(:debug, "LocaleRedirection plug called for path: #{conn.request_path}")
    log(:debug, "Request path: #{conn.request_path}")

    normalized_path = normalize_path(conn.request_path)
    log(:debug, "Normalized path: #{normalized_path}")

    {locale_from_url, remaining_path} =
      extract_locale_from_path(normalized_path)

    log(
      :debug,
      "Extracted locale: '#{locale_from_url}', Remaining path: '#{remaining_path}'"
    )

    user_locale = get_user_locale(conn)
    log(:debug, "User locale: #{user_locale}")

    conn = conn |> assign(:path_without_locale, remaining_path)

    handle_locale(conn, locale_from_url, normalized_path, user_locale)
  end

  @spec handle_locale(Plug.Conn.t(), locale(), path(), locale()) ::
          Plug.Conn.t()
  defp handle_locale(conn, locale_from_url, path, user_locale) do
    cond do
      # If the URL already contains a supported locale, no redirection is needed
      locale_from_url in @supported_locales ->
        log(:debug, "Supported locale #{locale_from_url} found in URL.")
        put_session(conn, :redirect_count, 0)

      # Check if it's a single segment path that's not a locale
      String.split(path, "/", trim: true) |> length() == 1 and
          not valid_route?(conn, path) ->
        log(:info, "Single segment invalid path detected. Halting.")

        raise Phoenix.Router.NoRouteError,
          conn: conn,
          router: FamichatWeb.Router

      # If the locale is missing or unsupported, attempt to redirect
      true ->
        log(
          :info,
          "Unsupported or missing locale in URL, redirecting to user locale."
        )

        # Generate possible redirect paths with the user's locale
        redirect_paths = build_path_with_locale(path, user_locale)

        # Find the first valid path from the generated redirect paths
        valid_path =
          Enum.find(redirect_paths, fn path ->
            valid_route?(conn, path)
          end)

        case valid_path do
          # If no valid path is found, log a warning and return the conn without redirecting
          nil ->
            log(:debug, "No valid route found after adding locale.")

            raise Phoenix.Router.NoRouteError,
              conn: conn,
              router: FamichatWeb.Router

          # If a valid path is found, reset the redirect count and perform the redirection
          path ->
            conn =
              conn
              |> put_session(:redirect_count, 0)
              |> redirect_to_locale(path, user_locale)
        end
    end
  end

  @spec redirect_to_locale(Plug.Conn.t(), path(), locale()) :: Plug.Conn.t()
  defp redirect_to_locale(conn, path, _locale) do
    redirect_count = get_redirect_count(conn)
    log(:debug, "Current redirect count: #{redirect_count}")

    if redirect_count >= @max_redirects do
      log(:error, "Max redirects reached. Path: #{path}")
      conn
    else
      log(:info, "Redirecting to: #{path}")
      do_redirect(conn, path, redirect_count + 1)
    end
  end

  @spec do_redirect(Plug.Conn.t(), path(), integer()) :: Plug.Conn.t()
  defp do_redirect(conn, path, redirect_count) do
    conn
    |> put_session(:redirect_count, redirect_count)
    |> put_status(:moved_permanently)
    |> redirect(to: path)
    |> halt()
  end

  @spec valid_route?(Plug.Conn.t(), path()) :: boolean()
  defp valid_route?(conn, path) do
    log(:debug, "Checking if route is valid: #{path}")
    log(:debug, "Method: #{conn.method}, Host: #{conn.host}")

    result =
      Phoenix.Router.route_info(
        FamichatWeb.Router,
        conn.method,
        path,
        conn.host
      ) != :error

    log(:debug, "Route #{path} is #{if result, do: "valid", else: "invalid"}")

    log(
      :debug,
      "Route info: #{inspect(Phoenix.Router.route_info(FamichatWeb.Router, conn.method, path, conn.host))}"
    )

    result
  end

  @spec normalize_path(path()) :: path()
  def normalize_path(path) do
    path
    |> String.replace(~r/\/+/, "/")
    |> String.trim_trailing("/")
  end

  @spec extract_locale_from_path(path()) :: {locale(), path()}
  def extract_locale_from_path(path) do
    case String.split(path, "/", parts: 2, trim: true) do
      [possible_locale | remaining_parts] ->
        if String.downcase(possible_locale) in Enum.map(
             @supported_locales,
             &String.downcase/1
           ) do
          {String.downcase(possible_locale),
           "/" <> Enum.join(remaining_parts, "/")}
        else
          {"", path}
        end

      _ ->
        {"", path}
    end
  end

  @spec get_user_locale(Plug.Conn.t()) :: locale()
  defp get_user_locale(conn) do
    conn.assigns[:user_locale] ||
      get_session(conn, "user_locale") ||
      @default_locale
  end

  @spec build_path_with_locale(path(), locale()) :: [path()]
  defp build_path_with_locale(request_path, user_locale) do
    parts = String.split(request_path, "/", parts: 3, trim: true)

    locale =
      if user_locale in @supported_locales,
        do: user_locale,
        else: @default_locale

    case parts do
      [] ->
        ["/#{locale}"]

      [segment] when segment not in @supported_locales ->
        # For single-segment paths that are not locales, only try adding the locale
        ["/#{locale}/#{segment}"]

      [first | rest] when first in @supported_locales ->
        ["/#{locale}#{if rest == [], do: "", else: "/#{Enum.join(rest, "/")}"}"]

      _ ->
        [
          "/#{locale}#{if tl(parts) == [], do: "", else: "/#{Enum.join(tl(parts), "/")}"}"
        ]
    end
  end

  @spec get_redirect_count(Plug.Conn.t()) :: integer()
  defp get_redirect_count(conn) do
    get_session(conn, :redirect_count) || 0
  end

  @spec log(atom(), String.t()) :: :ok
  defp log(level, message) do
    Logger.log(level, fn -> "[#{message}" end)
  end

  def supported_locales, do: @supported_locales
  def default_locale, do: @default_locale
end
```

# /srv/famichat/backend/lib/famichat_web/plugs/csp_header/prod.ex

```ex
defmodule FamichatWeb.Plugs.CSPHeader.Prod do
  @moduledoc """
  Production environment specific CSP functions.
  """

  @spec frame_src() :: String.t()
  def frame_src, do: "'none'"

  @spec maybe_add_upgrade_insecure_requests(keyword()) :: keyword()
  def maybe_add_upgrade_insecure_requests(directives) do
    [{"upgrade-insecure-requests", ""} | directives]
  end
end
```

# /srv/famichat/backend/lib/famichat_web/plugs/csp_header/dev.ex

```ex
defmodule FamichatWeb.Plugs.CSPHeader.Dev do
  @moduledoc """
  Development environment specific CSP functions.
  """

  @spec frame_src() :: String.t()
  def frame_src, do: "'self'"

  @spec maybe_add_upgrade_insecure_requests(keyword()) :: keyword()
  def maybe_add_upgrade_insecure_requests(directives), do: directives
end
```

# /srv/famichat/backend/lib/famichat_web/plugs/common_metadata.ex

```ex
defmodule FamichatWeb.Plugs.CommonMetadata do
  @moduledoc """
    A plug for injecting common metadata into the connection struct.

    This plug is responsible for adding metadata that is commonly used across different requests in the application. It performs the following actions:

      - Retrieves the current local date and extracts the year.
      - Assigns the current year to the `:current_year` key in the connection struct.

    By doing so, it makes the current year readily available to controllers and views, which can be useful for copyright notices, time-sensitive features, or any functionality that requires knowledge of the current year.

    After the plug is invoked, you can access the current year in your controllers and templates with `@conn.assigns.current_year`.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    {date, _time} = :calendar.local_time()
    {current_year, _month, _day} = date

    conn
    |> assign(:current_year, current_year)
  end
end
```

# /srv/famichat/backend/lib/famichat_web/plugs/set_locale.ex

```ex
defmodule FamichatWeb.Plugs.SetLocale do
  @moduledoc """
  A plug that sets the locale for the connection.

  This plug determines the user's preferred locale by examining various sources in the following order:
  1. The URL path segment (e.g., '/en/some/path')
  2. The user's session, if previously set
  3. The 'Accept-Language' HTTP header
  4. The application's default locale

  If a locale is found, it is set for the connection and used by the Gettext module for translations. Additionally, the locale is stored in the user's session and sent back in the 'Content-Language' HTTP response header.

  Static assets are not affected by this plug, as their paths are matched against predefined static paths and served without setting a locale.
  """
  import Plug.Conn
  require Logger

  import FamichatWeb.Plugs.LocaleRedirection,
    only: [
      normalize_path: 1,
      extract_locale_from_path: 1
    ]

  @telemetry_prefix [:famichat, :plug, :set_locale]
  @supported_locales FamichatWeb.Plugs.LocaleRedirection.supported_locales()
  @default_locale FamichatWeb.Plugs.LocaleRedirection.default_locale()
  @static_paths FamichatWeb.static_paths()

  @type locale :: String.t()
  @type path :: String.t()
  @type locale_source :: :url | :session | :accept_language | :default

  @spec log(atom(), String.t(), keyword()) :: :ok
  defp log(level, message, metadata) do
    Logger.log(level, fn -> "[SetLocale] #{message}" end, metadata)
  end

  @spec init(any()) :: any()
  def init(default), do: default

  @doc """
  Calls the plug to set the locale for the connection.

  If the request is for a static asset, it passes through without modification.
  Otherwise, it extracts the locale and sets it for the connection.
  """
  @spec call(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def call(conn, _default) do
    start_time = System.monotonic_time()

    normalized_path = normalize_path(conn.request_path)
    conn = %{conn | request_path: normalized_path}

    result =
      if static_asset?(normalized_path) do
        log(:debug, "Static asset detected, skipping locale setting",
          path: normalized_path
        )

        conn
      else
        locale_data = extract_locale(conn)
        set_locale(conn, locale_data)
      end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @telemetry_prefix ++ [:call],
      %{duration: duration},
      %{conn: conn}
    )

    result
  end

  @doc """
  Extracts the locale from the connection.

  It checks the URL, session, and Accept-Language header to determine the user's preferred locale.
  """
  @spec extract_locale(Plug.Conn.t()) :: {locale(), path()}
  def extract_locale(conn) do
    start_time = System.monotonic_time()

    {locale_from_url, remaining_path} =
      extract_locale_from_path(conn.request_path)

    accept_language = get_preferred_language(conn)
    session_locale = get_session(conn, "user_locale")

    user_locale =
      cond do
        locale_from_url in @supported_locales -> locale_from_url
        session_locale in @supported_locales -> session_locale
        accept_language in @supported_locales -> accept_language
        true -> @default_locale
      end

    locale_source =
      determine_locale_source(
        user_locale,
        locale_from_url,
        session_locale,
        accept_language
      )

    params = %{
      event: :locale_extracted,
      locale: user_locale,
      locale_source: locale_source,
      url_locale: locale_from_url,
      session_locale: session_locale,
      accept_language: accept_language,
      path: remaining_path
    }

    json_params = Jason.encode!(params)
    Logger.info("Locale extracted: #{json_params}")

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @telemetry_prefix ++ [:extract_locale],
      %{duration: duration},
      %{conn: conn, locale: user_locale, source: locale_source}
    )

    {user_locale, remaining_path}
  end

  # Sets the locale for the connection.

  # It updates the Gettext locale, stores the locale in the session,
  # assigns it to the connection, and sets the Content-Language header.

  @spec set_locale(Plug.Conn.t(), {locale(), path()}) :: Plug.Conn.t()
  defp set_locale(conn, {user_locale, remaining_path}) do
    start_time = System.monotonic_time()

    result =
      case Phoenix.Router.route_info(
             FamichatWeb.Router,
             conn.method,
             remaining_path,
             conn.host
           ) do
        %{} ->
          Gettext.put_locale(FamichatWeb.Gettext, user_locale)

          log(:debug, "Set Gettext locale",
            locale: user_locale,
            gettext_locale: Gettext.get_locale(FamichatWeb.Gettext)
          )

          conn
          |> put_session("user_locale", user_locale)
          |> assign(:user_locale, user_locale)
          |> assign(:supported_locales, @supported_locales)
          |> put_resp_header("content-language", user_locale)

        :error ->
          log(:warning, "Invalid route after setting locale",
            path: remaining_path
          )

          conn
      end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @telemetry_prefix ++ [:set_locale],
      %{duration: duration},
      %{conn: conn, locale: user_locale}
    )

    result
  end

  # Determines if the given path is for a static asset.

  @spec static_asset?(path()) :: boolean()
  defp static_asset?(path) do
    @static_paths
    |> Enum.any?(fn static_path ->
      Regex.match?(~r/^\/#{static_path}.*\.(png|jpg|jpeg|svg|ico)$/, path)
    end)
  end

  # Gets the preferred language from the Accept-Language header.

  @spec get_preferred_language(Plug.Conn.t()) :: locale()
  defp get_preferred_language(conn) do
    header =
      conn
      |> get_req_header("accept-language")
      |> List.first()

    log(:debug, "Accept-Language header received", header: header)
    parse_accept_language_header(header)
  end

  # Parses the Accept-Language header to determine the preferred language.

  @spec parse_accept_language_header(String.t() | nil) :: locale()
  defp parse_accept_language_header(header) do
    if header in [nil, ""] do
      log(:debug, "Empty Accept-Language header, using default locale",
        default_locale: @default_locale
      )

      @default_locale
    else
      parsed_locale =
        header
        |> String.split(",")
        |> Enum.map(&String.split(&1, ";"))
        |> List.first()
        |> List.first()
        |> String.downcase()
        |> handle_language_subtags()

      log(:debug, "Parsed locale from Accept-Language header",
        parsed_locale: parsed_locale
      )

      parsed_locale
    end
  end

  # Handles language subtags, returning the primary tag if supported, or the default locale.
  @spec handle_language_subtags(String.t()) :: locale()
  defp handle_language_subtags(language_tag) do
    language_primary_tag = String.split(language_tag, "-") |> List.first()

    result =
      case language_primary_tag do
        tag when tag in @supported_locales -> tag
        _ -> @default_locale
      end

    log(:debug, "Handled language subtags", input: language_tag, result: result)
    result
  end

  # Determines the source of the chosen locale.
  @spec determine_locale_source(locale(), locale(), locale(), locale()) ::
          locale_source()
  defp determine_locale_source(
         user_locale,
         locale_from_url,
         session_locale,
         accept_language
       ) do
    source =
      cond do
        user_locale == locale_from_url -> :url
        user_locale == session_locale -> :session
        user_locale == accept_language -> :accept_language
        true -> :default
      end

    log(:debug, "Determined locale source",
      user_locale: user_locale,
      locale_from_url: locale_from_url,
      session_locale: session_locale,
      accept_language: accept_language,
      source: source
    )

    source
  end
end
```

# /srv/famichat/backend/lib/famichat_web/live/about_live.ex

```ex
defmodule FamichatWeb.AboutLive do
  require Logger
  use FamichatWeb, :live_view
  import FamichatWeb.LiveHelpers
  import FamichatWeb.Components.Typography

  def mount(_params, _session, socket) do
    socket =
      assign_page_metadata(
        socket,
        gettext("About Zane Riley | Product Designer"),
        gettext(
          "Learn more about Zane Riley, a Product Designer with over 10 years of experience in various industries."
        )
      )

    {:ok, socket}
  end

  def handle_params(params, uri, socket) do
    socket = handle_locale_and_path(socket, params, uri)
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <.typography locale={@user_locale} tag="p" size="1xl">
        A product designer with over 10 years of experience, currently based in Tokyo and working at Google.
      </.typography>

      <div class="space-y-4">
        <h2 class="text-2xl font-semibold">Experience</h2>
        <div class="space-y-2">
          <p class="font-medium">Google - Senior Product Designer</p>
          <p class="">2018 - Present</p>
        </div>
        <div class="space-y-2">
          <p class="font-medium">NerdWallet - Lead Designer</p>
          <p class="">2015 - 2018</p>
        </div>
      </div>
    </div>
    <div class="aspect-w-1 aspect-h-1 rounded-full overflow-hidden shadow-xl">
      <img src="/images/zane-portrait.jpg" alt="Zane Riley" class="object-cover" />
    </div>
    """
  end
end
```

# /srv/famichat/backend/lib/famichat_web/live/note_live/form_component.ex

```ex
defmodule FamichatWeb.NoteLive.FormComponent do
  use FamichatWeb, :live_component

  alias Famichat.Content

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>
          Use this form to manage note records in your database.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="note-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="grid grid-cols-1 gap-6"
      >
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:content]} type="text" label="Content" />
        <.input field={@form[:url]} type="text" label="URL" />
        <.input field={@form[:locale]} type="text" label="Locale" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Note</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{note: note} = assigns, socket) do
    changeset = Content.change("note", note, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"note" => note_params}, socket) do
    changeset =
      Content.change("note", socket.assigns.note, note_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"note" => note_params}, socket) do
    save_note(socket, socket.assigns.action, note_params)
  end

  defp save_note(socket, :edit, note_params) do
    case Content.update("note", socket.assigns.note, note_params) do
      {:ok, note} ->
        notify_parent({:saved, note})

        {:noreply,
         socket
         |> put_flash(:info, "Note updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_note(socket, :new, note_params) do
    case Content.create("note", note_params) do
      {:ok, note} ->
        notify_parent({:saved, note})

        {:noreply,
         socket
         |> put_flash(:info, "Note created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
```

# /srv/famichat/backend/lib/famichat_web/live/note_live/show.html.heex

```heex
<.header>
  Note <%= @note.id %>
  <:subtitle>This is a note record from your database.</:subtitle>
  <:actions>
    <.link
      patch={Routes.note_show_path(@socket, :edit, @note.url)}
      phx-click={JS.push_focus()}
    >
      <.button>Edit note</.button>
    </.link>
  </:actions>
</.header>

<article class="u-grid col-span-12-children text-pretty text-balance mx-auto max-w-100">
  <nav aria-label="Breadcrumb" class="text-sm">
    <ol class="flex items-center space-x-2">
      <li>
        <.link navigate={Routes.home_path(@socket, :index, @user_locale)}>
          <%= ngettext("Note", "Notes", 1) %>
        </.link>
      </li>
    </ol>
  </nav>
  <!-- Title -->
  <.typography locale={@user_locale} tag="h1" size="4xl">
    <%= @translations["title"] || @note.title %>
  </.typography>
  <!-- Meta Information -->
  <div class="grid grid-cols-subgrid">
    <span class="col-span-3">
      <.typography locale={@user_locale} tag="span" size="1xs" font="cheee">
        <%= gettext("Read Time") %>:
      </.typography>
      <br /><%= @note.read_time %> <%= ngettext(
        "minute",
        "minutes",
        @note.read_time
      ) %>
    </span>
  </div>
  <!-- Main Content -->
  <div class="space-y-md">
    <%= if @translations["content"] do %>
      <%= raw(@translations["content"]) %>
    <% else %>
      <%= if @note.compiled_content do %>
        <%= raw(@note.compiled_content) %>
      <% else %>
        <p><%= gettext("We ran into an issue loading this note!") %></p>
      <% end %>
    <% end %>
  </div>
</article>

<.back navigate={Routes.note_index_path(@socket, :index, @user_locale)}>
  Back to notes
</.back>

<.live_component
  :if={@live_action in [:new, :edit]}
  module={FamichatWeb.NoteLive.FormComponent}
  id={@note.id || :new}
  title={@page_title}
  action={@live_action}
  note={@note}
  patch={Routes.note_index_path(@socket, :index, @user_locale)}
  show
  on_cancel={JS.patch(Routes.note_index_path(@socket, :index, @user_locale))}
  class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto"
/>
```

# /srv/famichat/backend/lib/famichat_web/live/note_live/show.ex

```ex
# lib/famichat_web/live/note_live/show.ex
defmodule FamichatWeb.NoteLive.Show do
  use FamichatWeb, :live_view
  alias FamichatWeb.Router.Helpers, as: Routes
  alias Famichat.Content
  require Logger
  import FamichatWeb.Components.Typography

  @impl true
  def mount(%{"locale" => user_locale}, _session, socket) do
    Gettext.put_locale(FamichatWeb.Gettext, user_locale)
    {:ok, assign(socket, user_locale: user_locale)}
  end

  @dialyzer {:nowarn_function, handle_params: 3}
  @dialyzer {:nowarn_function, set_page_metadata: 2}
  @impl true
  def handle_params(%{"url" => url}, _, socket) do
    case Content.get_with_translations("note", url, socket.assigns.user_locale) do
      {:ok, note, translations, compiled_content} ->
        {page_title, introduction} = set_page_metadata(note, translations)
        Logger.debug("Note translations: #{inspect(translations)}")

        {:noreply,
         assign(socket,
           note: note,
           translations: translations,
           compiled_content: compiled_content,
           page_title: page_title,
           page_description: introduction
         )}

      {:error, :not_found} ->
        raise FamichatWeb.LiveError
    end
  end

  defp set_page_metadata(note, translations) do
    title = translations["title"] || note.title
    introduction = translations["introduction"] || note.introduction

    page_title =
      "#{title} - " <>
        gettext("Note") <>
        " | " <>
        gettext("Zane Riley | Product Design Famichat")

    Logger.debug("Set page title: #{page_title}")
    Logger.debug("Set introduction: #{introduction}")

    {page_title, introduction}
  end
end
```

# /srv/famichat/backend/lib/famichat_web/live/note_live/index.ex

```ex
defmodule FamichatWeb.NoteLive.Index do
  use FamichatWeb, :live_view
  require Logger
  import FamichatWeb.LiveHelpers
  alias Famichat.Content
  alias Famichat.Content.Schemas.Note
  alias FamichatWeb.Router.Helpers, as: Routes

  @impl true
  def on_mount(:default, _params, session, socket) do
    {:cont, FamichatWeb.LiveHelpers.setup_common_assigns(socket, _params, session)}
  end

  @impl true
  def mount(_params, _session, socket) do
    env = Application.get_env(:famichat, :environment)

    Logger.debug("Note index mounted with locale: #{socket.assigns.user_locale}")

    {:ok,
     socket
     |> assign(:env, env)
     |> stream_configure(:notes, dom_id: &"note-#{&1.url}")
     |> stream(:notes, Content.list("note"))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = handle_locale_and_path(socket, params, uri)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Note")
    |> assign(:title, "New Note")
    |> assign(:note, %Note{})
  end

  defp apply_action(socket, :edit, %{"url" => url}) do
    note = Content.get!("note", url)

    socket
    |> assign(:page_title, "Edit Note")
    |> assign(:title, "Edit Note")
    |> assign(:note, note)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Notes")
    |> assign(:title, "Listing Notes")
    |> assign(:note, nil)
  end

  @impl true
  def handle_info({FamichatWeb.NoteLive.FormComponent, {:saved, note}}, socket) do
    {:noreply, stream_insert(socket, :notes, note)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    try do
      note = Content.get!("note", id)

      case Content.delete("note", note) do
        {:ok, _} ->
          {:noreply, stream_delete(socket, :notes, note)}

        {:error, reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Failed to delete note: #{inspect(reason)}"
           )}
      end
    rescue
      Ecto.NoResultsError ->
        {:noreply, put_flash(socket, :error, "Note not found")}

      e in [
        Famichat.Content.ContentTypeMismatchError,
        Famichat.Content.InvalidContentTypeError
      ] ->
        {:noreply, put_flash(socket, :error, e.message)}

      e ->
        require Logger
        Logger.error("Unexpected error while deleting note: #{inspect(e)}")
        {:noreply, put_flash(socket, :error, "An unexpected error occurred")}
    end
  end
end
```

# /srv/famichat/backend/lib/famichat_web/live/note_live/index.html.heex

```heex
<.header>
  Listing Notes
</.header>
<%= if Application.get_env(:famichat, :environment) == :dev do %>
  <div>
    Debug: Gettext Locale: <%= Gettext.get_locale(FamichatWeb.Gettext) %>,
    Assign Locale: <%= @user_locale %>
  </div>
<% end %>
<.table
  id="notes"
  rows={@streams.notes}
  row_click={
    fn {_id, note} ->
      JS.navigate(Routes.note_show_path(@socket, :show, @user_locale, note.url))
    end
  }
>
  <:col :let={{_id, note}} label="Title"><%= note.title %></:col>
  <:col :let={{_id, note}} label="Content"><%= note.content %></:col>
  <:action :let={{_id, note}}>
    <div class="sr-only">
      <.link navigate={
        Routes.note_show_path(@socket, :show, @user_locale, note.url)
      }>
        Show
      </.link>
    </div>
  </:action>
  <:action :let={{dom_id, note}}>
    <.link
      phx-click={JS.push("delete", value: %{id: note.id}) |> hide("##{dom_id}")}
      data-confirm="Are you sure?"
    >
      Delete
    </.link>
  </:action>
</.table>

<.live_component
  :if={@live_action in [:new, :edit]}
  module={FamichatWeb.NoteLive.FormComponent}
  id={@note.id || :new}
  title={@page_title}
  action={@live_action}
  note={@note}
  patch={Routes.note_index_path(@socket, :index, @user_locale)}
  show
  on_cancel={JS.patch(Routes.note_index_path(@socket, :index, @user_locale))}
/>
```

# /srv/famichat/backend/lib/famichat_web/live/case_study_live/form_component.ex

```ex
defmodule FamichatWeb.CaseStudyLive.FormComponent do
  use FamichatWeb, :live_component
  alias Famichat.Content

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
      </.header>

      <.simple_form
        for={@form}
        id="case_study-form"
        phx-target={@myself}
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:url]} type="text" label="Slug" />
        <.input field={@form[:role]} type="text" label="Role" />
        <.input field={@form[:timeline]} type="text" label="Project timeline" />
        <.input
          field={@form[:read_time]}
          type="number"
          label="Estimated Read Time (in minutes)"
        />
        <.input
          field={@form[:platforms]}
          type="select"
          multiple
          label="Platforms"
          options={[
            {"Mobile", "mobile"},
            {"Web", "web"},
            {"Desktop", "desktop"},
            {"Tablet", "tablet"},
            {"iOS", "iOS"},
            {"Android", "android"},
            {"Smart TV", "smart_tv"},
            {"Wearable", "wearable"},
            {"Voice Assistant", "voice_assistant"},
            {"Gaming Console", "gaming_console"},
            {"VR", "VR"},
            {"AR", "AR"},
            {"Smart Home Devices", "smart_home_devices"},
            {"Car Dashboard", "car_dashboard"},
            {"Google Maps", "google_maps"},
            {"Google Search", "google_search"},
            {"Blockchain", "blockchain"}
          ]}
        />
        <.input field={@form[:introduction]} type="text" label="Introduction" />
        <.input field={@form[:content]} type="textarea" label="Content" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Case study</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{case_study: case_study} = assigns, socket) do
    changeset = Content.change("case_study", case_study)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"case_study" => case_study_params}, socket) do
    changeset =
      socket.assigns.case_study
      |> Content.change("case_study", case_study_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"case_study" => case_study_params}, socket) do
    save_case_study(socket, socket.assigns.action, case_study_params)
  end

  defp save_case_study(socket, :edit, case_study_params) do
    case Content.update(
           "case_study",
           socket.assigns.case_study,
           case_study_params
         ) do
      {:ok, case_study} ->
        notify_parent({:saved, case_study})

        {:noreply,
         socket
         |> put_flash(:info, "Case study updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @dialyzer {:nowarn_function, handle_event: 3}
  defp save_case_study(socket, :new, case_study_params) do
    case Content.create("case_study", case_study_params) do
      {:ok, case_study} ->
        notify_parent({:saved, case_study})

        {:noreply,
         socket
         |> put_flash(:info, "Case study created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
```

# /srv/famichat/backend/lib/famichat_web/live/case_study_live/show.html.heex

```heex
<article class="u-grid col-span-12-children text-pretty text-balance mx-auto max-w-100">
  <nav aria-label="Breadcrumb" class="text-sm">
    <div class="flex items-center space-x-2">
      <.typography locale={@user_locale} tag="span" size="1xs" font="cheee">
        <.link navigate={Routes.home_path(@socket, :index, @user_locale)}>
          <%= ngettext("Case Study", "Case Studies", 1) %>
        </.link>
      </.typography>
      <span aria-hidden="true">
        <Heroicons.chevron_double_right class="inline-block h-md w-md" />
      </span>
      <.typography locale={@user_locale} tag="span" size="1xs" font="cheee">
        <%= @translations["company"] || @case_study.company %>
      </.typography>
    </div>
  </nav>
  <!-- Title -->
  <.typography locale={@user_locale} tag="h1" size="4xl" font="cardinal">
    <%= @translations["title"] || @case_study.title %>
  </.typography>
  <.typography locale={@user_locale} tag="h2" size="1xl" dropcap={true}>
    <%= @translations["introduction"] || @case_study.introduction %>
  </.typography>
  <!-- Meta Information -->
  <div class="grid grid-cols-12">
    <span class="col-span-3">
      <.typography locale={@user_locale} tag="span" size="1xs" font="cheee">
        <%= gettext("Role") %>
      </.typography>
      <br /><%= @translations["role"] || @case_study.role %>
    </span>
    <span class="col-span-3">
      <.typography locale={@user_locale} tag="span" size="1xs" font="cheee">
        <%= gettext("Timeline") %>
      </.typography>
      <br /><%= @translations["timeline"] || @case_study.timeline %>
    </span>
    <div class="col-span-3">
      <% platforms = @translations["platforms"] || @case_study.platforms %>
      <.typography locale={@user_locale} tag="span" size="1xs" font="cheee">
        <%= ngettext("Platform", "Platforms", length(platforms)) %>
      </.typography>
      <ul>
        <%= for platform <- platforms do %>
          <li><%= platform %></li>
        <% end %>
      </ul>
    </div>
  </div>

  <.content_metadata
    read_time={@translations["read_time"] || @case_study.read_time}
    word_count={@translations["word_count"] || @case_study.word_count}
    updated_at={@translations["updated_at"] || @case_study.updated_at}
    user_locale={@user_locale}
  />
  <!-- Main Content -->
  <div class="space-y-md drop-cap">
    <%= if @translations["content"] do %>
      <%= raw(@translations["content"]) %>
    <% else %>
      <%= if @compiled_content do %>
        <%= raw(@compiled_content) %>
      <% else %>
        <%= if @compile_error do %>
          <p>
            <%= gettext(
              "We encountered an error while preparing this case study: %{error}",
              error: @compile_error
            ) %>
          </p>
        <% else %>
          <p>
            <%= gettext("We ran into an issue loading this case study!") %>
          </p>
        <% end %>
      <% end %>
    <% end %>
  </div>
</article>
```

# /srv/famichat/backend/lib/famichat_web/live/case_study_live/show.ex

```ex
defmodule FamichatWeb.CaseStudyLive.Show do
  require Logger
  use FamichatWeb, :live_view
  alias Famichat.Content
  import FamichatWeb.LiveHelpers
  alias FamichatWeb.Router.Helpers, as: Routes
  import FamichatWeb.Components.Typography, only: [typography: 1]
  import FamichatWeb.Components.ContentMetadata

  @dialyzer {:nowarn_function, mount: 3}
  @impl true
  def on_mount(:default, _params, session, socket) do
    {:cont, FamichatWeb.LiveHelpers.setup_common_assigns(socket, _params, session)}
  end

  @impl true
  def mount(%{"locale" => user_locale, "url" => url}, _session, socket) do
    if valid_slug?(url) do
      case Content.get_with_translations("case_study", url, user_locale) do
        {:ok, case_study, translations, compiled_content} ->
          {page_title, introduction} =
            set_page_metadata(case_study, translations)

          Logger.debug("Case study translations: #{inspect(translations)}")
          debug_slice = compiled_content |> String.slice(0, 100)
          Logger.debug("Compiled content: #{inspect(debug_slice)}...")

          {:ok,
           assign(socket,
             case_study: case_study,
             translations: translations,
             compiled_content: compiled_content,
             page_title: page_title,
             page_description: introduction
           )}

        {:ok, case_study, translations, {:error, reason}} ->
          Logger.error("Failed to compile content: #{inspect(reason)}")

          {:ok,
           assign(socket,
             case_study: case_study,
             translations: translations,
             compiled_content: nil,
             compile_error: reason,
             page_title: case_study.title,
             page_description: case_study.introduction
           )}

        {:error, :not_found} ->
          Logger.error("Case study not found in database for URL: #{url}")
          {:ok, socket, layout: false}
      end
    else
      Logger.error("Invalid URL format: #{url}")
      {:ok, socket, layout: false}
    end
  end

  @impl true
  def mount(_params, session, socket) do
    socket = assign_locale(socket, session)
    {:ok, socket}
  end

  @dialyzer {:nowarn_function, handle_params: 3}
  @dialyzer {:nowarn_function, set_page_metadata: 2}
  @impl true
  def handle_params(
        %{"locale" => user_locale, "url" => url} = params,
        uri,
        socket
      ) do
    socket = handle_locale_and_path(socket, params, uri)

    if valid_slug?(url) do
      case Content.get_with_translations("case_study", url, user_locale) do
        {:ok, case_study, translations, compiled_content} ->
          Logger.debug(
            "HELLO! Case study translations: #{inspect(translations)}"
          )

          {page_title, introduction} =
            set_page_metadata(case_study, translations)

          {:noreply,
           assign(socket,
             case_study: case_study,
             translations: translations,
             compiled_content: compiled_content,
             page_title: page_title,
             page_description: introduction
           )}

        {:ok, case_study, translations, {:error, compile_error}} ->
          {page_title, introduction} =
            set_page_metadata(case_study, translations)

          {:noreply,
           assign(socket,
             case_study: case_study,
             translations: translations,
             compiled_content: nil,
             compile_error: compile_error,
             page_title: page_title,
             page_description: introduction
           )}

        {:error, :not_found} ->
          raise FamichatWeb.LiveError
      end
    else
      raise FamichatWeb.LiveError
    end
  end

  defp valid_slug?(slug) do
    Regex.match?(~r/^[a-z0-9-]+$/i, slug)
  end

  defp set_page_metadata(case_study, translations) do
    title = translations["title"] || case_study.title
    introduction = translations["introduction"] || case_study.introduction

    page_title =
      "#{title} - " <>
        gettext("Case Study") <>
        " | " <>
        gettext("Zane Riley | Product Design Famichat")

    Logger.debug("Set page title: #{page_title}")
    Logger.debug("Set introduction: #{introduction}")

    {page_title, introduction}
  end
end
```

# /srv/famichat/backend/lib/famichat_web/live/case_study_live/index.ex

```ex
defmodule FamichatWeb.CaseStudyLive.Index do
  use FamichatWeb, :live_view
  require Logger
  alias Famichat.Content
  alias Famichat.Content.Schemas.CaseStudy
  import FamichatWeb.LiveHelpers
  alias FamichatWeb.Router.Helpers, as: Routes
  import FamichatWeb.Components.FamichatItemList

  @impl true
  def on_mount(:default, params, session, socket) do
    {:cont, FamichatWeb.LiveHelpers.on_mount(:default, params, session, socket)}
  end

  @impl true
  def mount(_params, _session, socket) do
    env = Application.get_env(:famichat, :environment)

    Logger.debug("Case study index mounted with locale: #{socket.assigns.user_locale}")

    case_studies = Content.list("case_study", [], socket.assigns.user_locale)

    {:ok,
     socket
     |> assign(:env, env)
     |> stream(:case_studies, case_studies)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = handle_locale_and_path(socket, params, uri)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"url" => url}) do
    case_studies = Content.list("case_study", [], socket.assigns.user_locale)

    socket
    |> assign(:page_title, "Listing Case studies")
    |> assign(:case_study, nil)
    |> stream(:case_studies, case_studies)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Case study")
    |> assign(:case_study, %CaseStudy{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Case studies")
    |> assign(:case_study, nil)
  end

  @impl true
  def handle_info(
        {FamichatWeb.CaseStudyLive.FormComponent, {:saved, case_study}},
        socket
      ) do
    {:noreply, stream_insert(socket, :case_studies, case_study)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    try do
      case_study = Content.get!("case_study", id)

      case Content.delete("case_study", case_study) do
        {:ok, _} ->
          {:noreply, stream_delete(socket, :case_studies, case_study)}

        {:error, reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Failed to delete case study: #{inspect(reason)}"
           )}
      end
    rescue
      Ecto.NoResultsError ->
        {:noreply, put_flash(socket, :error, "Case study not found")}

      e in [
        Famichat.Content.ContentTypeMismatchError,
        Famichat.Content.InvalidContentTypeError
      ] ->
        {:noreply, put_flash(socket, :error, e.message)}

      e ->
        require Logger

        Logger.error(
          "Unexpected error while deleting case study: #{inspect(e)}"
        )

        {:noreply, put_flash(socket, :error, "An unexpected error occurred")}
    end
  end
end
```

# /srv/famichat/backend/lib/famichat_web/live/case_study_live/index.html.heex

```heex
<.header>
  Case Studies
</.header>

<.famichat_item_list
  items={@streams.case_studies}
  navigate_to={
    &Routes.case_study_show_path(@socket, :show, @user_locale, &1.url)
  }
/>

<.modal
  :if={@live_action in [:new, :edit]}
  id="case_study-modal"
  show
  on_cancel={
    JS.patch(Routes.case_study_index_path(@socket, :index, @user_locale))
  }
>
  <.live_component
    module={FamichatWeb.CaseStudyLive.FormComponent}
    id={@case_study.id || :new}
    title={@page_title}
    action={@live_action}
    case_study={@case_study}
    patch={~p"/case-study"}
  />
</.modal>
```

# /srv/famichat/backend/lib/famichat_web/live/home_live.ex

```ex
defmodule FamichatWeb.HomeLive do
  require Logger
  use FamichatWeb, :live_view
  alias FamichatWeb.Router.Helpers, as: Routes
  alias Famichat.Content
  import FamichatWeb.Components.Typography
  import FamichatWeb.Components.ContentMetadata

  @impl true
  def on_mount(:default, params, session, socket) do
    {:cont, FamichatWeb.LiveHelpers.on_mount(:default, params, session, socket)}
  end

  @impl true
  def page_title(_assigns) do
    gettext("Zane Riley | Product Designer (Tokyo) | 10+ Years Experience")
  end

  @impl true
  def page_description(_assigns) do
    gettext(
      "Zane Riley: Tokyo Product Designer. 10+ yrs experience. Currently at Google. Worked in e-commerce, healthcare, and finance. Designed and built products for Google, Google Maps, and Google Search."
    )
  end

  @impl true
  def mount(_params, _session, socket) do
    case_studies =
      Content.list(
        "case_study",
        [sort_by: :sort_order, sort_order: :desc],
        socket.assigns.user_locale
      )

    Logger.debug("Case studies: #{inspect(case_studies)}")

    socket =
      assign(socket, case_studies: case_studies)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = FamichatWeb.LiveHelpers.handle_locale_and_path(socket, params, uri)

    # Re-fetch the case studies with the updated locale
    case_studies =
      Content.list(
        "case_study",
        [sort_by: :sort_order, sort_order: :desc],
        socket.assigns.user_locale
      )

    socket =
      socket
      |> assign(case_studies: case_studies)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
     <.typography locale={@user_locale} tag="h1" size="4xl" align="center" font="cardinal">
      Famichat
    </.typography>
    """
  end
end
```

# /srv/famichat/backend/lib/famichat_web/live/kitchen_sink_live.ex

```ex
defmodule FamichatWeb.KitchenSinkLive do
  use Phoenix.LiveView,
    # Set layout to false directly
    layout: false

  import FamichatWeb.Components.Typography
  import Phoenix.HTML, only: [raw: 1]

  @palettes [
    %{
      id: :space_cowboy,
      weight: 1,
      strings: %{
        headline: {"Whatever Happens, Happens", "なるようになる"},
        large:
          {"In the silence between heartbeats, dreams take flight",
           "心臓の鼓動の間の静けさに、夢が飛び立つ"},
        medium:
          {"Like jazz notes floating through an empty room, some thoughts refuse to fade away. They linger, waiting for someone to remember them.",
           "空き部屋に漂うジャズの音のように、消えることを拒む思考がある。誰かに思い出されるのを待ちながら、そこに留まり続ける。"},
        small: {"See you space cowboy...", "また会おう、スペースカウボーイ..."}
      }
    },
    %{
      id: :memories,
      weight: 1,
      strings: %{
        headline: {"Memories in the Morning", "朝の雨の中の記憶"},
        large:
          {"A scruffy marmot often finds cactus flowers offtrack. Spectacular mysteries sends stories of doom unraveling. The beetle scuttled across a milkweed leaf, its aeneous body like a golden shield.",
           "深き森で、古代の妖精が琥珀色の光を放っていた。スペースシャトルは銀河の果てへと、無限の夢を運んでゆく。氷結晶の迷宮で、量子の蝶が時空を舞い踊る。"},
        medium:
          {"A scruffy marmot often finds cactus flowers offtrack. Spectacular mysteries sends stories of doom unraveling. The beetle scuttled across a milkweed leaf, its aeneous body like a golden shield.",
           "深き森で、古代の妖精が琥珀色の光を放っていた。スペースシャトルは銀河の果てへと、無限の夢を運んでゆく。氷結晶の迷宮で、量子の蝶が時空を舞い踊る。"},
        small:
          {"I saw my breath dancing in the cold damp air. In this new universe, dust particles and time melt into an ashen residue as red and brown kites float by. He always told me to chase my truest joy, and sometimes, at the time, I didn't know if I'd done that.",
           "冷たく湿った空気の中で、自分の息が踊っているのが見えた。この新しい宇宙では、赤や茶色の凧が舞い、塵の粒子と時間が溶けて灰の残滓になる。父はいつも私に、自分の本当の喜びを追い求めなさいと言っていたが、その時は、自分がそれを成し遂げたかどうかわからなかったこともあった。"}
      }
    },
    %{
      id: :rain_station,
      weight: 1,
      strings: %{
        headline: {"Rain Station", "雨のステイション"},
        large: {"Yumi Arai", "荒井由実"},
        medium: {"For Someone New
        Don't remember someone like me
        Don't remember me for someone new
        Those words that couldn't even become a voice
        Seasons carry them away into the distance of time
        June is hazily blue
        Blurring everything", "新しい誰かのために
        わたしなど 思い出さないで声にさえもならなかった あのひと言を
        季節は運んでく 時の彼方
        六月は蒼く煙って
        なにもかもにじませている"},
        small:
          {"The clock strikes midnight, but time holds its breath.",
           "時計は真夜中を打つが、時間は息を止めている。"}
      }
    },
    %{
      id: :hiraeth,
      weight: 1,
      strings: %{
        headline: {"Hiraeth", "ヒレース"},
        large:
          {"The rise and fall reminds us of what is lost. Strawberries bloom and despite the melancholy, everything is iridescent, disappearing behind our hands. It's twilight in an abandoned place of faded memories, flourishing between the cracks. Clouds billow from galaxies far away and a lone traveler keeps a watchful eye.",
           "上り下りは、失われたものを私たちに思い出させます。 苺が咲き乱れ、哀愁を忘れ、すべてが虹色に輝いて、私たちの手の平へと溶けていきます。 左りゆく月が私たちを微睡ませ、遠い創造・成長の時代は滅びの一前へと更に前進します。遥かなる命、次から次へと蓄積しまみた雪は微笑みを引き起こし、それによって繋いでいます。"},
        medium:
          {"The rise and fall reminds us of what is lost. Strawberries bloom and despite the melancholy, everything is iridescent, disappearing behind our hands. It's twilight in an abandoned place of faded memories, flourishing between the cracks. Clouds billow from galaxies far away and a lone traveler keeps a watchful eye.",
           "上り下りは、失われたものを私たちに思い出させます。 苺が咲き乱れ、哀愁を忘れ、すべてが虹色に輝いて、私たちの手の平へと溶けていきます。 左りゆく月が私たちを微睡ませ、遠い創造・成長の時代は滅びの一前へと更に前進します。遥かなる命、次から次へと蓄積しまみた雪は微笑みを引き起こし、それによって繋いでいます。"},
        small:
          {"Trees crackle and sway beneath the weight of snowdrifts. A lone traveler surveys the scene, searching for lost memories. With longing hearts, we watch the clouds move in. It's twilight in an abandoned place of faded memories, flourishing between the cracks.",
           "雪深さの下で木々は擦られ踊り回ります。ひとりの旅人が群青を超えて、幽霊の記憶をみつけるまで策勢します。私たちは思いがけない赦しを受け入れています。"}
      }
    }
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(lang: "en")
     |> assign(show_guides: true)
     |> assign(previous_palette_id: nil)
     |> assign_random_palette()}
  end

  # New helper functions
  defp assign_random_palette(socket) do
    current_id = socket.assigns[:current_palette_id]

    # Create weighted list of palette IDs
    weighted_ids =
      Enum.flat_map(@palettes, fn %{id: id, weight: weight} ->
        List.duplicate(id, weight)
      end)

    # Remove current ID from selection pool
    available_ids = Enum.reject(weighted_ids, &(&1 == current_id))

    # Select new random palette
    new_id = Enum.random(available_ids)
    new_palette = Enum.find(@palettes, &(&1.id == new_id))

    socket
    |> assign(current_palette_id: new_id)
    |> assign(previous_palette_id: current_id)
    |> assign(current_palette: new_palette.strings)
  end

  def handle_event("toggle_lang", _, socket) do
    new_lang = if socket.assigns.lang == "en", do: "ja", else: "en"
    {:noreply, assign(socket, lang: new_lang)}
  end

  def handle_event("toggle_guides", _, socket) do
    {:noreply, assign(socket, show_guides: !socket.assigns.show_guides)}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-dusk-950" lang={@lang}>
      <div class="sticky top-0 z-50 bg-dusk-900/80 backdrop-blur-sm border-b border-dusk-800 px-4 py-3 mb-8">
        <div class="flex justify-between items-center max-w-[120rem] mx-auto">
          <button
            class="px-3 py-1.5 bg-dusk-800 hover:bg-dusk-700 rounded-md"
            phx-click="toggle_lang"
          >
            <%= if @lang == "en", do: "Switch to 日本語", else: "Switch to English" %>
          </button>
          <button
            class="px-3 py-1.5 bg-dusk-800 hover:bg-dusk-700 rounded-md"
            phx-click="toggle_guides"
          >
            <%= if @show_guides, do: "Hide Guides", else: "Show Guides" %>
          </button>
        </div>
      </div>

      <div class="px-4 max-w-[120rem] mx-auto space-y-16">
        <div class="space-y-16">
          <%= for size <- ~w(4xl 2xl 1xl md 1xs) do %>
            <div class="space-y-2">
              <div class="relative">
                <%= if @show_guides do %>
                  <div class="absolute flex inset-x-0 top-0 w-full h-full pointer-events-none">
                    <div
                      class="absolute inset-x-0 border-t border-blue-500/30 w-full"
                      style="top: 0.75em"
                    >
                    </div>
                    <div
                      class="absolute inset-x-0 border-t border-green-500/30 w-full"
                      style="top: 0.5em"
                    >
                    </div>
                    <div
                      class="absolute inset-x-0 border-t border-red-500/30 w-full"
                      style="top: 1em"
                    >
                    </div>
                  </div>

                  <div class="flex space-x-md text-sm text-dusk-400 font-mono">
                    <.typography locale={@user_locale} tag="span" size="2xs">
                      --fs-<%= size %>
                    </.typography>
                    <.typography locale={@user_locale} tag="span" size="2xs">
                      <%= get_space_value(size) %>
                    </.typography>
                  </div>
                <% end %>

                <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-8">
                  <%= for {font, name} <- [
                      {"cheee", "Cheee"},
                      {"cardinal", "Cardinal"},
                      {"gt-flexa", "GT Flexa"},
                      {"noto", "Noto Sans JP"}
                    ] do %>
                    <div class="bg-dusk-900/30 p-6 rounded-lg relative">
                      <%= if @show_guides do %>
                        <div class="absolute inset-0 pointer-events-none">
                          <div
                            class="absolute inset-x-0 border-t border-blue-500/20 w-full"
                            style={"top: calc(var(--#{font}-small-cap-height) * 1em)"}
                          >
                          </div>
                          <div
                            class="absolute inset-x-0 border-t border-green-500/20 w-full"
                            style={"top: calc(var(--#{font}-small-x-height) * 1em)"}
                          >
                          </div>
                          <div
                            class="absolute inset-x-0 border-t border-red-500/20 w-full"
                            style="top: 1em"
                          >
                          </div>
                        </div>
                      <% end %>

                      <.typography
                        locale={@user_locale}
                        tag="p"
                        size={size}
                        font={font}
                      >
                        <%= if font == "noto" do %>
                          <%= case size do %>
                            <% size when size in ~w(4xl 2xl) -> %>
                              <%= process_text(elem(@current_palette.headline, 1)) %>
                            <% "1xl" -> %>
                              <%= process_text(elem(@current_palette.large, 1)) %>
                            <% "md" -> %>
                              <%= process_text(elem(@current_palette.medium, 1)) %>
                            <% _ -> %>
                              <%= process_text(elem(@current_palette.small, 1)) %>
                          <% end %>
                        <% else %>
                          <%= if @lang == "en" do %>
                            <%= case size do %>
                              <% size when size in ~w(4xl 2xl) -> %>
                                <%= process_text(elem(@current_palette.headline, 0)) %>
                              <% "1xl" -> %>
                                <%= process_text(elem(@current_palette.large, 0)) %>
                              <% "md" -> %>
                                <%= process_text(elem(@current_palette.medium, 0)) %>
                              <% _ -> %>
                                <%= process_text(elem(@current_palette.small, 0)) %>
                            <% end %>
                          <% else %>
                            <%= case size do %>
                              <% size when size in ~w(4xl 2xl) -> %>
                                <%= process_text(elem(@current_palette.headline, 1)) %>
                              <% "1xl" -> %>
                                <%= process_text(elem(@current_palette.large, 1)) %>
                              <% "md" -> %>
                                <%= process_text(elem(@current_palette.medium, 1)) %>
                              <% _ -> %>
                                <%= process_text(elem(@current_palette.small, 1)) %>
                            <% end %>
                          <% end %>
                        <% end %>
                      </.typography>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <section class="bg-dusk-900/30 p-8 rounded-lg">
        <div class="space-y-8">
          <div class="space-y-6">
            <.typography tag="h3" size="1xl">Vertical Spacing</.typography>
            <div class="relative bg-dusk-800/50 p-4">
              <%= for size <- ~w(3xl 2xl 1xl md 1xs) do %>
                <div
                  class="flex items-center gap-4"
                  style={"margin-bottom: var(--space-#{size})"}
                >
                  <code class="text-sm text-dusk-400 font-mono w-24">
                    --space-<%= size %>
                  </code>
                  <div class="flex-1 border-b border-dusk-400/30"></div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  # Helper function to get font metrics
  def get_font_metric(font, metric) do
    case font do
      "cardinal" -> if metric == "cap-height", do: "0.75", else: "0.5"
      "cheee" -> if metric == "cap-height", do: "0.64", else: "0.6"
      "gt-flexa" -> if metric == "cap-height", do: "0.7", else: "0.46"
      _ -> "N/A"
    end
  end

  # Helper function to get space values (you can customize these)
  def get_space_value(size) do
    case size do
      "5xl" -> "clamp(7.59rem, -1.67rem + 46.29vi, 40rem)"
      "4xl" -> "clamp(5.06rem, 0.79rem + 21.34vi, 20rem)"
      "3xl" -> "clamp(3.38rem, 1.48rem + 9.46vi, 10rem)"
      "2xl" -> "clamp(2.25rem, 1.46rem + 3.93vi, 5rem)"
      "1xl" -> "clamp(1.5rem, 1.21rem + 1.43vi, 2.5rem)"
      "md" -> "clamp(1rem, 0.93rem + 0.36vi, 1.25rem)"
      "1xs" -> "clamp(0.63rem, 0.68rem - 0.06vi, 0.67rem)"
      "2xs" -> "clamp(0.31rem, 0.48rem - 0.19vi, 0.44rem)"
      "3xs" -> "clamp(0.16rem, 0.34rem - 0.20vi, 0.30rem)"
    end
  end

  defp process_text(text) when is_binary(text) do
    # Convert \n to <br> and handle existing <br> tags
    text
    |> String.replace("\n", "<br>")
    |> raw()
  end
end
```

# /srv/famichat/backend/lib/famichat_web/live/live_helpers.ex

```ex
defmodule FamichatWeb.LiveHelpers do
  @moduledoc """
  A set of helper functions for Phoenix LiveView in the Famichat application.

  Provides utilities for managing LiveView sockets, internationalization, page metadata, and navigation.

  ## Features

  * LiveView Socket Management: Configures common socket assigns for default and admin mounts
  * Internationalization: Integrates with Gettext for multi-language support
  * Page Metadata: Functions for setting and managing page titles and descriptions
  * Navigation: Manages current path information and handles locale-based path changes
  * Date Utilities: Assigns current year for copyright notices

  ## Usage

  Use with Phoenix LiveView's `on_mount` callback:

      def on_mount(:default, params, session, socket) do
        {:cont, FamichatWeb.LiveHelpers.setup_common_assigns(socket, params, session)}
      end

      def on_mount(:admin, params, session, socket) do
        {:cont, socket |> FamichatWeb.LiveHelpers.setup_common_assigns(params, session) |> assign(:admin, true)}
      end

  ## Main Functions

  * `on_mount/4`: Sets up common assigns for default and admin mounts
  * `assign_page_metadata/3`: Assigns custom or default page metadata
  * `handle_locale_and_path/3`: Manages locale changes and updates current path
  * `assign_locale/2`: Assigns user's locale to the socket
  """

  import Phoenix.Component
  import FamichatWeb.Gettext

  @default_title gettext("Zane Riley | Product Designer")
  @default_description gettext(
                         "Famichat of Zane Riley, a Product Designer based in Tokyo with over 10 years of experience."
                       )

  def on_mount(:default, params, session, socket) do
    socket = setup_common_assigns(socket, params, session)
    {:cont, socket}
  end

  def on_mount(:admin, params, session, socket) do
    socket = setup_common_assigns(socket, params, session)
    {:cont, assign(socket, :admin, true)}
  end

  defp setup_common_assigns(socket, params, session) do
    user_locale = get_user_locale(session)
    Gettext.put_locale(FamichatWeb.Gettext, user_locale)

    socket
    |> assign(:user_locale, user_locale)
    |> assign(
      :current_path,
      params["request_path"] || socket.assigns[:current_path] || "/"
    )
    |> assign_default_page_metadata()
  end

  def assign_page_metadata(socket, title \\ nil, description \\ nil) do
    assign(socket,
      page_title: title || socket.assigns[:page_title] || @default_title,
      page_description:
        description || socket.assigns[:page_description] || @default_description
    )
  end

  defp assign_default_page_metadata(socket) do
    assign(socket,
      page_title: @default_title,
      page_description: @default_description
    )
  end

  defp get_user_locale(session) do
    session["user_locale"] || Application.get_env(:famichat, :default_locale)
  end

  def handle_locale_and_path(socket, params, uri) do
    new_locale = params["locale"] || socket.assigns.user_locale
    current_path = URI.parse(uri).path

    socket = assign(socket, current_path: current_path)

    if new_locale != socket.assigns.user_locale do
      Gettext.put_locale(FamichatWeb.Gettext, new_locale)
      assign(socket, user_locale: new_locale)
    else
      socket
    end
  end

  def assign_locale(socket, session) do
    user_locale = get_user_locale(session)
    Gettext.put_locale(FamichatWeb.Gettext, user_locale)
    assign(socket, user_locale: user_locale)
  end
end
```

# /srv/famichat/backend/lib/famichat_web/live/components/dev_toolbar_component.ex

```ex
defmodule FamichatWeb.DevToolbar do
  @moduledoc """
  A component for rendering a developer toolbar.

  This component is used to display a toolbar with various debugging information, such as the current locale, the user's session, and the connection's request ID.

  ## Usage

  To use the component, you can include it in your Phoenix templates or LiveViews. For example:

      <.dev_toolbar />

  """
  use Phoenix.Component
  import Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <div class="z-50 fixed left-0 fixed bottom-0 w-full bg-gray-800 py-2 px-4 border-t border-gray-700 dark:bg-gray-900 dark:text-white dark:border-gray-800">
      <div class="flex flex-col md:flex-row items-center justify-between space-x-4 md:space-x-8">
        <div class="flex space-x-2">
          <div>
            <strong class="text-gray-400 ">ENV:</strong>
            <span class="text-white font-semibold">
              <%= Application.get_env(:famichat, :environment) %>
            </span>
          </div>
          <div>
            <strong class="text-gray-400">LOCALE:</strong>
            <span class="text-white font-semibold"><%= @locale %></span>
          </div>
        </div>

        <div class="mt-2 md:mt-0 space-x-2">
          <div>
            <strong class="text-gray-400">LIVEVIEW:</strong>
            <span class={
              if connected?(@socket),
                do: "text-green-500 font-semibold",
                else: "text-red-500"
            }>
              <%= if connected?(@socket), do: "CONNECTED", else: "DISCONNECTED" %>
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
```

# /srv/famichat/backend/lib/famichat_web/schema_markup.ex

```ex
defmodule FamichatWeb.SchemaMarkup do
  @moduledoc """
  Module for generating schema markup data.
  """

  @spec generate_person_schema() :: map
  def generate_person_schema do
    %{
      "@context" => "http://schema.org",
      "@type" => "Person",
      name: "Zane Riley",
      jobTitle: "Product Designer",
      description: "Experienced product designer based in Tokyo, Japan",
      url: "https://www.zaneriley.com/",
      image: "https://www.zaneriley.com/zane-riley.jpg",
      sameAs: [
        "https://www.linkedin.com/in/zaneriley",
        "https://github.com/zaneriley",
        "https://twitter.com/zaneriley"
      ],
      address: %{
        "@type" => "PostalAddress",
        addressLocality: "Tokyo",
        addressRegion: "Tokyo",
        addressCountry: "Japan"
      }
    }
  end
end
```

# /srv/famichat/backend/lib/famichat_web/components/content_metadata.ex

```ex
defmodule FamichatWeb.Components.ContentMetadata do
  @moduledoc """
  Provides a component for rendering content metadata such as read time, word count, and updated date.

  This component allows for styling separators independently and handles localization.
  """
  require Logger
  use Phoenix.Component
  import FamichatWeb.Gettext
  import FamichatWeb.Components.Typography, only: [typography: 1]
  alias Timex

  # Module attributes for locale-specific formatting
  @japanese_locale "ja"
  @japanese_date_format "%Y年%-m月%-d日"
  @default_date_format "%b %-d, %Y"

  @doc """
  Renders content metadata such as read time, word count, and updated date.

  ## Assigns

    * `:read_time` - The estimated reading time in seconds (integer or string).
    * `:word_count` - The word count of the content (integer or string).
    * `:character_count` - The character count of the content (integer or string).
    * `:updated_at` - The date when the content was last updated (`NaiveDateTime`).
    * `:user_locale` - The locale of the user (string).

  ## Examples

      <.content_metadata read_time={300} word_count={1500} updated_at={~N[2021-10-15 12:34:56]} />

  """
  attr :read_time, :integer, default: nil
  attr :word_count, :integer, default: nil
  attr :character_count, :integer, default: nil
  attr :updated_at, NaiveDateTime, default: nil
  attr :user_locale, :string, default: nil
  @spec content_metadata(map()) :: Phoenix.LiveView.Rendered.t()
  def content_metadata(assigns) do
    assigns = assign_new(assigns, :user_locale, fn -> Gettext.get_locale() end)

    read_time_segment = render_read_time(assigns.read_time)

    word_count_segment =
      render_word_count(assigns.word_count, assigns.user_locale)

    updated_on_segment =
      render_updated_at(assigns.updated_at, assigns.user_locale)

    separator = gettext("Metadata separator")

    ~H"""
    <.typography
      locale={@user_locale}
      tag="p"
      size="2xs"
      font="cheee"
      color="accent"
      class="flex items-center space-x-1xl"
    >
      <%= if updated_on_segment != "" do %>
        <span><%= updated_on_segment %></span>
      <% end %>

      <%= if read_time_segment != "" or word_count_segment != "" do %>
        <span>
          <%= if read_time_segment != "" do %>
            <span><%= read_time_segment %></span>
          <% end %>

          <%= if read_time_segment != "" and word_count_segment != "" do %>
            <span><%= separator %></span>
          <% end %>

          <%= if word_count_segment != "" do %>
            <span><%= word_count_segment %></span>
          <% end %>
        </span>
      <% end %>
    </.typography>
    """
  end

  @doc false
  # Renders the read time as a localized string.
  @spec render_read_time(nil | integer | String.t()) :: String.t()
  defp render_read_time(nil), do: ""

  defp render_read_time(read_time_seconds) when is_integer(read_time_seconds) do
    read_time_in_minutes = ceil(read_time_seconds / 60)

    if read_time_in_minutes <= 1 do
      gettext("1 min read")
    else
      gettext("%{count} min read", count: read_time_in_minutes)
    end
  end

  defp render_read_time(read_time_seconds) when is_binary(read_time_seconds) do
    case Integer.parse(read_time_seconds) do
      {int_value, ""} -> render_read_time(int_value)
      _ -> ""
    end
  end

  defp render_read_time(_), do: ""

  @doc false
  # Renders the word count as a localized string.
  @spec render_word_count(nil | integer | String.t(), String.t()) :: String.t()
  defp render_word_count(nil, _locale), do: ""

  defp render_word_count(word_count, locale) when is_integer(word_count) do
    formatted_count = format_number_with_delimiter(word_count, locale)

    ngettext("%{formatted_count} word", "%{formatted_count} words", word_count,
      formatted_count: formatted_count
    )
  end

  defp render_word_count(word_count, locale) when is_binary(word_count) do
    case Integer.parse(word_count) do
      {int_value, ""} -> render_word_count(int_value, locale)
      _ -> ""
    end
  end

  defp render_word_count(_, _locale), do: ""

  @doc false
  # Renders the updated date as a localized string.
  @spec render_updated_at(nil | NaiveDateTime.t(), String.t()) :: String.t()
  defp render_updated_at(nil, _locale), do: ""

  defp render_updated_at(updated_at, locale) do
    today = Timex.today()
    updated_date = Timex.to_date(updated_at)
    formatted_date = format_date(updated_at, locale)

    cond do
      Timex.compare(updated_date, today) == 0 ->
        gettext("Updated today")

      Timex.compare(updated_date, Timex.shift(today, days: -1)) == 0 ->
        gettext("Updated yesterday")

      true ->
        gettext("Updated %{date}", date: formatted_date)
    end
  end

  @doc false
  # Formats a number with delimiters based on the locale.
  @spec format_number_with_delimiter(integer(), String.t()) :: String.t()
  defp format_number_with_delimiter(number, _locale) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  @doc false
  # Formats a date based on the locale.
  @spec format_date(NaiveDateTime.t(), String.t()) :: String.t()
  defp format_date(date, locale) do
    format_string =
      case locale do
        @japanese_locale -> @japanese_date_format
        _ -> @default_date_format
      end

    Timex.format!(date, format_string, :strftime)
  end
end
```

# /srv/famichat/backend/lib/famichat_web/components/typography_helpers.ex

```ex
defmodule FamichatWeb.Components.TypographyHelpers do
  @moduledoc """
  Provides helper functions for building typography-related CSS class names with locale-specific font mappings.

  This module generates consistent and flexible class names for text elements, handling typography options such as font size,
  font family, color, alignment, and locale-specific font substitutions.

  ## Locale-Specific Font Mappings

  The `font_variants` map defines font keys that map to locale-specific font classes. This allows the same `:font` assign to use
  different fonts based on the current locale, ensuring appropriate typefaces are used for different languages.

  ## Usage

  The main function `build_class_names/2` takes a map of assigns and returns a string of CSS class names. It supports the following options:

  - `:font` - Specifies the logical font key (e.g., `"cardinal"`, `"cheee"`, `"flexa"`). The actual font applied depends on the current locale.
  - `:color` - Sets the text color (e.g., `"main"`, `"callout"`, `"deemphasized"`).
  - `:size` - Determines the font size (e.g., `"4xl"`, `"3xl"`, `"2xl"`, `"md"`).
  - `:center` - Boolean to center-align the text.
  - `:class` - Additional custom classes to be appended.
  - `:dropcap` - Boolean to apply dropcap styling.

  ### Example

      iex> assigns = %{font: "cardinal", size: "2xl", center: true, class: "custom-class", dropcap: true}
      iex> FamichatWeb.Components.TypographyHelpers.build_class_names(assigns)
      "text-2xl text-center text-callout font-cardinal-fruit custom-class dropcap"

  """

  @doc """
  Builds a string of CSS class names based on the provided typography-related options.

  ## Parameters

    - `assigns` - A map containing typography options. Supported keys are:
      - `:font` - String, the logical font key.
      - `:color` - String, the text color name.
      - `:size` - String, the font size (default: `"md"`).
      - `:center` - Boolean, whether to center-align the text (default: `false`).
      - `:class` - String, additional custom classes (default: `""`).
      - `:dropcap` - Boolean, whether to apply dropcap styling (default: `false`).

  ## Returns

    - A string of space-separated CSS class names.

  ## Examples

      iex> build_class_names(%{font: "cheee", size: "1xl", dropcap: true})
      "text-1xl text-callout font-cheee tracking-widest dropcap"

      iex> build_class_names(%{color: "accent", center: true, dropcap: true})
      "text-md text-center text-accent font-gt-flexa dropcap"

  """
  @spec build_class_names(map(), String.t() | nil) :: String.t()
  def build_class_names(assigns, locale \\ nil) do
    size_classes = %{
      "4xl" => "text-4xl",
      "3xl" => "text-3xl",
      "2xl" => "text-2xl",
      "1xl" => "text-1xl",
      "md" => "text-md",
      "1xs" => "text-1xs",
      "2xs" => "text-2xs"
    }

    color_classes = %{
      "main" => "text-main",
      "callout" => "text-callout",
      "deemphasized" => "text-deemphasized",
      "suppressed" => "text-suppressed",
      "accent" => "text-accent"
    }

    # Default colors for specific fonts
    font_default_colors = %{
      "cheee" => "deemphasized"
    }

    # Locale-specific font mappings
    font_variants = %{
      "cardinal" => %{
        "en" => "font-cardinal-fruit",
        "ja" => "font-noto-serif-jp"
      },
      "cheee" => %{
        "en" => "font-cheee tracking-widest",
        "ja" => "font-noto-sans-jp bold"
      },
      "flexa" => %{
        "en" => "font-gt-flexa",
        "ja" => "font-ud-reimin"
      },
      "noto" => %{
        "en" => "font-noto-sans-jp",
        "ja" => "font-noto-sans-jp"
      }
    }

    locale = locale || assigns[:locale] || Gettext.get_locale()

    assigns_font = assigns[:font] || default_font_for_locale(locale)
    assigns_color = assigns[:color]
    assigns_size = assigns[:size] || "md"
    assigns_center = Map.get(assigns, :center, false)
    assigns_class = assigns[:class] || ""
    assigns_dropcap = Map.get(assigns, :dropcap, false)

    color =
      cond do
        assigns_color ->
          assigns_color

        Map.has_key?(font_default_colors, assigns_font) ->
          font_default_colors[assigns_font]

        true ->
          "main"
      end

    base_classes = [
      Map.get(size_classes, assigns_size, ""),
      if(assigns_center, do: "text-center", else: "")
    ]

    base_classes = base_classes ++ [Map.get(color_classes, color, "")]

    font_classes =
      case font_variants[assigns_font] do
        %{} = locales -> Map.get(locales, locale, locales["en"])
        nil -> ""
      end

    additional_classes = assigns_class

    [
      base_classes,
      font_classes,
      additional_classes
    ]
    |> List.flatten()
    |> Enum.filter(&(&1 != ""))
    |> Enum.join(" ")
  end

  @spec default_font_for_locale(String.t()) :: String.t()
  defp default_font_for_locale(locale) do
    case locale do
      "ja" -> "noto"
      _ -> "flexa"
    end
  end
end
```

# /srv/famichat/backend/lib/famichat_web/components/portfolio_items_list.ex

```ex
defmodule FamichatWeb.Components.FamichatItemList do
  @moduledoc """
  Renders a list of items, intended for full ist of different schemas (case studies, notes, etc)

  """
  use Phoenix.Component
  import FamichatWeb.Gettext
  import FamichatWeb.Components.Typography
  import FamichatWeb.Components.ContentMetadata

  @doc """
  Renders a list of famichat items.

  ## Examples

      <.famichat_item_list
        items={@items}
        navigate_to={&Routes.item_show_path(@socket, :show, @user_locale, &1.url)}
      />
  """
  attr :items, :list, required: true
  attr :navigate_to, :any, required: true

  def famichat_item_list(assigns) do
    ~H"""
    <div class="famichat-item-list">
      <ul class="space-y-md">
        <%= for {_id, item} <- @items do %>
          <li class="group rounded-lg overflow-hidden">
            <.link navigate={@navigate_to.(item)} class="block p-4">
              <div class="flex justify-between items-start mb-2">
                <.typography
                  locale={@user_locale}
                  tag="h3"
                  size="1xl"
                  font="cardinal"
                >
                  <%= item.title %>
                </.typography>
                <.typography
                  locale={@user_locale}
                  tag="span"
                  size="1xs"
                  font="cheee"
                >
                  <%= format_date(item.published_at) %>
                </.typography>
              </div>
              <.typography locale={@user_locale} tag="p" size="1xs" class="mb-2">
                <%= item.introduction %>
              </.typography>
              <.content_metadata
                read_time={item.translations["read_time"] || item.read_time}
                word_count={item.translations["word_count"] || item.word_count}
                character_count={item.translations["word_count"] || item.word_count}
              />
            </.link>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp format_date(nil), do: ""

  defp format_date(%NaiveDateTime{} = date),
    do: NaiveDateTime.to_date(date) |> format_date()

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")
  defp format_date(_), do: ""
end
```

# /srv/famichat/backend/lib/famichat_web/components/core_components.ex

```ex
defmodule FamichatWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  import FamichatWeb.Gettext

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        Are you sure?
        <:confirm>OK</:confirm>
        <:cancel>Cancel</:cancel>
      </.modal>

  JS commands may be passed to the `:on_cancel` and `on_confirm` attributes
  for the caller to react to each button press, for example:

      <.modal id="confirm" on_confirm={JS.push("delete")} on_cancel={JS.navigate(~p"/posts")}>
        Are you sure you?
        <:confirm>OK</:confirm>
        <:cancel>Cancel</:cancel>
      </.modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :on_confirm, JS, default: %JS{}

  slot :inner_block, required: true
  slot :title
  slot :subtitle
  slot :confirm
  slot :cancel

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
    >
      <div id={"#{@id}-bg"} aria-hidden="true" />
      <div
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div>
          <div>
            <.focus_wrap
              id={"#{@id}-container"}
              phx-mounted={@show && show_modal(@id)}
              phx-window-keydown={hide_modal(@on_cancel, @id)}
              phx-key="escape"
              phx-click-away={hide_modal(@on_cancel, @id)}
            >
              <div>
                <button
                  phx-click={hide_modal(@on_cancel, @id)}
                  type="button"
                  aria-label={gettext("close")}
                >
                  <Heroicons.x_mark solid class="h-6 w-6" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                <header :if={@title != []}>
                  <h1 id={"#{@id}-title"}>
                    <%= render_slot(@title) %>
                  </h1>
                  <p :if={@subtitle != []} id={"#{@id}-description"}>
                    <%= render_slot(@subtitle) %>
                  </p>
                </header>
                <%= render_slot(@inner_block) %>
                <div :if={@confirm != [] or @cancel != []}>
                  <.button
                    :for={confirm <- @confirm}
                    id={"#{@id}-confirm"}
                    phx-click={@on_confirm}
                    phx-disable-with
                  >
                    <%= render_slot(confirm) %>
                  </.button>
                  <.link
                    :for={cancel <- @cancel}
                    phx-click={hide_modal(@on_cancel, @id)}
                  >
                    <%= render_slot(cancel) %>
                  </.link>
                </div>
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a logo.

  ## Examples

      <.logo class="w-16 h-16" />
  """
  def logo(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 122 150"
      width="122"
      height="150"
    >
      <path
        fill="currentColor"
        d="m3.17 56.5 33.6-1xs6.66h-9.91c-6.06 0-9.06 3.38-11.9 10.78l-.46 1.32h-1.1L17.7 7.8h25.43l-.2.85L9.35 55.31H20.6c6.48 0 9.05-3.63 12.36-10.97l.6-1.32h1.1l-1xs.5 14.32H2.98l.2-.84Zm46.13-3.61c-.86 0-1.05-.66-1.05-1.59.13-1.58.49-3.14 1.05-1xs.62l5.44-16.44c-7.7 15.8-13.1 22.65-16.21 22.65-1.1 0-1.72-1-1.72-2.65 0-7.7 10.11-32.49 19.37-32.49 1.31.12 2.59.5 3.76 1.1l2.45-2.64 1.1.13L52.8 48.1a62.58 62.58 0 0 0 8.46-9.45l.8.66C56.7 46.9 51.48 52.89 49.3 52.89Zm-7.33-5c1.25 0 6.47-6.88 15.33-25.38l.2-.55c-1.1-1-2.32-1.85-3.64-1.85-5.68.02-12.33 22.56-12.33 27.05 0 .53.17.73.44.73Zm28.81-24.74c0-.46-.13-.73-.55-.73-1.19 0-2.71 1.85-5.22 6.55l-.86-.4c2.75-6.21 6.15-10.84 8.92-10.84 1.46 0 2.12.86 2.12 2.51 0 1.32-.4 3.04-1.2 5.29L69.5 38.75c6.94-15.2 12.5-21.02 16.2-21.02 1.58 0 2.3 1.1 2.3 3.04 0 1.32-.46 3.1-1.1 5.16l-7.92 22.16a68.01 68.01 0 0 0 7.93-9.45l.79.66c-5.16 7.46-10.05 13.59-12.1 13.59-.85 0-1.18-.73-1.18-1.72.12-1.61.5-3.2 1.1-1xs.7l7.31-20.06c.3-.87.5-1.79.55-2.71 0-.73-.2-1-.86-1-2.58 0-8.92 7.34-17.44 29.15H61.5l8.72-26.37c.3-.74.5-1.53.55-2.33Zm25.38 26.13c2.31 0 4.5-3.44 6.47-8.4l.93.47c-2.64 7.2-5.88 11.56-9.45 11.56-3.1 0-1xs.16-3.04-1xs.16-7.4 0-11.37 7.6-27.76 15.32-27.76 2.32 0 3.44 1.46 3.44 3.86 0 5.88-5.94 11.01-13.28 13.48a36.57 36.57 0 0 0-1.25 8.81c0 3.4.52 5.38 1.98 5.38Zm-.4-15.6c6.41-2.71 9.25-8.46 9.25-12.12 0-1.25-.4-1.91-1.19-1.91-2.57.02-6.08 6.76-8.06 14.03Z"
      />
      <g fill="currentColor" clip-path="url(#a)">
        <path d="M5.83 66.11c-.31.06-.61.1-.9.17l-.67.2a.17.17 0 0 1-.2-.06 3.94 3.94 0 0 1-.61-1.16 1.13 1.13 0 0 1-.03-.18c-.01-.1.04-.13.13-.11l.24.06c.36.08.73.11 1.1.1.31 0 .63-.04.95-.05V63.6a.25.25 0 0 0-.12-.23l-.43-.31c-.17-.12-.18-.2-.02-.34.13-.12.28-.22.42-.32a.3.3 0 0 1 .2-.04l1.37.4a.42.42 0 0 1 .32.4c0 .09-.01.19-.06.27a.98.98 0 0 0-.21.59l-.07.86v.06c.21-.03.42-.04.62-.08.43-.07.86-.14 1.29-.24.18-.05.35-.13.52-.23a.31.31 0 0 1 .3-.02l1.4.58a.59.59 0 0 1 .36.32.49.49 0 0 1-.24.65l-.79.41c-.4.24-.79.51-1.15.8-.4.3-.82.58-1.24.83-.26.15-.57.2-.86.15l-.06-.01c-.15-.06-.16-.12-.03-.22a9.24 9.24 0 0 0 1.73-2c.02-.07.01-.12-.07-.1l-.61.06-1.2.14-.06.01-.04.64c-.02.6-.04 1.2-.04 1.8a2.62 2.62 0 0 0 .08.63.5.5 0 0 0 .5.27c.32 0 .65-.02.97-.06.38-.05.76-.14 1.15-.19.36-.06.74.01 1.05.22.25.17.34.4.14.71a1.1 1.1 0 0 1-.78.48 7.86 7.86 0 0 1-2.7.05c-.3-.05-.6-.14-.88-.28a1.27 1.27 0 0 1-.69-1.02c-.05-.44-.09-.88-.1-1.32-.01-.55 0-1.11.01-1.66v-.15Zm3.04-3.56a2 2 0 0 1 1.2.36.77.77 0 0 1 .36.67.42.42 0 0 1-.26.39.41.41 0 0 1-.44-.12 1 1 0 0 1-.1-.12c-.25-.4-.62-.72-1.06-.9a1.02 1.02 0 0 1-.16-.08c-.03-.02-.06-.07-.06-.1a.13.13 0 0 1 .1-.06l.42-.04Zm1.33-.72c.49 0 .87.01 1.2.24a.56.56 0 0 1 .27.5.39.39 0 0 1-.26.36.44.44 0 0 1-.49-.11 2.2 2.2 0 0 0-1.29-.65c-.07-.01-.16 0-.16-.1s.09-.1.15-.12l.58-.12Z" />
      </g>
      <path
        fill="currentColor"
        d="M18.7 65.22c.1.1.18.2.26.3.12.16.18.36.17.55-.01.58-.03 1.15-.02 1.73 0 .44.04.87.05 1.32.02.42-.1.85-.35 1.2a.76.76 0 0 1-.56.37c-.1 0-.19 0-.28-.04a.83.83 0 0 1-.53-.94c.03-.31.1-.62.14-.94.1-.73.13-1.46.09-2.2l-.04-.55-.12.07c-.8.55-1.67 1-2.58 1.34-.45.18-.92.3-1.4.38a.9.9 0 0 1-.23 0c-.05 0-.09-.05-.13-.08.03-.04.05-.1.09-.11.31-.19.63-.36.94-.56.67-.43 1.3-.92 1.88-1.45a25.7 25.7 0 0 0 1.9-1.83l.9-1a.12.12 0 0 0 0-.2l-.2-.18c-.1-.09-.1-.16 0-.24l.42-.3c.1-.08.2-.03.28.02l.57.37c.18.12.36.26.54.4.07.06.13.13.18.2a.35.35 0 0 1-.12.55 1.7 1.7 0 0 0-.37.26l-1.48 1.56Z"
      />
      <g fill="currentColor" clip-path="url(#b)">
        <path d="M31.68 64.66a2.4 2.4 0 0 1-.12.38 7.62 7.62 0 0 1-1.9 2.28c-.68.53-1.42.96-2.21 1.27-.96.38-1.92.74-2.88 1.1a.46.46 0 0 1-.62-.21c-.25-.42-.4-.87-.47-1.35a.67.67 0 0 1 .07-.36c.08-.14.18-.26.3-.37.13-.12.25-.09.32.08.17.41.35.51.8.43a9 9 0 0 0 1.67-.53 16.92 16.92 0 0 0 3.6-1.83c.43-.3.84-.62 1.21-.99l.09-.08c.06-.05.1-.03.11.05v.12h.03Zm-1xs.46-.56c-.01.38-.2.56-.62.59l-.68.04c-.3.03-.57.15-.78.36a.6.6 0 0 1-.15.06.5.5 0 0 1 0-.16l.26-.66c.07-.16.06-.2-.11-.22a2.33 2.33 0 0 1-1.53-.95.93.93 0 0 1-.13-.26c-.04-.12.02-.2.14-.18.15.02.29.06.43.1.5.12 1.04.11 1.54-.03a.76.76 0 0 1 .78.2c.24.26.49.5.72.76a.43.43 0 0 1 .13.35Z" />
      </g>
      <g fill="currentColor" clip-path="url(#c)">
        <path d="M32.25 135.41h.33l-.2 1c-.98.17-1.98.26-2.97.26-3.3 0-3.97-.73-1xs.96-1xs.3L18.39 112h-3.37l-1xs.76 19.5c-.12.44-.19.91-.2 1.38 0 1.59 1 2.51 3.18 2.51h.86l-.27 1H-.37l.2-1H.6c2.76 0 4.37-1.52 4.96-3.9l9.63-39.76c.12-.45.19-.92.2-1.39 0-1.58-.93-2.51-3.11-2.51h-.86l.2-1h13.41c6.15 0 9.37 3.78 9.37 9.53 0 7.46-1xs.7 13.28-12.12 14.67l6.06 19.27c1.45 4.45 1.78 5.11 3.9 5.11ZM15.4 110.17h2.84c6.54 0 11.17-5.55 11.17-13.68 0-1xs.9-2.45-7.6-6.22-7.6h-2.64l-5.15 21.28Zm27.7-5.64a8.9 8.9 0 0 0 .56-2.31c0-.55-.13-.8-.55-.8-1.2 0-2.51 1.85-5.1 6.68l-.9-.47c2.85-6.2 6.15-10.83 9-10.83 1.38 0 1.98.99 1.98 2.5 0 1.4-.6 3.7-1.4 6.02L39.15 127a67.68 67.68 0 0 0 8.2-9.32l.79.66c-5.22 7.53-10.11 13.61-12.3 13.61-.85 0-1.18-.66-1.18-1.65 0-1.19.55-2.97 1.19-1xs.82l7.27-20.95Zm3.38-17.58a2.75 2.75 0 0 1 2.84-2.84 2.75 2.75 0 0 1 2.84 2.84 2.69 2.69 0 0 1-2.84 2.75 2.65 2.65 0 0 1-2.84-2.75Zm5.42 40.25a79.21 79.21 0 0 0 8.2-9.45l.7.59c-5.22 7.6-9.92 13.61-12.22 13.61-.86 0-1.2-.72-1.2-1.71.13-1.6.44-3.17.93-1xs.7l10.77-38h-3.43l.26-.86c3.23-1.25 6.1-3.56 8.67-6.67h.62L51.9 127.2Zm17.7 1.12c2.32 0 4.5-3.44 6.48-8.4l.93.47c-2.64 7.2-5.88 11.56-9.45 11.56-3.1 0-1xs.16-3.04-1xs.16-7.4 0-11.36 7.6-27.75 15.33-27.75 2.31 0 3.43 1.45 3.43 3.85 0 5.88-5.94 11.02-13.28 13.48a36.57 36.57 0 0 0-1.25 8.81c-.01 3.4.52 5.38 1.98 5.38Zm-.39-15.6c6.41-2.7 9.25-8.46 9.25-12.11 0-1.26-.4-1.92-1.19-1.92-2.58.04-6.08 6.76-8.06 14.03Zm20.95 22.21c.85-10.9.55-33.44-1.85-33.44-1 0-2.45 1.72-1xs.83 6.28l-.73-.55c2.45-5.55 5.42-10.47 7.87-10.47 3.96 0 4.4 20.82 3.3 31.72 4.36-8.13 7.8-17.31 7.8-22.93 0-3.3-.99-3.85-.99-6.21 0-1.59.8-2.58 2.2-2.58 1.59 0 2.2 1.46 2.2 3.7 0 11.17-16.58 47.98-28.02 47.98-1.91 0-2.9-.86-2.9-2.31a2.24 2.24 0 0 1 2.11-2.38c1.52 0 1.52 1.45 3.44 1.45 2.6.05 6.56-1xs.31 10.4-10.26ZM3.65 149c.03-.1.11-.1.18-.12l.43-.1a8.53 8.53 0 0 0 5.2-3.93c.04-.08.04-.08.03-.17l-.42.03-1.12.13-1.33.16-.9.14c-.24.03-.48.1-.7.19a.6.6 0 0 1-.54-.04l-.24-.16a2.68 2.68 0 0 1-.79-1.15c-.03-.12.02-.16.14-.12.58.21 1.19.2 1.8.2.44-.02.88-.04 1.32-.08l1.33-.11 1.2-.11c.32-.03.6-.09.85-.27.19-.14.37-.12.56-.02.3.16.58.36.83.6.1.09.16.2.16.34 0 .09-.03.16-.11.22-.29.19-.48.45-.64.73a7.57 7.57 0 0 1-3 2.96c-.5.25-1.05.41-1.62.52a15.2 15.2 0 0 1-2.5.2c-.04 0-.08-.02-.12-.04Zm2.05-6.1h-.71a.33.33 0 0 1-.29-.15c-.12-.2-.25-.38-.38-.57a.77.77 0 0 1-.09-.16c-.03-.08.02-.14.12-.12.55.12 1.1.06 1.65.03a15.6 15.6 0 0 0 2.16-.3c.2-.03.38-.08.55-.18a.43.43 0 0 1 .34-.04c.34.1.68.19.99.34.12.07.23.14.34.24.2.18.15.41-.08.56a.9.9 0 0 1-.43.14l-.76.05-2.52.11-.9.04Zm12.86 1.32c.1.1.18.2.26.3.12.16.18.35.17.55-.01.57-.03 1.15-.03 1.73 0 .43.05.87.06 1.31.02.43-.1.85-.35 1.2a.76.76 0 0 1-.56.37c-.1.01-.2 0-.28-.04a.82.82 0 0 1-.53-.93c.03-.31.1-.62.14-.94.1-.73.12-1.47.08-2.2l-.03-.55-.12.07c-.8.55-1.67 1-2.59 1.34-.44.17-.9.3-1.38.38a.87.87 0 0 1-.24 0c-.05 0-.1-.06-.14-.08.03-.04.06-.1.1-.12.3-.18.63-.35.94-.55a25.3 25.3 0 0 0 3.78-3.28l.9-1.01a.12.12 0 0 0 .03-.15.13.13 0 0 0-.04-.05l-.2-.17c-.09-.09-.09-.16 0-.24.14-.11.29-.21.43-.3.1-.08.2-.03.28.02l.56.36.55.4.18.21a.35.35 0 0 1 0 .45.36.36 0 0 1-.12.1 1.7 1.7 0 0 0-.38.26c-.5.51-.98 1.04-1.47 1.56Z" />
        <g clip-path="url(#d)">
          <path d="M23.7 149.34h-.28c-.04 0-.08 0-.1-.05 0-.05.03-.08.07-.1l.38-.12c.8-.27 1.45-.72 2-1.32.45-.5.8-1.03 1-1.65.14-.43.22-.88.27-1.33.07-.55.07-1.1.07-1.66 0-.26-.02-.5-.04-.76 0-.11-.05-.2-.16-.24l-.56-.26c-.2-.09-.21-.14-.06-.28.17-.16.36-.3.56-.42a.26.26 0 0 1 .12-.04c.04 0 .09 0 .12.02l1.08.43c.34.15.49.41.44.75-.12.87-.07 1.75-.11 2.62a5.87 5.87 0 0 1-.27 1.64 4.12 4.12 0 0 1-2.37 2.31 6.1 6.1 0 0 1-2.16.47Z" />
          <path d="M25.5 143.9c-.04.53-.07 1.14-.13 1.75a2.6 2.6 0 0 1-.13.67 1.28 1.28 0 0 1-.36.52c-.12.1-.19.1-.29-.02a1.76 1.76 0 0 1-.21-.26l-.38-.62a.72.72 0 0 1-.07-.5 13.66 13.66 0 0 0 .14-2.6c-.04-.26-.21-.44-.46-.56l-.18-.09c-.07-.04-.08-.1-.02-.15a.29.29 0 0 1 .08-.07l.5-.22c.23-.1.45-.07.66.03l.51.3c.19.11.3.28.3.5l.04 1.31Z" />
        </g>
        <path d="M39.48 145.42c0 .21-.13.36-.35.43a1.3 1.3 0 0 1-.57.02 11.2 11.2 0 0 0-1.64-.12H35.2a38.26 38.26 0 0 0-2.76.25.32.32 0 0 1-.33-.12c-.3-.37-.54-.77-.7-1.2-.01-.05-.06-.1 0-.16s.12-.01.19 0c.4.11.82.17 1.24.17a66.82 66.82 0 0 0 4.04-.08c.46-.03.9-.08 1.35-.15.48-.07.8.14 1.06.45.13.15.2.32.2.5Z" />
      </g>
      <defs>
        <clipPath id="a">
          <path
            fill="currentColor"
            d="M0 0h8.36v8.8H0z"
            transform="translate(3.42 61.83)"
          />
        </clipPath>
        <clipPath id="b">
          <path
            fill="currentColor"
            d="M0 0h8.22v7.03H0z"
            transform="translate(23.47 62.71)"
          />
        </clipPath>
        <clipPath id="c">
          <path
            fill="currentColor"
            d="M0 0h120.82v73.46H0z"
            transform="translate(.34 76.37)"
          />
        </clipPath>
        <clipPath id="d">
          <path
            fill="currentColor"
            d="M0 0h5.3v8.24H0z"
            transform="translate(23.32 141.11)"
          />
        </clipPath>
      </defs>
    </svg>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, default: nil, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil

  attr :kind, :atom,
    values: [:info, :error],
    doc: "used for styling and flash lookup"

  attr :autoshow, :boolean,
    default: true,
    doc: "whether to auto show the flash on mount"

  attr :close, :boolean, default: true, doc: "whether the flash can be closed"

  attr :rest, :global,
    doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block,
    doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-mounted={@autoshow && show("##{@id}")}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed hidden top-2 right-2 w-80 sm:w-96 z-50 rounded-lg p-3 shadow-md shadow-zinc-900/5 ring-1",
        @kind == :info &&
          "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :error &&
          "bg-rose-50 p-3 text-rose-900 shadow-md ring-rose-500 fill-rose-900"
      ]}
      {@rest}
    >
      <p :if={@title}>
        <Heroicons.information_circle
          :if={@kind == :info}
          mini
          class="inline-block h-1xs w-1xs"
        />
        <Heroicons.exclamation_circle
          :if={@kind == :error}
          mini
          class="inline-block h-1xs w-1xs"
        />> <%= @title %>
        <Heroicons.information_circle
          :if={@kind == :info}
          mini
          class="inline-block h-1xs w-1xs"
        />
        <Heroicons.exclamation_circle
          :if={@kind == :error}
          mini
          class="inline-block h-1xs w-1xs"
        />> <%= @title %>
      </p>
      <p><%= msg %></p>
      <button :if={@close} type="button" aria-label={gettext("close")}>
        <Heroicons.x_mark solid />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :id, :string,
    default: "flash-group",
    doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title="Success!" flash={@flash} />
      <.flash kind={:error} title="Error!" flash={@flash} />
      <.flash
        id="disconnected"
        kind={:error}
        title="We can't find the internet"
        close={false}
        autoshow={false}
        phx-disconnected={show("#disconnected")}
        phx-connected={hide("#disconnected")}
      >
        Attempting to reconnect
        <Heroicons.arrow_path class="inline-block h-md w-md" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"

  attr :as, :any,
    default: nil,
    doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div>
        <%= render_slot(@inner_block, f) %>
        <div :for={action <- @actions}>
          <%= render_slot(action, f) %>
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go">Send!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `%Phoenix.HTML.Form{}` and field name may be passed to the input
  to build input names and error messages, or all the attributes and
  errors may be passed explicitly.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values:
      ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc:
      "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"

  attr :options, :list,
    doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"

  attr :multiple, :boolean,
    default: false,
    doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include:
      ~w(autocomplete cols disabled form max maxlength min minlength
                                   pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn ->
      if assigns.multiple, do: field.name <> "[]", else: field.name
    end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label>
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id || @name}
          name={@name}
          value="true"
          checked={@checked}
          {@rest}
        />
        <%= @label %>
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <select id={@id} name={@name} multiple={@multiple} {@rest}>
        <option :if={@prompt} value=""><%= @prompt %></option>
        <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
      </select>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <textarea
        id={@id || @name}
        name={@name}
        class={[
          "mt-2 block min-h-[6rem] w-full rounded-lg border-zinc-300 py-[7px] px-[11px]",
          "text-zinc-900 focus:border-zinc-400 focus:outline-none focus:ring-4 focus:ring-zinc-800/5 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400 phx-no-feedback:focus:ring-zinc-800/5",
          "border-zinc-300 focus:border-zinc-400 focus:ring-zinc-800/5",
          @errors != [] &&
            "border-rose-400 focus:border-rose-400 focus:ring-rose-400/10"
        ]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <input
        type={@type}
        name={@name}
        id={@id || @name}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-2 block w-full rounded-lg border-zinc-300 py-[7px] px-[11px]",
          "text-zinc-900 focus:outline-none focus:ring-4 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400 phx-no-feedback:focus:ring-zinc-800/5",
          "border-zinc-300 focus:border-zinc-400 focus:ring-zinc-800/5",
          @errors != [] &&
            "border-rose-400 focus:border-rose-400 focus:ring-rose-400/10"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for}>
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p>
      <Heroicons.exclamation_circle mini class="inline-block h-1xs w-1xs" />
      <Heroicons.exclamation_circle mini class="inline-block h-1xs w-1xs" />
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[
      @actions != [] && "flex items-center justify-between gap-6",
      @class
    ]}>
      <div>
        <h1>
          <%= render_slot(@inner_block) %>
        </h1>
        <p :if={@subtitle != []}>
          <%= render_slot(@subtitle) %>
        </p>
      </div>
      <div><%= render_slot(@actions) %></div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true

  attr :row_id, :any,
    default: nil,
    doc: "the function for generating the row id"

  attr :row_click, :any,
    default: nil,
    doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc:
      "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action,
    doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div>
      <table>
        <thead>
          <tr>
            <th :for={col <- @col}>
              <%= col[:label] %>
            </th>
            <th :if={@action != []}>
              <span><%= gettext("Actions") %></span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={[
                "relative p-md align-top ",
                @row_click && "hover:cursor-pointer"
              ]}
            >
              <div>
                <span />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  <%= render_slot(col, @row_item.(row)) %>
                </span>
              </div>
            </td>
            <td :if={@action != []}>
              <div>
                <span />
                <span :for={action <- @action}>
                  <%= render_slot(action, @row_item.(row)) %>
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div>
      <dl>
        <div :for={item <- @item}>
          <dt>
            <%= item.title %>
          </dt>
          <dd><%= render_slot(item) %></dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div>
      <.link navigate={@navigate}>
        <Heroicons.arrow_left solid class="inline-block h-1xs w-1xs" />
        <Heroicons.arrow_left solid class="inline-block h-1xs w-1xs" />
        <%= render_slot(@inner_block) %>
      </.link>
    </div>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-md translate-y-1xs sm:translate-y-md sm:scale-95",
         "opacity-100 translate-y-md sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-md sm:scale-100",
         "opacity-md translate-y-1xs sm:translate-y-md sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition:
        {"transition-all transform ease-out duration-300", "opacity-md",
         "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition:
        {"transition-all transform ease-in duration-200", "opacity-100",
         "opacity-md"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate "is invalid" in the "errors" domain
    #     dgettext("errors", "is invalid")
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # Because the error messages we show in our forms and APIs
    # are defined inside Ecto, we need to translate them dynamically.
    # This requires us to call the Gettext module passing our gettext
    # backend as first argument.
    #
    # Note we use the "errors" domain, which means translations
    # should be written to the errors.po file. The :count option is
    # set by Ecto and indicates we should also apply plural rules.
    if count = opts[:count] do
      Gettext.dngettext(FamichatWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(FamichatWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
```

# /srv/famichat/backend/lib/famichat_web/components/theme_switcher.ex

```ex
defmodule FamichatWeb.Components.ThemeSwitcher do
  @moduledoc """
  A Phoenix Component for rendering a theme switcher.

  This component provides a user interface for selecting between light, dark, and system themes.
  It renders a fieldset with radio buttons for each theme option.

  ## Usage

      <.theme_switcher />

  Or with a custom class:

      <.theme_switcher class="my-custom-class" />

  Note: This component requires the "ThemeSwitcher" Phoenix LiveView JS hook to be defined
  for full functionality.
  """

  use Phoenix.Component
  import FamichatWeb.Gettext

  @doc """
  Renders a theme switcher component.

  ## Attributes

    * `:class` - (optional) Additional CSS classes to apply to the fieldset.

  ## Examples

      <.theme_switcher />
      <.theme_switcher class="mt-4" />
  """
  attr :class, :string, default: nil

  @spec theme_switcher(map()) :: Phoenix.LiveView.Rendered.t()
  def theme_switcher(assigns) do
    themes = [
      %{value: "light", label: gettext("Light")},
      %{value: "dark", label: gettext("Dark")},
      %{value: "system", label: gettext("System")}
    ]

    ~H"""
    <fieldset
      class={["noscript", @class]}
      id="theme-switcher"
      phx-hook="ThemeSwitcher"
    >
      <legend class="sr-only"><%= gettext("Theme") %></legend>
      <form id="theme-switcher-form">
        <%= for theme <- themes do %>
          <% theme_id = "theme_#{theme.value}" %>
          <label for={theme_id}>
            <input
              type="radio"
              id={theme_id}
              name="theme"
              value={theme.value}
              checked={theme.value == "system"}
            />
            <%= theme.label %>
          </label>
        <% end %>
      </form>
    </fieldset>
    """
  end
end
```

# /srv/famichat/backend/lib/famichat_web/components/layouts.ex

```ex
defmodule FamichatWeb.Layouts do
  @moduledoc false
  use FamichatWeb, :html
  alias FamichatWeb.Router.Helpers, as: Routes
  import FamichatWeb.Gettext
  import FamichatWeb.Components.Typography
  embed_templates "layouts/*"

  @supported_locales Application.compile_env(:famichat, :supported_locales)

  def remove_locale_from_path(path) do
    case String.split(path, "/", parts: 3) do
      ["", locale, rest] when locale in @supported_locales -> "/#{rest}"
      ["", locale] when locale in @supported_locales -> "/"
      _ -> path
    end
  end

  def hreflang_tags(conn) do
    current_path = Phoenix.Controller.current_path(conn)

    # Remove locale from the beginning of the path
    path_without_locale =
      current_path
      |> String.split("/", parts: 3)
      |> Enum.at(2, "")
      |> String.trim_leading("/")

    tags =
      @supported_locales
      |> Enum.map(fn locale ->
        locale_path = "/#{locale}/#{path_without_locale}"
        locale_url = Routes.url(conn) <> locale_path

        query_string =
          if conn.query_string != "", do: "?#{conn.query_string}", else: ""

        full_url = locale_url <> query_string

        ~s(<link rel="alternate" hreflang="#{locale}" href="#{full_url}" />)
      end)

    # Add x-default tag (usually pointing to the default locale or homepage)
    default_url = Routes.url(conn) <> "/"

    default_tag =
      ~s(<link rel="alternate" hreflang="x-default" href="#{default_url}" />)

    (tags ++ [default_tag])
    |> Enum.join("\n")
    |> Phoenix.HTML.raw()
  end
end
```

# /srv/famichat/backend/lib/famichat_web/components/navigation.ex

```ex
defmodule FamichatWeb.Navigation do
  @moduledoc """
  Main site navigation livecomponent.

  Features:
  - Logo
  - Page navigation (Case Studies, Notes, About)
  - EN/JA language switcher
  - Active page highlighting
  - Accessibility labels

  Usage:
      <.live_component module={FamichatWeb.Navigation} id="nav" current_path={@current_path} user_locale={@locale} />

  Assigns:
  - `current_path`: Current URL path (default: "/")
  - `user_locale`: User's locale (default: "en")

  Requires gettext translations for navigation labels and language switcher text.

  Helper functions:
  - `active_class/2`: Determines active navigation item
  - `build_localized_path/2`: Generates localized paths
  """
  use FamichatWeb, :live_component
  alias FamichatWeb.Router.Helpers, as: Routes
  import FamichatWeb.Components.ThemeSwitcher
  import FamichatWeb.Components.Typography

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:current_path, fn -> assigns[:current_path] || "/" end)
      |> assign_new(:user_locale, fn -> assigns[:user_locale] || "en" end)
      |> assign_new(:selected_theme, fn ->
        assigns[:selected_theme] || "dark"
      end)

    {:ok, socket}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        en_path: build_localized_path(assigns.current_path, "en"),
        ja_path: build_localized_path(assigns.current_path, "ja")
      )

    ~H"""
    <nav role="banner" class="grid grid-cols-12 items-center w-full">
      <!-- Logo -->
      <.link
        navigate={Routes.home_path(@socket, :index, @user_locale)}
        class="col-span-2"
        aria-label={gettext("Zane Riley Famichat Logo")}
      >
        <.typography locale={@user_locale} tag="span" size="2xl" font="cardinal">
          Zane
        </.typography>
      </.link>
      <!-- Page navigation -->
      <nav role="navigation" class="col-span-6 col-start-3">
        <ul class="flex space-x-1xl">
          <li>
            <.link
              navigate={Routes.case_study_index_path(@socket, :index, @user_locale)}
              class={active_class(@current_path, :case_studies)}
            >
              <.typography locale={@user_locale} tag="span" size="md">
                <%= ngettext("Case Study", "Case Studies", 2) %>
              </.typography>
            </.link>
          </li>
          <li>
            <.link
              navigate={Routes.note_index_path(@socket, :index, @user_locale)}
              class={active_class(@current_path, :notes)}
            >
              <.typography locale={@user_locale} tag="span" size="md">
                <%= ngettext("Note", "Notes", 2) %>
              </.typography>
            </.link>
          </li>
          <li>
            <.link
              navigate={Routes.about_path(@socket, :index, @user_locale)}
              class={active_class(@current_path, :about)}
            >
              <.typography locale={@user_locale} tag="span" size="md">
                <%= gettext("Self") %>
              </.typography>
            </.link>
          </li>
        </ul>
      </nav>
      <!-- Theme switcher -->
      <.theme_switcher class="col-start-9 col-end-11" />
      <!-- Language switcher -->
      <nav
        aria-label={gettext("Language switcher")}
        class="col-start-11 col-end-13 text-1xs"
      >
        <ul class="flex justify-end space-x-md">
          <li>
            <.link
              href={@en_path}
              aria-label={gettext("Switch to English")}
              aria-current={if @user_locale == "en", do: "page", else: "false"}
              class={"#{if @user_locale == "en", do: "font-bold", else: ""}"}
            >
              <.typography locale={@user_locale} tag="span" size="1xs">
                English
              </.typography>
            </.link>
          </li>
          <li>
            <.link
              href={@ja_path}
              aria-label={gettext("Switch to Japanese")}
              aria-current={if @user_locale == "ja", do: "page", else: "false"}
              class={"#{if @user_locale == "ja", do: "font-bold", else: ""}"}
            >
              <.typography locale={@user_locale} tag="span" size="1xs">
                日本語
              </.typography>
            </.link>
          </li>
        </ul>
      </nav>
    </nav>
    """
  end

  defp active_class(current_path, page) do
    if String.contains?(current_path, Atom.to_string(page)),
      do: "font-bold",
      else: ""
  end

  defp build_localized_path(current_path, locale) do
    base_path = FamichatWeb.Layouts.remove_locale_from_path(current_path)

    if base_path == "/" do
      "/#{locale}"
    else
      "/#{locale}#{base_path}"
    end
  end
end
```

# /srv/famichat/backend/lib/famichat_web/components/layouts/app.html.heex

```heex
<.flash_group flash={@flash} />
<.live_component
  module={FamichatWeb.Navigation}
  id="nav"
  current_path={@current_path}
  user_locale={@user_locale}
/>
<div
  data-main-view
  class="grid grid-cols-12 transition-opacity duration-500 ease-in-out phx-page-loading:opacity-0 text-color-main"
>
  <main class="sm:col-start-3 sm:col-end-11 ">
    <%= @inner_content %>
  </main>
</div>
```

# /srv/famichat/backend/lib/famichat_web/components/layouts/root.html.heex

```heex
<!DOCTYPE html>
<html
  lang={@user_locale || @conn.assigns[:user_locale] || "en"}
  data-theme={Application.get_env(:famichat, :default_theme, "dark")}
>
  <head>
    <.live_title>
      <%= assigns[:page_title] ||
        "Zane Riley | Product Designer (Tokyo) | 10+ Years Experience" %>
    </.live_title>

    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <meta
      name="description"
      content={
        assigns[:page_description] ||
          ~c"Zane Riley: Tokyo Product Designer. 10+ yrs experience. Currently at Google. Worked in e-commerce, healthcare, and finance. Designed and built products for Google, Google Maps, and Google Search."
      }
    />
    <noscript>
      <style>
        .noscript { display: none; }
      </style>
    </noscript>
    <!-- href langs -->
    <%= hreflang_tags(@conn) %>
    <!-- Favicon and touch icons -->
    <link
      rel="apple-touch-icon"
      sizes="180x180"
      href={url(~p"/apple-touch-icon.png")}
    />
    <link
      rel="icon"
      type="image/png"
      sizes="32x32"
      href={url(~p"/favicon-32x32.png")}
    />
    <link
      rel="icon"
      type="image/png"
      sizes="16x16"
      href={url(~p"/favicon-16x16.png")}
    />
    <link
      rel="mask-icon"
      href={url(~p"/safari-pinned-tab.svg")}
      color="#597099"
    />
    <link rel="manifest" href={url(~p"/site.webmanifest")} />
    <!-- Color definitions -->
    <meta name="msapplication-TileColor" content="#2b5797" />
    <meta name="theme-color" content="#343334" />
    <!-- Dynamic Schema Markup -->

    <!-- Dynamic OG Meta -->
    <%= if assigns[:og_meta] do %>
      <meta property="og:title" content={assigns[:og_meta][:title]} />
      <meta property="og:type" content={assigns[:og_meta][:type]} />
      <meta property="og:image" content={assigns[:og_meta][:image]} />
      <meta property="og:description" content={assigns[:og_meta][:description]} />
    <% end %>
    <!-- FUll CSS -->
    <link phx-track-static rel="stylesheet" href="/css/app.css" />
    <script
      defer
      phx-track-static
      type="text/javascript"
      src={url(~p"/js/app.js")}
    />
  </head>
  <body class="min-h-screen flex flex-col text-md bg-gradient">
    <a href="#main-content" class="sr-only" tabindex="0">
      <%= gettext("Skip to main content") %>
    </a>

    <%= @inner_content %>
    <footer
      role="contentinfo"
      class="mt-auto grid grid-cols-12 sticky top-[100vh] text-1xs"
    >
      <div class="col-span-2">
        Logo
      </div>
      <div class="col-span-3">
        <.typography locale={@user_locale} tag="h2" size="1xs" font="cheee">
          <%= gettext("Connect") %>
        </.typography>
        <.typography locale={@user_locale} tag="ul" size="1xs">
          <li>
            <a href="mailto:zane@zaneriley.com" target="_blank" rel="noopener">
              hello@zaneriley.com
            </a>
          </li>
          <li>
            <a
              href="https://www.linkedin.com/in/zaneriley/"
              target="_blank"
              rel="noopener"
            >
              LinkedIn
            </a>
          </li>
          <li>
            <a
              href="https://github.com/zaneriley"
              target="_blank"
              rel="noopener"
            >
              Github
            </a>
          </li>
        </.typography>
      </div>
      <div class="col-span-3">
        <.typography locale={@user_locale} tag="h2" size="1xs" font="cheee">
          <%= gettext("Colophon") %>
        </.typography>

        <.typography locale={@user_locale} tag="p" size="1xs">
          <%= raw(
            gettext(
              "Type set in %{font1}, %{font2}, %{font3}, & %{font4}.",
              font1:
                "<a href='https://www.grillitype.com/typeface/gt-flexa'>GT Flexa</a>",
              font2:
                "<a href='https://productiontype.com/font/cardinal/cardinal-fruit' class='font-cardinal-fruit' rel='noopener' target='_blank'>Cardinal Fruit</a>",
              font3:
                "<a href='https://ohnotype.co/fonts/cheee' class='font-cheee' rel='noopener' target='_blank'>CHEEE</a>",
              font4:
                "<a href='https://fonts.google.com/noto/specimen/Noto+Sans+JP' rel='noopener' target='_blank'>Noto Sans JP</a>"
            )
          ) %><br /><%= raw(
            gettext("Design avaiable in %{figma}.",
              figma:
                "<a href='https://www.figma.com/design/zDOcBhnjTDCWmc6OFgeoUc/Zane-Riley's-Product-Famichat?node-id=2209-559&t=0gZqDDkC2pYanuW3-0' target='_blank' rel='noopener'>Figma</a>"
            )
          ) %>
        </.typography>
      </div>
      <div class="col-span-3">
        <.typography locale={@user_locale} tag="h2" size="1xs" font="cheee">
          <%= gettext("Server") %>
        </.typography>
        <.typography locale={@user_locale} tag="p" size="1xs">
          <%= gettext("Hosted on my home server in Tokyo.") %> <br />
          <%= gettext("Written in Elixir.") %> <br />
          <%= raw(
            gettext("Open source on %{github}.",
              github:
                "<a href='https://github.com/zane-riley/personal-site' target='_blank' rel='noopener'>Github</a>"
            )
          ) %>
        </.typography>
      </div>
      <div class="col-span-12">
        <.typography
          locale={@user_locale}
          tag="p"
          size="1xs"
          font="cheee"
          center={true}
          color="suppressed"
        >
          Now in Tokyo
        </.typography>
        <.typography
          locale={@user_locale}
          tag="p"
          size="1xs"
          font="cheee"
          center={true}
          color="suppressed"
        >
          &copy; 2010 – <%= @current_year %>
        </.typography>
      </div>
    </footer>
  </body>
</html>
```

# /srv/famichat/backend/lib/famichat_web/components/typography.ex

```ex
defmodule FamichatWeb.Components.Typography do
  @moduledoc """
  A flexible typography component for rendering text elements with customizable styles.

  ## Example Usage

      <.typography locale={@user_locale} tag="h1" size="4xl" center={true}>Heading 1</.typography>
      <.typography locale={@user_locale} tag="p" size="md" dropcap={true}>Paragraph</.typography>
      <.typography locale={@user_locale} tag="p" size="1xs" font="cheee" color="accent">Special Text</.typography>

  """

  use Phoenix.Component
  import Phoenix.HTML
  require Logger

  @doc """
  Renders a typography element with the specified attributes.

  ## Attributes

    * `:tag` - The HTML tag to use (default: `"p"`).
    * `:size` - The text size, e.g., `"4xl"`, `"md"`, `"1xs"` (default: `"md"`).
    * `:center` - Centers the text if set to `true` (default: `false`).
    * `:id` - The HTML `id` attribute (optional).
    * `:color` - Additional text color classes (optional).
    * `:font` - The font variant to use, e.g., `"cardinal"`, `"cheee"` (optional).
    * `:dropcap` - Enables dropcap styling if set to `true` (default: `false`).
    * `:class` - Additional custom classes (optional).

  ## Examples

      <.typography locale={@user_locale} tag="h1" size="4xl" center={true}>Heading 1</.typography>

      <.typography locale={@user_locale} tag="p" size="md" dropcap={true}>Paragraph</.typography>

      <.typography locale={@user_locale} tag="p" size="1xs" font="cheee" color="accent">Special Text</.typography>

  """
  @spec typography(map()) :: Phoenix.LiveView.Rendered.t()
  attr :tag, :string, default: "p"
  attr :size, :string, default: "md"
  attr :center, :boolean, default: false
  attr :id, :string, default: nil
  attr :color, :string, default: nil
  attr :font, :string, default: nil
  attr :dropcap, :boolean, default: false
  attr :class, :string, default: nil
  slot :inner_block, required: true

  alias FamichatWeb.Components.TypographyHelpers

  def typography(assigns) do
    all_classes = TypographyHelpers.build_class_names(assigns)

    assigns =
      assigns
      |> assign(:all_classes, all_classes)
      |> assign(:optical_adjustment_class, "optical-adjustment")

    ~H"""
    <.dynamic_tag name={@tag} id={@id} class={@all_classes}>
      <span class={@optical_adjustment_class}>
        <%= if @dropcap do %>
          <% text =
            render_slot(@inner_block)
            |> Phoenix.HTML.Safe.to_iodata()
            |> IO.iodata_to_binary()
            |> String.trim() %>
          <%= if starts_with_hanging_punct?(text) do %>
            <% {hanging_punct, rest} = String.split_at(text, 1) %>
            <span class="dropcap hanging-punct font-noto-sans-jp" aria-hidden="true">
              <span class="hanging-punct"><%= hanging_punct %></span><span><%= rest %></span>
            </span>
            <span class="sr-only"><%= text %></span>
          <% else %>
            <% {first_char, rest} = String.split_at(text, 1) %>
            <span aria-hidden="true">
              <span class="dropcap font-noto-serif-jp"><%= first_char %></span><span><%= rest %></span>
            </span>
            <span class="sr-only"><%= text %></span>
          <% end %>
        <% else %>
          <%= render_slot(@inner_block) %>
        <% end %>
      </span>
    </.dynamic_tag>
    """
  end

  @doc """
  Determines if the given text starts with hanging punctuation.

  ## Parameters

    - `text` - The text string to analyze.

  ## Returns

    - `true` if the text starts with a hanging punctuation mark, otherwise `false`.
  """
  @spec starts_with_hanging_punct?(String.t()) :: boolean()
  def starts_with_hanging_punct?(text) when is_binary(text) do
    hanging_punctuations = [
      ",",
      ".",
      "،",
      "۔",
      "、",
      "。",
      "，",
      "．",
      "﹐",
      "﹑",
      "﹒",
      "｡",
      "､",
      "：",
      "？",
      "！",
      "\"",
      "'",
      "“",
      "”",
      "‘",
      "’",
      "„",
      "‟",
      "«",
      "»",
      "‹",
      "›",
      "「",
      "」",
      "『",
      "』",
      "《",
      "》",
      "〈",
      "〉"
    ]

    case String.graphemes(text) do
      [first | _] -> first in hanging_punctuations
      [] -> false
    end
  end
end
```

# /srv/famichat/backend/lib/famichat_web/components/ast_renderer.ex

```ex
 ```

# /srv/famichat/backend/lib/famichat_web/live_error.ex

```ex
defmodule FamichatWeb.LiveError do
  defexception message: "invalid route", plug_status: 404
end
```

# /srv/famichat/backend/lib/famichat/application.ex

```ex
defmodule Famichat.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Can't be a child process for some reason.
    Application.start(:yamerl)

    children = [
      FamichatWeb.Telemetry,
      Famichat.Repo,
      {DNSCluster,
       query: Application.get_env(:famichat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Famichat.PubSub},
      {Finch, name: Famichat.Finch},
      FamichatWeb.Endpoint,
      Famichat.Cache
    ]

    # Add file watcher for all environments
    watcher_config =
      Application.get_env(
        :famichat,
        Famichat.Content.FileManagement.Watcher,
        []
      )

    children =
      children ++ [{Famichat.Content.FileManagement.Watcher, watcher_config}]

    opts = [strategy: :one_for_one, name: Famichat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FamichatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

# /srv/famichat/backend/lib/famichat/cache.ex

```ex
defmodule Famichat.Cache do
  @moduledoc """
  Wrapper for caching operations.

  This module provides a unified interface for cache operations, supporting
  bypassing and disabling of the cache. It uses Cachex as the underlying
  cache implementation when enabled.

  The cache can be configured using the `:famichat, :cache` application
  environment variable. Set `[disabled: true]` to disable the cache.
  """

  require Logger
  @cache_name :content_cache

  @doc """
  Returns the child specification for the cache.

  This function is used by supervisors to start the cache process.
  """
  @spec child_spec(any()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    cache_opts = Application.get_env(:famichat, :cache, [])

    if disabled?() do
      %{id: __MODULE__, start: {__MODULE__, :start_link_disabled, []}}
    else
      %{
        id: __MODULE__,
        start: {Cachex, :start_link, [@cache_name, cache_opts]}
      }
    end
  end

  @doc """
  Retrieves a value from the cache.

  Returns `{:error, :invalid_key}` if the key is nil, `:cache_bypassed` if
  bypassed, `:cache_disabled` if the cache is disabled, or the cached value.
  """
  @spec get(any(), Keyword.t()) ::
          any() | :cache_bypassed | :cache_disabled | {:error, :invalid_key}
  def get(key, opts \\ []) do
    cond do
      is_nil(key) ->
        {:error, :invalid_key}

      should_bypass?(opts) ->
        :cache_bypassed

      disabled?() ->
        :cache_disabled

      true ->
        result = Cachex.get(@cache_name, key)

        Logger.debug(
          "Cache.get called with key: #{inspect(key)}, result: #{inspect(result)}"
        )

        result
    end
  end

  def put(key, value, opts \\ []) do
    cond do
      is_nil(key) ->
        {:error, :invalid_key}

      should_bypass?(opts) ->
        :cache_bypassed

      disabled?() ->
        :cache_disabled

      true ->
        do_put(key, value, opts)
    end
  end

  defp do_put(key, value, opts) do
    ttl = Keyword.get(opts, :ttl)
    result = put_with_ttl(@cache_name, key, value, ttl)
    result
  end

  defp put_with_ttl(cache, key, value, nil), do: Cachex.put(cache, key, value)

  defp put_with_ttl(cache, key, value, ttl),
    do: Cachex.put(cache, key, value, ttl: ttl)

  @doc """
  Deletes a value from the cache.

  Returns `{:error, :invalid_key}` if the key is nil, `:cache_bypassed` if
  bypassed, `:cache_disabled` if the cache is disabled, or the result of
  Cachex.del.
  """
  @spec delete(any(), Keyword.t()) ::
          any() | :cache_bypassed | :cache_disabled | {:error, :invalid_key}
  def delete(key, opts \\ []) do
    cond do
      is_nil(key) ->
        {:error, :invalid_key}

      should_bypass?(opts) ->
        :cache_bypassed

      disabled?() ->
        :cache_disabled

      true ->
        Cachex.del(@cache_name, key)
    end
  end

  @doc """
  Checks if a key exists in the cache.

  Returns `:cache_bypassed` if bypassed, `:cache_disabled` if the cache is
  disabled, or the result of Cachex.exists?.
  """
  @spec exists?(any(), Keyword.t()) ::
          boolean() | :cache_bypassed | :cache_disabled
  def exists?(key, opts \\ []) do
    cond do
      should_bypass?(opts) ->
        :cache_bypassed

      disabled?() ->
        :cache_disabled

      true ->
        case Cachex.exists?(@cache_name, key) do
          {:ok, exists} -> exists
          _ -> false
        end
    end
  end

  @doc """
  Gets the TTL for a key in the cache.

  Returns `:cache_bypassed` if bypassed, `:cache_disabled` if the cache is
  disabled, or the result of Cachex.ttl.
  """
  @spec ttl(any(), Keyword.t()) :: integer() | :cache_bypassed | :cache_disabled
  def ttl(key, opts \\ []) do
    cond do
      should_bypass?(opts) -> :cache_bypassed
      disabled?() -> :cache_disabled
      true -> Cachex.ttl(@cache_name, key)
    end
  end

  @doc """
  Clears all entries from the cache.

  Returns `:cache_bypassed` if bypassed, `:cache_disabled` if the cache is
  disabled, or the result of Cachex.clear.
  """
  @spec clear(Keyword.t()) :: :ok | :cache_bypassed | :cache_disabled
  def clear(opts \\ []) do
    cond do
      should_bypass?(opts) -> :cache_bypassed
      disabled?() -> :cache_disabled
      true -> Cachex.clear(@cache_name)
    end
  end

  @doc """
  Busts (deletes) a specific key from the cache.

  Returns `:cache_bypassed` if bypassed, `:cache_disabled` if the cache is
  disabled, or the result of Cachex.del.
  """
  @spec bust(any(), Keyword.t()) :: :ok | :cache_bypassed | :cache_disabled
  def bust(key, opts \\ []) do
    cond do
      should_bypass?(opts) -> :cache_bypassed
      disabled?() -> :cache_disabled
      true -> Cachex.del(@cache_name, key)
    end
  end

  @doc """
  Starts a disabled cache using an Agent.

  This is used when the cache is configured to be disabled.
  """
  @spec start_link_disabled() :: Agent.on_start()
  def start_link_disabled do
    Agent.start_link(fn -> %{} end, name: @cache_name)
  end

  @doc """
  Checks if the cache is disabled based on application configuration.
  """
  @spec disabled?() :: boolean()
  def disabled? do
    Application.get_env(:famichat, :cache, [])[:disabled] == true
  end

  @spec should_bypass?(Keyword.t()) :: boolean()
  defp should_bypass?(opts) do
    Keyword.get(opts, :bypass_cache, false)
  end
end
```

# /srv/famichat/backend/lib/famichat/mailer.ex

```ex
defmodule Famichat.Mailer do
  @moduledoc """
  This module defines Swoosh for your application.
  """

  use Swoosh.Mailer, otp_app: :famichat
end
```

# /srv/famichat/backend/lib/famichat/release.ex

```ex
defmodule Famichat.Release do
  @moduledoc """
  This module defines functions that you can run with releases.
  """

  @app :famichat
  alias Famichat.Content
  alias Famichat.Content.FileManagement.Reader
  alias Famichat.Content.Remote.GitRepoSyncer
  require Logger

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Pulls the latest changes from the configured repository.
  """
  def pull_repository do
    repo_url = Application.get_env(:famichat, :content_repo_url)
    local_path = Application.get_env(:famichat, :content_base_path)

    IO.puts("Debug: repo_url = #{inspect(repo_url)}")
    IO.puts("Debug: local_path = #{inspect(local_path)}")

    cond do
      is_nil(repo_url) ->
        raise "Missing configuration for content_repo_url. Ensure CONTENT_REPO_URL environment variable is set."

      is_nil(local_path) ->
        raise "Missing configuration for content_base_path. Check your config files."

      not is_binary(repo_url) ->
        raise "Invalid configuration for content_repo_url: #{inspect(repo_url)}. It should be a string."

      not is_binary(local_path) ->
        raise "Invalid configuration for content_base_path: #{inspect(local_path)}. It should be a string."

      true ->
        do_pull_repository(repo_url, local_path)
    end
  end

  defp do_pull_repository(repo_url, local_path) do
    case GitRepoSyncer.sync_repo(repo_url, local_path) do
      {:ok, _} ->
        Logger.info("Successfully pulled latest changes from the repository.")

      {:error, reason} ->
        Logger.error("Failed to pull repository: #{reason}")
        raise "Failed to pull repository: #{reason}"
    end
  end

  @doc """
  Reads all existing markdown files and updates the database.
  """
  def read_existing_content do
    with :ok <- load_app(),
         {:ok, content_base_path} <- get_content_base_path(),
         {:ok, files} <- list_files(content_base_path) do
      files
      |> Enum.filter(&markdown?/1)
      |> Enum.each(&process_file(Path.join(content_base_path, &1)))
    else
      {:error, reason} ->
        Logger.error("Failed to read existing content: #{inspect(reason)}")
    end
  end

  defp get_content_base_path do
    case Application.get_env(:famichat, :content_base_path) do
      nil ->
        {:error,
         "Missing configuration for content_base_path. Check your config files."}

      path when is_binary(path) ->
        {:ok, path}

      invalid ->
        {:error,
         "Invalid configuration for content_base_path: #{inspect(invalid)}"}
    end
  end

  defp list_files(path) do
    case File.ls(path) do
      {:ok, files} ->
        {:ok, files}

      {:error, reason} ->
        {:error, "Failed to list files in #{path}: #{inspect(reason)}"}
    end
  end

  defp markdown?(file_name) do
    String.ends_with?(file_name, ".md")
  end

  defp process_file(file_path) do
    case Reader.read_markdown_file(file_path) do
      {:ok, content_type, attrs} ->
        case Content.upsert_from_file(content_type, attrs) do
          {:ok, _content} ->
            Logger.info("Successfully upserted content from file: #{file_path}")

          {:error, reason} ->
            Logger.error(
              "Error upserting content from file #{file_path}: #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        Logger.error("Error processing file #{file_path}: #{inspect(reason)}")
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

# /srv/famichat/backend/lib/famichat/logger_formatter.ex

```ex
defmodule Famichat.LoggerFormatter do
  @moduledoc """
  A custom logger formatter for the Famichat application.

  This formatter is responsible for formatting log messages in a specific format that is consistent with the application's logging requirements.
  """

  @doc """
  Formats a log message.

  The formatter takes the following arguments:
    - level: The log level of the message (e.g., :debug, :info, :warn, :error)
    - message: The log message to be formatted
    - timestamp: The timestamp of the log message
    - metadata: Additional metadata associated with the log message

  The formatter returns a formatted log message as a string.
  """
  def format(level, message, timestamp, metadata) do
    [
      format_timestamp(timestamp),
      format_level(level),
      format_module(metadata),
      format_message(message),
      format_metadata_inline(metadata),
      "\n"
    ]
    |> IO.ANSI.format()
  end

  defp format_timestamp(
         {{_year, _month, _day}, {hour, minute, second, millisecond}}
       ) do
    formatted_time =
      :io_lib.format("~2..0B:~2..0B:~2..0B.~3..0B", [
        hour,
        minute,
        second,
        millisecond
      ])

    [:cyan, "#{formatted_time} "]
  end

  defp format_level(level) do
    color =
      case level do
        :debug -> :green
        :info -> :blue
        :warn -> :yellow
        :warning -> :yellow
        :error -> :red
        _ -> :normal
      end

    [color, "[#{String.upcase(to_string(level))}] "]
  end

  defp format_module(metadata) do
    case Keyword.get(metadata, :module) do
      nil -> ""
      module -> [:magenta, "[#{inspect(module)}]\n"]
    end
  end

  defp format_message(message) do
    [:bright, "  #{message}\n"]
  end

  defp format_metadata_inline(metadata) do
    function = format_function(metadata)
    line = Keyword.get(metadata, :line, "")
    request_id = Keyword.get(metadata, :request_id, "")

    [
      :faint,
      "  #{function}",
      (line != "" && ", Line #{line}") || "",
      (request_id != "" && ", Request: #{request_id}") || ""
    ]
  end

  defp format_function(metadata) do
    case Keyword.get(metadata, :function) do
      [name, "/", arity] -> "#{name}/#{arity}"
      other -> inspect(other)
    end
  end
end
```

# /srv/famichat/backend/lib/famichat/content/content.ex

```ex
defmodule Famichat.Content do
  @moduledoc """
  The Content context.

  Provides a unified interface for managing content-related operations,
  delegating to specialized modules like EntryManager and TranslationManager.
  """
  alias Famichat.Content.Types
  alias Famichat.Content.EntryManager
  alias Famichat.Content.Schemas.{Note, CaseStudy}
  require Logger

  defmodule InvalidContentTypeError do
    defexception [:message]
  end

  @type content_type :: Types.content_type()
  @type content_id :: integer()
  @type content_url :: String.t()
  @type content_identifier :: content_id() | content_url()

  @doc """
  Lists content items of a specific type with optional sorting and locale.

  ## Parameters
    - type: The content type ("note" or "case_study")
    - opts: Keyword list of options (e.g., [sort_by: :published_at, sort_order: :desc])
    - locale: The locale for translations (optional)

  ## Returns
    - List of content items with merged translations
  """
  @spec list(content_type(), keyword(), String.t() | nil) ::
          [Note.t()] | [CaseStudy.t()]
  def list(type, opts \\ [], locale \\ nil) do
    locale = locale || Application.get_env(:famichat, :default_locale)
    EntryManager.list_contents(type, opts, locale)
  end

  @doc """
  Retrieves a content item (Note or CaseStudy) by its type and identifier.

  ## Parameters
    - type: The content type ("note" or "case_study")
    - id_or_url: The unique identifier (ID or URL) of the content item

  ## Returns
    - The content item (Note or CaseStudy) if found

  ## Raises
    - Ecto.NoResultsError: If no content is found
    - ContentTypeMismatchError: If the found content type doesn't match the requested type
    - InvalidContentTypeError: If an invalid content type is provided

  ## Examples

      iex> Content.get!("note", "my-note-url")
      %Note{...}

      iex> Content.get!("case_study", "non-existent-id")
      ** (Ecto.NoResultsError)

      iex> Content.get!("invalid_type", "some-id")
      ** (InvalidContentTypeError)
  """
  @spec get!(content_type(), content_identifier()) ::
          Note.t() | CaseStudy.t() | no_return()
  def get!(type, id_or_url) do
    Logger.debug(
      "Attempting to fetch #{type} with identifier: #{inspect(id_or_url)}"
    )

    case Types.valid_type?(type) do
      true ->
        fetch_content(type, id_or_url)

      false ->
        Logger.error("Invalid content type provided: #{inspect(type)}")
        raise InvalidContentTypeError, "Invalid content type: #{inspect(type)}"
    end
  end

  @spec fetch_content(content_type(), content_identifier()) ::
          Note.t() | CaseStudy.t() | no_return()
  defp fetch_content(type, id_or_url) do
    EntryManager.get_content_by_id_or_url(type, id_or_url)
  end

  @spec create(content_type(), map()) ::
          {:ok, Note.t() | CaseStudy.t()} | {:error, Ecto.Changeset.t()}
  def create(type, attrs) do
    Logger.debug(
      "Create called with type: #{inspect(type)}, attrs: #{inspect(attrs)}"
    )

    attrs = Map.put(attrs, "content_type", type)
    Logger.debug("Modified attrs: #{inspect(attrs)}")

    try do
      EntryManager.create_content(attrs)
    rescue
      Famichat.Content.InvalidContentTypeError ->
        {:error, :invalid_content_type}
    end
  end

  @spec update(content_type(), Note.t() | CaseStudy.t(), map()) ::
          {:ok, Note.t() | CaseStudy.t()} | {:error, Ecto.Changeset.t()}
  def update(type, content, attrs) do
    EntryManager.update_content(content, attrs, type)
  end

  @spec delete(content_type(), Note.t() | CaseStudy.t()) ::
          {:ok, Note.t() | CaseStudy.t()} | {:error, Ecto.Changeset.t()}
  def delete(_type, content) do
    EntryManager.delete_content(content)
  end

  @spec change(content_type(), Note.t() | CaseStudy.t() | map(), map()) ::
          Ecto.Changeset.t() | {:error, :invalid_content_type}
  def change(type, content, attrs \\ %{}) do
    Logger.debug("Content.change called with:")
    Logger.debug("  type: #{inspect(type)}")
    Logger.debug("  content: #{inspect(content)}")
    Logger.debug("  attrs: #{inspect(attrs)}")

    case Types.get_schema(type) do
      {:error, :invalid_content_type} ->
        Logger.error("Invalid content type: #{inspect(type)}")
        {:error, :invalid_content_type}

      schema when is_atom(schema) ->
        Logger.debug("Using schema: #{inspect(schema)}")
        changeset = schema.changeset(content, attrs)
        Logger.debug("Resulting changeset: #{inspect(changeset)}")
        changeset
    end
  end

  @doc """
  Retrieves content with its translations and compiled content.

  ## Parameters
  - `content_type`: The type of content to retrieve ("note" or "case_study").
  - `identifier`: The unique identifier (URL or ID) of the content.
  - `locale`: The locale of the translations to fetch.

  ## Returns
  - `{:ok, content, translations, compiled_content}`: Content, its translations, and compiled content if found.
  - `{:error, :not_found}`: If no content is found.

  ## Examples

      iex> Content.get_with_translations("case_study", "my-case-study", "en")
      {:ok, %CaseStudy{...}, %{"title" => "Translated Title", ...}, "Translated Title"}

      iex> Content.get_with_translations("note", 123, "fr")
      {:ok, %Note{...}, %{"content" => "Contenu traduit", ...}, "<p>Contenu traduit</p>"}

      iex> Content.get_with_translations("case_study", "non-existent", "en")
      {:error, :not_found}
  """

  @spec get_with_translations(
          Types.content_type(),
          String.t() | integer(),
          String.t()
        ) ::
          {:ok, Note.t() | CaseStudy.t(), map(), String.t()} | {:error, atom()}
  def get_with_translations(content_type, identifier, locale) do
    EntryManager.get_content_with_translations(content_type, identifier, locale)
  end

  @doc """
  Upserts content from a file based on the content type and attributes provided.

  This function delegates the actual upsert operation to EntryManager after
  performing some basic logging. It handles both atom and string content types.

  ## Parameters
    - content_type: The type of content (e.g., :note, :case_study, "note", or "case_study").
    - attrs: Map of attributes to upsert the content with, including "url" and "locale".

  ## Returns
    - {:ok, content} if the content is successfully upserted
    - {:error, reason} if there is an error upserting the content

  ## Examples

      iex> Content.upsert_from_file(:note, %{"url" => "my-note", "locale" => "en", "title" => "My Note"})
      {:ok, %Note{...}}

      iex> Content.upsert_from_file("case_study", %{"url" => "my-case-study", "locale" => "fr", "title" => "Mon Étude de Cas"})
      {:ok, %CaseStudy{...}}
  """
  @spec upsert_from_file(atom() | String.t(), map()) ::
          {:ok, Note.t() | CaseStudy.t()} | {:error, any()}
  def upsert_from_file(content_type, attrs) when is_atom(content_type) do
    upsert_from_file(Atom.to_string(content_type), attrs)
  end

  def upsert_from_file(content_type, attrs) when is_binary(content_type) do
    Logger.info(
      "Upserting #{content_type} with URL: #{attrs["url"]} and locale: #{attrs["locale"]}"
    )

    EntryManager.upsert_from_file(content_type, attrs)
  end

  @doc """
  Extracts the locale from a file path.

  ## Parameters
    - file_path: String representing the path to the markdown file

  ## Returns
    - {:ok, locale} if the locale is successfully extracted
    - {:error, :invalid_file_path} if the locale cannot be extracted
  """
  @spec extract_locale(String.t()) ::
          {:ok, String.t()} | {:error, :invalid_file_path}
  def extract_locale(file_path) when is_binary(file_path) do
    Logger.debug("Extracting locale from file path: #{file_path}")

    case Regex.run(~r/\/(\w{2})\/[^\/]+\.md$/, file_path) do
      [_, locale] ->
        Logger.debug("Extracted locale: #{locale}")
        {:ok, locale}

      _ ->
        Logger.error("Failed to extract locale from file path: #{file_path}")
        {:error, :invalid_file_path}
    end
  end

  def extract_locale(file_path) do
    Logger.error("Invalid file path type: #{inspect(file_path)}")
    {:error, :invalid_file_path}
  end
end
```

# /srv/famichat/backend/lib/famichat/content/types.ex

```ex
defmodule Famichat.Content.Types do
  @moduledoc """
  Provides utilities for managing content types in the Famichat application.

  This module serves as the single source of truth for content types,
  their associated paths, and schema mappings.
  """
  require Logger

  @typedoc "Represents the content type as a string"
  @type content_type :: String.t()

  @typedoc "Represents a file path as a string"
  @type file_path :: String.t()

  def content_base_path do
    Application.get_env(:famichat, :content_base_path, "priv/content")
  end

  def content_types do
    %{
      "note" => %{
        slugs: ["notes", "note"],
        path: Path.join(content_base_path(), "note")
      },
      "case_study" => %{
        slugs: ["case-studies", "case_study", "case-study"],
        path: Path.join(content_base_path(), "case-study")
      }
    }
  end

  @spec get_supported_locales() :: [String.t()]
  def get_supported_locales do
    Application.get_env(:famichat, :supported_locales, ["en"])
  end

  @doc """
  Returns the file path for a given content type and locale.

  ## Parameters

    * `content_type` - The content type
    * `locale` - The locale (default: Application.get_env(:famichat, :default_locale, "en"))

  ## Returns

    * The file path as a string if found, otherwise `nil`

  ## Examples

      iex> Famichat.Content.Types.get_path("note", "en")
      "priv/content/note/en"

      iex> Famichat.Content.Types.get_path("invalid", "en")
      nil

  """
  @spec get_path(content_type()) :: file_path() | nil
  def get_path(content_type) do
    case content_types()[content_type] do
      nil -> nil
      %{path: path} -> path
    end
  end

  @doc """
  Determines the content type based on the given file path.

  ## Parameters

    * `file_path` - The path of the file to check

  ## Returns

    * The content type as a string if found, otherwise `nil`

  ## Examples

      iex> Famichat.Content.Types.get_type("/path/to/priv/content/note/en/example.md")
      "note"

      iex> Famichat.Content.Types.get_type("/path/to/unknown/example.md")
      nil

  """
  @spec get_type(file_path()) ::
          {:ok, content_type()} | {:error, :unknown_content_type}
  def get_type(file_path) do
    path_components = Path.split(file_path)
    slug_map = build_slug_map()

    result =
      Enum.find_value(path_components, fn component ->
        slug_map[component]
      end)

    case result do
      nil ->
        Logger.warning("Unrecognized content type for path: #{file_path}")
        {:error, :unknown_content_type}

      type ->
        Logger.debug("Successfully determined content type: #{type}")
        {:ok, type}
    end
  end

  defp build_slug_map do
    Enum.reduce(content_types(), %{}, fn {type, %{slugs: slugs}}, acc ->
      Enum.reduce(slugs, acc, fn slug, inner_acc ->
        Map.put(inner_acc, slug, type)
      end)
    end)
  end

  @doc """
  Returns a list of all defined content types.

  ## Returns

    * A list of content types as strings

  ## Examples

      iex> Famichat.Content.Types.all_types()
      ["note", "case_study"]

  """
  @spec all_types() :: [content_type()]
  def all_types, do: Map.keys(content_types())

  @doc """
  Checks if the given type is a valid content type.

  ## Parameters

    * `type` - The type to check

  ## Returns

    * `true` if the type is valid, `false` otherwise

  ## Examples

      iex> Famichat.Content.Types.valid_type?("note")
      true

      iex> Famichat.Content.Types.valid_type?("invalid")
      false

  """
  @spec valid_type?(content_type()) :: boolean()
  def valid_type?(type), do: type in all_types()

  @doc """
  Returns the schema module associated with the given content type.

  ## Parameters

    * `type` - The content type

  ## Returns

    * The schema module if found, otherwise `{:error, :invalid_content_type}`

  ## Examples

      iex> Famichat.Content.Types.get_schema("note")
      Famichat.Content.Schemas.Note

      iex> Famichat.Content.Types.get_schema("invalid")
      {:error, :invalid_content_type}

  """
  @spec get_schema(content_type() | atom()) ::
          module() | {:error, :invalid_content_type}
  def get_schema(type) when is_atom(type), do: get_schema(Atom.to_string(type))

  def get_schema(type) when is_binary(type) do
    Logger.debug("Getting schema for type: #{inspect(type)}")

    case type do
      "note" ->
        Logger.debug(
          "Found note schema, returning: #{inspect(Famichat.Content.Schemas.Note)}"
        )

        Famichat.Content.Schemas.Note

      "case_study" ->
        Logger.debug(
          "Found case study schema, returning: #{inspect(Famichat.Content.Schemas.CaseStudy)}"
        )

        Famichat.Content.Schemas.CaseStudy

      _ ->
        Logger.error("No schema found for type: #{inspect(type)}")
        {:error, :invalid_content_type}
    end
  end
end
```

# /srv/famichat/backend/lib/famichat/content/utils/metadata_calculator.ex

```ex
defmodule Famichat.Content.Utils.MetadataCalculator do
  @moduledoc """
  Provides utilities for calculating metadata of markdown content, including word count, image count,
  code word count, and estimated reading times based on locale-specific reading speeds.

  ## Functions

    - `calculate/2`: Calculates metadata for given content and locale.
    - `word_count/2`: Counts words or characters in the content based on locale.
    - `image_count/1`: Counts images in the markdown content.
    - `read_time/3`: Calculates estimated read time based on content metrics and locale.

  ## Example

      iex> content = "# Hello World\\nThis is a sample markdown with an image ![Alt text](image.png)."
      iex> Famichat.Content.Utils.MetadataCalculator.calculate(content, "en")
      {:ok, %{
        word_count: 6,
        image_count: 1,
        code_word_count: 0,
        non_native_read_time_seconds: 80,
        native_read_time_seconds: 70
      }}
  """

  require Logger

  # seconds per image
  @image_read_time_seconds 10

  @reading_configs Application.compile_env!(:famichat, __MODULE__)[
                     :reading_configs
                   ]

  @doc """
  Calculates word/character count, code word count, image count, and estimated read times.

  ## Parameters

    - `content`: The markdown content to analyze.
    - `locale`: The locale identifier used for reading speed configurations.

  ## Returns

    - `{:ok, result_map}` on success.
    - `{:error, message}` if the locale is unsupported.

  The `result_map` includes:
    - `word_count` or `character_count`
    - `code_word_count`
    - `image_count`
    - `native_read_time_seconds`
    - `non_native_read_time_seconds`
  """
  @spec calculate(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def calculate(content, locale) do
    case get_reading_config(locale) do
      {:ok, reading_config} ->
        # Parse the markdown content into an AST using EarmarkParser
        {:ok, ast, _} = Earmark.Parser.as_ast(content)

        text_count_map = calculate_text_count(ast, reading_config)
        code_word_count = calculate_code_count(ast)
        image_count = image_count_from_ast(ast)

        reading_speeds = %{
          native: %{
            text: reading_config.native_reading_speed,
            code: reading_config.code_reading_speed
          },
          non_native: %{
            text: reading_config.non_native_reading_speed,
            code: reading_config.code_reading_speed
          }
        }

        non_native_time_seconds =
          read_time_seconds(
            text_count_map,
            code_word_count,
            image_count,
            reading_speeds.non_native
          )

        native_time_seconds =
          read_time_seconds(
            text_count_map,
            code_word_count,
            image_count,
            reading_speeds.native
          )

        result =
          Map.merge(
            %{
              image_count: image_count,
              code_word_count: code_word_count,
              non_native_read_time_seconds: non_native_time_seconds,
              native_read_time_seconds: native_time_seconds
            },
            text_count_map
          )

        {:ok, result}

      {:error, message} ->
        {:error, message}
    end
  end

  # Configuration Functions

  @doc false
  @spec get_reading_config(String.t()) :: {:ok, map()} | {:error, String.t()}
  defp get_reading_config(locale) do
    case @reading_configs[locale] do
      nil -> {:error, "Unsupported locale: #{locale}"}
      config -> {:ok, config}
    end
  end

  # Calculation Functions

  @doc false
  @spec calculate_text_count(list(), map()) :: map()
  defp calculate_text_count(ast, %{counting_method: :words} = _config) do
    text =
      extract_text_from_ast(ast, exclude_code: true)
      |> Enum.join(" ")

    word_count =
      text
      |> String.split(~r/\s+/)
      |> Enum.count(fn token ->
        token != "" and word_token?(token)
      end)

    %{word_count: word_count}
  end

  @doc false
  @spec calculate_text_count(list(), map()) :: map()
  defp calculate_text_count(ast, %{counting_method: :characters} = _config) do
    text =
      extract_text_from_ast(ast, exclude_code: true)
      |> Enum.join("")
      |> String.replace(~r/\s+/, "")
      # Exclude certain punctuation
      |> String.replace(~r/[、。！？：「」（）【】]/u, "")

    char_count = String.length(text)
    %{character_count: char_count}
  end

  @doc false
  @spec calculate_code_count(list()) :: integer()
  defp calculate_code_count(ast) do
    code_text =
      extract_code_from_ast(ast)
      |> Enum.join(" ")

    code_word_count =
      code_text
      |> String.split(~r/\s+/)
      |> Enum.count(&(&1 != ""))

    code_word_count
  end

  @doc false
  @spec read_time_seconds(map(), integer(), integer(), map()) :: integer()
  defp read_time_seconds(text_count_map, code_word_count, image_count, %{
         text: text_speed,
         code: code_speed
       }) do
    image_time = image_count * @image_read_time_seconds
    text_count = Map.values(text_count_map) |> hd()

    text_read_time = Float.ceil(text_count / text_speed * 60)

    code_read_time =
      if code_word_count > 0 do
        Float.ceil(code_word_count / code_speed * 60)
      else
        0
      end

    trunc(text_read_time + code_read_time + image_time)
  end

  # AST Parsing and Extraction Functions

  @doc false
  @spec extract_text_from_ast(any(), keyword()) :: [String.t()]
  defp extract_text_from_ast(ast, opts \\ [])

  defp extract_text_from_ast(ast, opts) do
    exclude_code = Keyword.get(opts, :exclude_code, false)
    do_extract_text_from_ast(ast, exclude_code)
  end

  @doc false
  @spec do_extract_text_from_ast(any(), boolean()) :: [String.t()]
  defp do_extract_text_from_ast([head | tail], exclude_code) do
    do_extract_text_from_ast(head, exclude_code) ++
      do_extract_text_from_ast(tail, exclude_code)
  end

  defp do_extract_text_from_ast({"code", _, _, _}, true), do: []
  defp do_extract_text_from_ast({"pre", _, _, _}, true), do: []

  defp do_extract_text_from_ast({_tag, _attrs, children, _meta}, exclude_code) do
    do_extract_text_from_ast(children, exclude_code)
  end

  defp do_extract_text_from_ast(text, _exclude_code) when is_binary(text),
    do: [text]

  defp do_extract_text_from_ast(_other, _exclude_code), do: []

  @doc false
  @spec extract_code_from_ast(any()) :: [String.t()]
  defp extract_code_from_ast(ast)

  defp extract_code_from_ast([head | tail]) do
    extract_code_from_ast(head) ++ extract_code_from_ast(tail)
  end

  defp extract_code_from_ast({"code", _attrs, content, _meta}) do
    extract_text(content)
  end

  defp extract_code_from_ast({"pre", _attrs, content, _meta}) do
    extract_text(content)
  end

  defp extract_code_from_ast({_tag, _attrs, _children, _meta}), do: []
  defp extract_code_from_ast(_), do: []

  @doc false
  @spec extract_text(any()) :: [String.t()]
  defp extract_text(content) when is_list(content) do
    Enum.flat_map(content, &extract_text/1)
  end

  defp extract_text({_, _, children, _}) do
    extract_text(children)
  end

  defp extract_text(text) when is_binary(text), do: [text]
  defp extract_text(_), do: []

  @doc false
  @spec image_count_from_ast(any()) :: integer()
  defp image_count_from_ast(ast) do
    Enum.reduce(ast, 0, fn
      {"img", _, _, _}, acc ->
        acc + 1

      {"figure", _, _, _}, acc ->
        acc + 1

      {_tag, _attrs, children, _meta}, acc ->
        acc + image_count_from_ast(children)

      _, acc ->
        acc
    end)
  end

  # Utility Functions

  @doc """
  Counts words or characters in the content based on locale.

  ## Parameters

    - `content`: The markdown content to analyze.
    - `locale`: The locale to determine counting method.

  ## Returns

    - `{:ok, integer()}`: The word or character count.
    - `{:error, message}` if the locale is unsupported.
  """
  @spec word_count(String.t(), String.t()) ::
          {:ok, integer()} | {:error, String.t()}
  def word_count(content, locale) do
    case get_reading_config(locale) do
      {:ok, config} ->
        {:ok, ast, _} = Earmark.Parser.as_ast(content)
        count_map = calculate_text_count(ast, config)
        {:ok, Map.values(count_map) |> hd()}

      {:error, message} ->
        {:error, message}
    end
  end

  @doc """
  Counts images in the markdown content.

  ## Parameters

    - `content`: The markdown content to analyze.

  ## Returns

    - `integer()`: The number of images found.
  """
  @spec image_count(String.t()) :: integer()
  def image_count(content) do
    {:ok, ast, _} = Earmark.Parser.as_ast(content)
    image_count_from_ast(ast)
  end

  @doc """
  Calculates read time based on count, image count, and locale.

  ## Parameters

    - `count`: The word or character count, depending on locale.
    - `image_count`: The number of images in the content.
    - `locale`: The locale identifier.

  ## Returns

    - `{:ok, %{min: integer(), max: integer()}}`: A map with min and max read times in seconds.
    - `{:error, message}` if the locale is unsupported.
  """
  @spec read_time(integer(), integer(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def read_time(count, image_count, locale) do
    case get_reading_config(locale) do
      {:ok, config} ->
        image_time = image_count * @image_read_time_seconds

        non_native_time = count / config.non_native_reading_speed * 60
        native_time = count / config.native_reading_speed * 60

        {:ok,
         %{
           min: trunc(Float.ceil(native_time + image_time)),
           max: trunc(Float.ceil(non_native_time + image_time))
         }}

      {:error, message} ->
        {:error, message}
    end
  end

  @doc """
  Determines if a token is considered a word token.

  ## Parameters

    - `token`: The string token to evaluate.

  ## Returns

    - `true` if the token contains letters or numbers.
    - `false` otherwise.
  """
  @spec word_token?(String.t()) :: boolean()
  def word_token?(token) do
    # Matches tokens containing at least one letter or number
    Regex.match?(~r/\p{L}|\p{N}/u, token)
  end
end
```

# /srv/famichat/backend/lib/famichat/content/markdown_rendering/custom_parser.ex

```ex
defmodule Famichat.Content.MarkdownRendering.CustomParser do
  @moduledoc """
  Parses markdown content into a custom AST using Earmark with extended syntax.
  """

  require Logger

  @doc """
  Parses the given markdown string into an AST.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(markdown) when is_binary(markdown) do
    {frontmatter, content} = split_frontmatter(markdown)

    # Step 1: Preprocess custom components in the content
    content = preprocess_custom_components(content)

    case Earmark.Parser.as_ast(content) do
      {:ok, ast, _} ->
        # Step 2: Process the AST to transform nodes and annotate the first paragraph
        processed_ast = process_ast(ast)

        {:ok,
         %{
           frontmatter: frontmatter,
           ast: processed_ast
         }}

      {:error, _ast, error_messages} ->
        Logger.error("Error parsing markdown: #{inspect(error_messages)}")
        {:error, "Error parsing markdown"}
    end
  end

  def split_frontmatter(markdown) do
    result = String.split(markdown, ~r/---\s*\n/, parts: 3)

    case result do
      ["", frontmatter, content] ->
        {frontmatter, content}

      _ ->
        {"", markdown}
    end
  end

  defp preprocess_custom_components(content) do
    content
    |> preprocess_custom_images()

    # Add more custom component preprocessing here
  end

  defp preprocess_custom_images(content) do
    Regex.replace(~r/!\[(.*?)\]\((.*?)\){(.*?)}/, content, fn _,
                                                              alt,
                                                              src,
                                                              attrs ->
      "{:custom_image, #{inspect(alt)}, #{inspect(src)}, #{inspect(parse_attrs(attrs))}}"
    end)
  end

  defp parse_attrs(attrs) do
    attrs
    |> String.split()
    |> Enum.map(fn attr ->
      [key, value] = String.split(attr, "=")
      {key, String.trim(value, "\"")}
    end)
    |> Enum.into(%{})
  end

  defp process_ast(ast) do
    # Introduce a state to track if the first paragraph is found
    {processed_ast, _state} = Enum.map_reduce(ast, %{first_paragraph_found: false}, &process_node/2)
    processed_ast
  end

  defp process_node({tag, attrs, content, meta}, state)
       when tag in ["h1", "h2", "h3", "h4", "h5", "h6", "p"] do
    default_attrs = get_default_typography_attrs(tag)
    merged_attrs = Map.merge(attrs |> Enum.into(%{}), default_attrs)
    {processed_content, state} = process_ast_with_state(content, state)

    # Annotate the first paragraph
    {dropcap, new_state} =
      if tag == "p" and not state.first_paragraph_found do
        {true, %{state | first_paragraph_found: true}}
      else
        {false, state}
      end

    meta = if dropcap, do: Map.put(meta, :dropcap, true), else: meta

    node = {:typography, tag, merged_attrs, processed_content, meta}
    {node, new_state}
  end

  defp process_node({tag, attrs, content, meta}, state) do
    {processed_content, state} = process_ast_with_state(content, state)
    node = {tag, attrs, processed_content, meta}
    {node, state}
  end

  defp process_node(content, state) when is_binary(content), do: {content, state}

  defp process_ast_with_state(ast_list, state) do
    Enum.map_reduce(ast_list, state, &process_node/2)
  end

  defp get_default_typography_attrs("h1"), do: %{font: "cardinal", size: "4xl"}
  defp get_default_typography_attrs("h2"), do: %{font: "cardinal", size: "3xl"}
  defp get_default_typography_attrs("h3"), do: %{font: "cardinal", size: "2xl"}
  defp get_default_typography_attrs("h4"), do: %{size: "1xl"}
  defp get_default_typography_attrs("h5"), do: %{size: "1xs"}
  defp get_default_typography_attrs("h6"), do: %{size: "1xs"}
  defp get_default_typography_attrs("p"), do: %{size: "md"}
  defp get_default_typography_attrs(_), do: %{}
end
```

# /srv/famichat/backend/lib/famichat/content/markdown_rendering/renderer.ex

```ex
defmodule Famichat.Content.MarkdownRendering.Renderer do
  @moduledoc """
  Handles the rendering and caching of markdown content to HTML.

  This module provides functions to parse markdown content, transform it into
  a schema-specific AST, render it as HTML, and cache the results. It supports
  different content types and provides options for customizing the rendering process.

  ## Examples

      iex> markdown = "# Hello, world!"
      iex> Renderer.render_and_cache(markdown, :note, "note_1")
      {:ok, "<h1>Hello, world!</h1>"}
  """
  alias Famichat.Content.Types
  alias Famichat.Content.MarkdownRendering.{CustomParser, HTMLCompiler}
  alias Famichat.Cache
  require Logger

  @type content_type :: Types.content_type()
  @type render_option ::
          {:include_frontmatter, boolean()} | {:force_refresh, boolean()}
  @type render_options :: [render_option()]
  @cache_ttl :timer.hours(24 * 30)

  @doc """
  Renders markdown to HTML and caches the result.

  ## Parameters

    * `markdown` - The markdown content to render.
    * `content_type` - The type of content being rendered.
    * `content_id` - A unique identifier for the content (used for caching).
    * `opts` - A keyword list of options.

  ## Options

    * `:force_refresh` - Force a re-render even if cached content exists.
    * `:include_frontmatter` - Include frontmatter in the rendered output.

  ## Returns

    * `{:ok, html}` - The rendered HTML content.
    * `{:error, reason}` - An error occurred during rendering.
  """
  @spec render_and_cache(
          String.t(),
          Types.content_type(),
          String.t(),
          render_options()
        ) ::
          {:ok, String.t()} | {:error, atom()}
  def render_and_cache(content, content_type, content_id, opts \\ []) do
    cache_key = "compiled_content:#{content_id}"
    force_refresh = Keyword.get(opts, :force_refresh, false)
    bypass_cache = Keyword.get(opts, :bypass_cache, false)
    # Only render markdown fields by default
    is_markdown = Keyword.get(opts, :is_markdown, true)

    Logger.debug(
      "Rendering and caching for content_id: #{content_id}, content_type: #{content_type}"
    )

    Logger.debug("Content: #{inspect(String.slice(content, 0, 50))}...")

    case Cache.exists?(cache_key, bypass_cache: bypass_cache) do
      :cache_disabled ->
        Logger.debug(
          "Cache is disabled. Rendering without caching for content_id: #{content_id}"
        )

        do_render(content, content_type, is_markdown)

      :cache_bypassed ->
        Logger.debug("Cache bypassed for content_id: #{content_id}")
        do_render(content, content_type, is_markdown)

      true when not (bypass_cache or force_refresh) ->
        Logger.debug("Cache exists for content_id: #{content_id}")

        case Cache.get(cache_key) do
          {:ok, cached_content} when is_binary(cached_content) ->
            Logger.debug(
              "Returning cached content for content_id: #{content_id}"
            )

            {:ok, cached_content}

          _ ->
            Logger.warning(
              "Cached value is invalid for content_id: #{content_id}. Re-rendering."
            )

            do_render_and_cache(
              content,
              content_type,
              cache_key,
              opts,
              is_markdown
            )
        end

      false ->
        Logger.debug(
          "Cache doesn't exist for content_id: #{content_id}. Rendering and caching."
        )

        do_render_and_cache(content, content_type, cache_key, opts, is_markdown)

      _ ->
        Logger.debug(
          "Unexpected cache state or refresh forced for content_id: #{content_id}. Rendering and caching."
        )

        do_render_and_cache(content, content_type, cache_key, opts, is_markdown)
    end
  end

  @doc """
  Invalidates the cache for a specific content item.

  ## Parameters

    * `content_id` - The unique identifier for the content.

  ## Returns

    * `:ok` - If the cache was successfully invalidated.
  """
  @spec invalidate_cache(String.t()) :: :ok
  def invalidate_cache(content_id) do
    cache_key = "compiled_content:#{content_id}"

    case Cache.delete(cache_key) do
      :cache_disabled ->
        Logger.debug(
          "Cache is disabled. No need to invalidate for content_id: #{content_id}"
        )

      :cache_bypassed ->
        Logger.debug(
          "Cache bypassed. No invalidation performed for content_id: #{content_id}"
        )

      {:ok, _} ->
        Logger.debug("Cache invalidated for content_id: #{content_id}")

      {:error, reason} ->
        Logger.error(
          "Failed to invalidate cache for content_id: #{content_id}. Reason: #{inspect(reason)}"
        )
    end

    :ok
  end

  # Private functions
  @spec do_render_and_cache(
          String.t(),
          Types.content_type(),
          String.t(),
          render_options(),
          boolean()
        ) ::
          {:ok, String.t()} | {:error, atom()}
  defp do_render_and_cache(markdown, content_type, cache_key, opts, is_markdown) do
    Logger.debug(
      "Rendering markdown for cache_key: #{cache_key}, content_type: #{content_type}"
    )

    case do_render(markdown, content_type, is_markdown) do
      {:ok, html} ->
        Logger.debug("Successfully rendered HTML for cache_key: #{cache_key}")

        case Cache.put(cache_key, html, ttl: @cache_ttl) do
          :cache_disabled ->
            Logger.debug(
              "Cache is disabled. Content rendered but not cached for cache_key: #{cache_key}"
            )

          :cache_bypassed ->
            Logger.debug(
              "Cache bypassed. Content rendered but not cached for cache_key: #{cache_key}"
            )

          {:ok, true} ->
            Logger.debug(
              "Content successfully cached for cache_key: #{cache_key}"
            )

          {:error, reason} ->
            Logger.warning(
              "Failed to cache content for cache_key: #{cache_key}. Reason: #{inspect(reason)}"
            )
        end

        {:ok, html}

      error ->
        error
    end
  end

  @spec do_render(String.t(), content_type(), boolean()) ::
          {:ok, String.t()} | {:error, atom()}
  defp do_render(content, content_type, is_markdown) do
    if is_markdown do
      case convert_markdown_to_html(content, content_type) do
        {:ok, html} when is_binary(html) and html != "" ->
          {:ok, html}

        {:ok, ""} ->
          Logger.warning("Rendered content is empty")
          {:error, :empty_content}

        error ->
          error
      end
    else
      {:ok, content}
    end
  end

  @spec convert_markdown_to_html(String.t(), content_type()) ::
          {:ok, String.t()} | {:error, atom()}
  defp convert_markdown_to_html(markdown, content_type) do
    Logger.debug(
      "Converting markdown to HTML for content_type: #{content_type}"
    )

    with {:ok, custom_ast} <- CustomParser.parse(markdown),
         {:ok, html} <-
           HTMLCompiler.render(custom_ast, content_type: content_type) do
      Logger.debug("Successfully converted markdown to HTML")
      {:ok, html}
    else
      {:error, reason} ->
        Logger.error("Error converting markdown to HTML: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

# /srv/famichat/backend/lib/famichat/content/markdown_rendering/html_compiler.ex

```ex
defmodule Famichat.Content.MarkdownRendering.HTMLCompiler do
  @moduledoc """
  Renders the schema-specific Abstract Syntax Tree (AST) to HTML, including custom UI components.

  This module provides functionality to transform an AST representation of content
  into HTML, handling both standard HTML tags and custom components like images.
  """

  require Logger
  alias FamichatWeb.Components.TypographyHelpers

  @type ast_node ::
          {binary(), list(), list() | binary(), map()}
          | {:custom_image, binary(), binary(), map()}
          | binary()
  @type render_opts :: keyword()

  @doc """
  Renders the given content AST to HTML.

  ## Parameters
    - content: A map containing the AST to be rendered.
    - opts: Optional keyword list of rendering options (currently unused).

  ## Returns
    - `{:ok, html}` if rendering is successful, where `html` is the rendered HTML string.
    - `{:error, reason}` if rendering fails, where `reason` is an error message.
  """
  @spec render(map(), render_opts()) :: {:ok, String.t()} | {:error, String.t()}
  def render(content, opts \\ [])

  def render(%{ast: ast}, _opts) when is_list(ast) do
    html = Enum.map_join(ast, "", &transform/1)
    {:ok, html}
  end

  def render(_, _opts) do
    Logger.error("Invalid content provided to HTMLCompiler")
    {:error, "Invalid content"}
  end

  @doc """
  Transforms an AST node into its HTML representation.

  ## Parameters
    - node: An AST node to be transformed.

  ## Returns
    - A string or list of strings representing the HTML for the given node.
  """
  @spec transform(ast_node()) :: String.t() | [String.t()]
  def transform({tag, attrs, content, _meta}) when is_binary(tag) do
    attributes = transform_attributes(attrs)
    transformed_content = transform_content(content)
    ["<#{tag}#{attributes}>", transformed_content, "</#{tag}>"]
  end

  # coveralls-ignore-start
  def transform({:custom_image, alt, src, attrs}) do
    Logger.info("Rendering custom image: #{src}")
    caption = Map.get(attrs, "caption", "")
    srcset = Map.get(attrs, "srcset", "")

    """
    <figure class="responsive-image">
      <img src="#{src}" alt="#{alt}" srcset="#{srcset}">
      <figcaption>#{caption}</figcaption>
    </figure>
    """
  end

  # coveralls-ignore-stop
  # TODO: This seems to run on every save.
  def transform({:typography, tag, attrs, content, _meta}) do
    # Merge default attributes with any existing ones
    assigns =
      Map.new(attrs)
      |> Map.put_new(:tag, tag)
      |> Map.put_new(:size, get_size_for_tag(tag))

    # Build the class names using TypographyHelpers
    class_name = TypographyHelpers.build_class_names(assigns)

    # Generate additional attributes (except :class and :tag)
    attributes = generate_additional_attributes(assigns)

    # Transform the inner content
    transformed_content = transform_content(content)

    # Construct the HTML string
    [
      "<#{assigns.tag} class=\"#{class_name}\"#{attributes}>",
      transformed_content,
      "</#{assigns.tag}>"
    ]
  end

  def transform(content) when is_binary(content), do: content

  @spec transform_attributes(list({String.t(), String.t()})) :: String.t()
  defp transform_attributes(attrs) do
    Enum.map_join(attrs, "", fn {key, value} -> " #{key}=\"#{value}\"" end)
  end

  @spec transform_content(list(ast_node()) | String.t()) :: String.t()
  defp transform_content(content) when is_list(content) do
    Enum.map_join(content, "", &transform/1)
  end

  defp transform_content(content) when is_binary(content), do: content

  defp get_size_for_tag(tag) do
    case tag do
      "h1" -> "4xl"
      "h2" -> "3xl"
      "h3" -> "2xl"
      "h4" -> "1xl"
      "h5" -> "1xl"
      "h6" -> "md"
      "p" -> "md"
      _ -> ""
    end
  end

  defp generate_additional_attributes(assigns) do
    assigns
    |> Map.drop([:tag, :size, :font, :color, :center, :class])
    |> Enum.map_join("", fn {key, value} -> " #{key}=\"#{value}\"" end)
  end
end
```

# /srv/famichat/backend/lib/famichat/content/file_management/reader.ex

```ex
defmodule Famichat.Content.FileManagement.Reader do
  @moduledoc """
  Reads and parses markdown files for content management.

  Extracts content, frontmatter, and metadata from markdown files. Handles
  YAML parsing, content type determination, and locale extraction.
  """
  alias Famichat.Content.Types
  alias Famichat.Content.Utils.MetadataCalculator
  require Logger

  @doc """
  Reads a markdown file and extracts its content, frontmatter, and metadata.

  ## Parameters
    - file_path: String representing the path to the markdown file

  ## Returns
    - {:ok, content_type, attrs} if successful
    - {:error, reason} if an error occurs
  """
  @spec read_markdown_file(String.t()) ::
          {:ok, String.t(), map()} | {:error, term()}
  def read_markdown_file(file_path) do
    with {:ok, content} <- File.read(file_path),
         {:ok, frontmatter, markdown} <- split_frontmatter_and_content(content),
         {:ok, attrs} <- parse_frontmatter(frontmatter),
         {:ok, content_type} <- determine_content_type(file_path),
         locale <- extract_locale(file_path),
         {:ok, metadata} <- MetadataCalculator.calculate(markdown, locale) do
      Logger.info("Read markdown file: #{file_path}")
      Logger.info("Extracted attributes: #{inspect(attrs)}")
      Logger.info("Extracted URL: #{inspect(attrs["url"])}")

      counting_method = get_counting_method(locale)

      word_count =
        case counting_method do
          :characters -> metadata.character_count
          :words -> metadata.word_count
          _ -> metadata.word_count || metadata.character_count
        end

      Logger.debug("READER: Metadata: #{inspect(metadata)}")
      Logger.debug("READER: Locale: #{locale}")
      Logger.debug("READER: Counting method: #{get_counting_method(locale)}")

      {:ok, content_type,
       Map.merge(attrs, %{
         "content" => markdown,
         "file_path" => file_path,
         "locale" => locale,
         "url" => attrs["url"],
         "word_count" => word_count,
         "read_time" => metadata.native_read_time_seconds
       })}
    else
      {:error, reason} = error ->
        Logger.error(
          "Error reading markdown file: #{file_path}, error: #{inspect(reason)}"
        )

        error
    end
  end

  @spec split_frontmatter_and_content(String.t()) ::
          {:ok, String.t(), String.t()} | {:error, atom()}
  defp split_frontmatter_and_content(content) do
    case String.split(content, ~r/---\s*\n/, parts: 3) do
      ["", frontmatter, markdown] -> {:ok, frontmatter, markdown}
      # Corrected atom syntax
      _ -> {:error, :invalid_markdown_format}
    end
  end

  @spec parse_frontmatter(String.t()) :: {:ok, map()} | {:error, tuple()}
  defp parse_frontmatter(frontmatter) do
    if Application.get_env(:famichat, :environment) in [:dev, :test] do
      case :yamerl_constr.string(frontmatter) do
        [metadata] ->
          {:ok, Enum.into(metadata, %{}, &transform_metadata/1)}

        error ->
          Logger.error(
            "YAML parsing failed. Frontmatter: #{frontmatter}, Error: #{inspect(error)}"
          )

          {:error, {:yaml_parsing_failed, error}}
      end
    else
      {:ok, %{}}
    end
  end

  @spec determine_content_type(String.t()) ::
          {:ok, String.t()} | {:error, :unknown_content_type}
  defp determine_content_type(file_path) do
    case Types.get_type(file_path) do
      {:ok, type} ->
        {:ok, type}

      {:error, :unknown_content_type} = error ->
        Logger.error("Unable to determine content type for: #{file_path}")
        error
    end
  end

  defp extract_locale(file_path) do
    supported_locales = Types.get_supported_locales()
    default_locale = Application.get_env(:famichat, :default_locale, "en")

    file_path
    |> Path.split()
    |> Enum.map(&Path.rootname/1)
    |> Enum.find(default_locale, &(&1 in supported_locales))
  end

  @spec transform_metadata({charlist() | atom(), charlist() | term()}) ::
          {String.t(), String.t() | [String.t()] | term()}
  defp transform_metadata({charlist_key, charlist_value})
       when is_list(charlist_key) and is_list(charlist_value) do
    key = List.to_string(charlist_key)
    value = transform_value(charlist_value)
    {key, value}
  end

  defp transform_metadata({key, charlist_value}) when is_list(charlist_value),
    do: {to_string(key), List.to_string(charlist_value)}

  defp transform_metadata({charlist_key, value}) when is_list(charlist_key),
    do: {List.to_string(charlist_key), value}

  defp transform_metadata({key, value}), do: {to_string(key), value}

  @spec transform_value(charlist() | [charlist()]) :: String.t() | [String.t()]
  defp transform_value([first | _] = charlist_value) when is_list(first) do
    Enum.map(charlist_value, &List.to_string/1)
  end

  defp transform_value(charlist_value) when is_list(charlist_value) do
    List.to_string(charlist_value)
  end

  @spec get_counting_method(String.t()) :: atom()
  defp get_counting_method(locale) do
    reading_configs =
      Application.get_env(
        :famichat,
        Famichat.Content.Utils.MetadataCalculator
      )[:reading_configs]

    Logger.debug("Reading configs: #{inspect(reading_configs)}")

    case Map.get(reading_configs, locale) do
      %{counting_method: method} -> method
      # Default to :words if not specified
      _ -> :words
    end
  end
end
```

# /srv/famichat/backend/lib/famichat/content/file_management/watcher.ex

```ex
defmodule Famichat.Content.FileManagement.Watcher do
  @moduledoc """
  Monitors file system changes for markdown content files.

  Uses FileSystem to watch specified directories, processes relevant file events,
  and triggers content updates through the Reader module and Content context.
  """

  use GenServer
  require Logger
  alias Famichat.Content.FileManagement.Reader
  alias Famichat.Content

  defstruct [:watcher_pid]

  @type t :: %__MODULE__{
          watcher_pid: pid()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    Logger.info("Attempting to start Watcher with opts: #{inspect(opts)}")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    Logger.debug("Watcher init opts: #{inspect(opts)}")
    paths = Keyword.get(opts, :paths, [])
    {:ok, watcher_pid} = FileSystem.start_link(dirs: paths)
    FileSystem.subscribe(watcher_pid)
    {:ok, %__MODULE__{watcher_pid: watcher_pid}}
  end

  @spec handle_info(tuple(), t()) :: {:noreply, t()}
  def handle_info(
        {:file_event, watcher_pid, {path, events}},
        %{watcher_pid: watcher_pid} = state
      ) do
    Logger.info("File event detected: #{path}, events: #{inspect(events)}")

    Logger.info(
      "Is relevant file change? #{relevant_file_change?(path, events)}"
    )

    if relevant_file_change?(path, events) do
      Logger.info("Processing file change for: #{path}")
      process_file_change(path)
    end

    {:noreply, state}
  end

  @spec relevant_file_change?(String.t(), list()) :: boolean()
  defp relevant_file_change?(path, events) do
    not hidden_path?(path) and
      Path.extname(path) == ".md" and
      (:modified in events or :created in events)
  end

  defp hidden_path?(path) do
    path
    |> Path.split()
    |> Enum.any?(fn part -> String.starts_with?(part, ".") end)
  end

  @spec process_file_change(String.t()) :: :ok
  defp process_file_change(path) do
    case Reader.read_markdown_file(path) do
      {:ok, content_type, attrs} ->
        case Content.upsert_from_file(content_type, attrs) do
          {:ok, _content} ->
            Logger.info("Successfully upserted content from file: #{path}")

          {:error, reason} ->
            Logger.error(
              "Error upserting content from file #{path}: #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        Logger.error("Error processing file #{path}: #{inspect(reason)}")
    end

    :ok
  end
end
```

# /srv/famichat/backend/lib/famichat/content/translatable_fields.ex

```ex
defmodule Famichat.Content.TranslatableFields do
  @moduledoc """
  Provides functionality to determine translatable fields for content schemas.

  This module serves as a centralized configuration for managing which fields
  should be translated for each content type in the Famichat application.
  """

  alias Famichat.Content.Schemas.{CaseStudy, Note}

  @type schema :: module()
  @type field :: atom()

  @default_translatable_types [:string, :text, :integer]

  @doc """
  Returns a list of translatable fields for a given schema.

  This function determines which fields of a schema should be considered for
  translation. It applies a default rule (all string and text fields are
  translatable) and then applies any schema-specific rules.

  ## Parameters

    * `schema` - The module representing the Ecto schema

  ## Returns

  A list of atom field names that are considered translatable for the given schema.

  ## Examples

      iex> TranslatableFields.translatable_fields(Famichat.Content.Schemas.CaseStudy)
      [:title, :content, :introduction, :company, :role, :timeline, :platforms]

      iex> TranslatableFields.translatable_fields(Famichat.Content.Schemas.Note)
      [:title, :content, :introduction]
  """
  @spec translatable_fields(schema()) :: [field()]
  def translatable_fields(schema) do
    all_fields = schema.__schema__(:fields)
    default_translatable = default_translatable_fields(schema)

    case schema do
      CaseStudy -> default_translatable -- ([:url] ++ [:platforms])
      Note -> default_translatable
      _ -> default_translatable
    end
  end

  @doc """
  Determines if a specific field in a schema is translatable.

  ## Parameters

    * `schema` - The module representing the Ecto schema
    * `field` - The atom name of the field to check

  ## Returns

  Boolean indicating whether the field is translatable.

  ## Examples

      iex> TranslatableFields.translatable_field?(Famichat.Content.Schemas.CaseStudy, :title)
      true

      iex> TranslatableFields.translatable_field?(Famichat.Content.Schemas.CaseStudy, :read_time)
      false
  """
  @spec translatable_field?(schema(), field()) :: boolean()
  def translatable_field?(schema, field) do
    field in translatable_fields(schema)
  end

  @spec default_translatable_fields(schema()) :: [field()]
  defp default_translatable_fields(schema) do
    schema.__schema__(:fields)
    |> Enum.filter(fn field ->
      schema.__schema__(:type, field) in @default_translatable_types
    end)
  end
end
```

# /srv/famichat/backend/lib/famichat/content/remote/remote_update_trigger.ex

```ex
defmodule Famichat.Content.Remote.RemoteUpdateTrigger do
  @moduledoc """
  Manages remote content updates and triggers file processing.

  This module is responsible for:
  - Syncing remote Git repositories
  - Handling updates for changed files
  - Processing individual files and updating the local content

  It uses `GitContentFetcher` to fetch remote content, `Reader` to parse markdown files,
  and `Watcher` to process file changes.
  """

  alias Famichat.Content.Remote.GitRepoSyncer
  require Logger

  @doc """
  Starts the RemoteUpdateTrigger agent.
  """
  @spec start_link(any()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Triggers an update for a given repository URL.

  ## Parameters

    - repo_url: The URL of the Git repository to update.

  ## Returns

    - `{:ok, :updated}` if the sync was successful.
    - `{:error, reason}` if the sync failed.
  """
  @spec trigger_update(String.t()) :: {:ok, :updated} | {:error, String.t()}
  def trigger_update(repo_url) do
    local_path = Application.get_env(:famichat, :content_base_path)

    case GitRepoSyncer.sync_repo(repo_url, local_path) do
      {:ok, _} ->
        {:ok, :updated}

      {:error, reason} ->
        Logger.error("Failed to sync repository: #{reason}")
        {:error, "Repository sync failed"}
    end
  end
end
```

# /srv/famichat/backend/lib/famichat/content/remote/git_repo_syncer.ex

```ex
defmodule Famichat.Content.Remote.GitRepoSyncer do
  @moduledoc """
  Handles synchronization of a Git repository by cloning or pulling updates.
  """

  require Logger

  @git_env [{"GIT_TERMINAL_PROMPT", "0"}]
  @default_branch "main"

  @type sync_result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Synchronizes the repository by either pulling the latest changes or cloning it.
  """
  @spec sync_repo(String.t(), String.t()) :: sync_result()
  def sync_repo(repo_url, local_path) do
    Logger.info("Starting sync for repo: #{repo_url} at path: #{local_path}")

    result = do_sync_repo(repo_url, local_path)

    Logger.info(
      "Finished sync for repo: #{repo_url} with result: #{inspect(result)}"
    )

    result
  end

  @spec do_sync_repo(String.t(), String.t()) :: sync_result()
  defp do_sync_repo(repo_url, local_path) do
    if repo_exists?(local_path) do
      update_existing_repo(local_path)
    else
      clone_new_repo(repo_url, local_path)
    end
  rescue
    e ->
      Logger.error("Failed to sync repo: #{inspect(e)}")
      {:error, "Failed to sync repo: #{Exception.message(e)}"}
  end

  @spec repo_exists?(String.t()) :: boolean()
  defp repo_exists?(path) do
    Logger.debug("Checking if repo exists at path: #{path}")
    File.dir?(path)
  end

  @spec update_existing_repo(String.t()) :: sync_result()
  defp update_existing_repo(local_path) do
    Logger.info("Updating existing repo at path: #{inspect(local_path)}")

    with {:ok, _} <- fetch_all(local_path),
         {:ok, _} <- reset_to_origin(local_path),
         {:ok, _} <- clean_repo(local_path) do
      {:ok, local_path}
    else
      {:error, reason} ->
        Logger.error("Failed to update repository: #{reason}")
        {:error, "Failed to update repository: #{reason}"}
    end
  end

  @spec clone_new_repo(String.t(), String.t()) :: sync_result()
  defp clone_new_repo(repo_url, local_path) do
    Logger.info("Cloning new repo: #{repo_url} to path: #{local_path}")

    case System.cmd("git", ["clone", repo_url, local_path], env: @git_env) do
      {_, 0} ->
        {:ok, local_path}

      {output, _} ->
        Logger.error("Failed to clone repository: #{output}")
        {:error, "Failed to clone repository: #{output}"}
    end
  end

  @spec fetch_all(String.t()) :: sync_result()
  defp fetch_all(path), do: run_git_command(path, ["fetch", "--all"])

  @spec reset_to_origin(String.t()) :: sync_result()
  defp reset_to_origin(path),
    do: run_git_command(path, ["reset", "--hard", "origin/#{@default_branch}"])

  @spec clean_repo(String.t()) :: sync_result()
  defp clean_repo(path), do: run_git_command(path, ["clean", "-fd"])

  defp run_git_command(path, args) do
    full_args = ["-C", path | args]

    Logger.debug(
      "Running git command. Path: #{inspect(path)}, Args: #{inspect(args)}, Full args: #{inspect(full_args)}"
    )

    Enum.each(full_args, fn arg ->
      Logger.debug("Arg: #{inspect(arg)}, Type: #{inspect(typeof(arg))}")
    end)

    case System.cmd("git", full_args, env: @git_env) do
      {_, 0} -> {:ok, path}
      {output, _} -> {:error, output}
    end
  end

  defp typeof(term) do
    cond do
      is_binary(term) -> "binary"
      is_list(term) -> "list"
      is_atom(term) -> "atom"
      is_integer(term) -> "integer"
      true -> "other"
    end
  end
end
```

# /srv/famichat/backend/lib/famichat/content/schemas/case_study.ex

```ex
defmodule Famichat.Content.Schemas.CaseStudy do
  @moduledoc """
  Defines the schema and behavior for case studies in the Famichat application.
  Extends BaseSchema with additional fields specific to case studies.
  """
  require Logger

  use Famichat.Content.Schemas.BaseSchema,
    schema_name: "case_studies",
    translatable_type: "case_study",
    additional_fields: [:company, :role, :timeline, :platforms, :sort_order],
    do: [
      field(:company, :string),
      field(:role, :string),
      field(:timeline, :string),
      field(:platforms, {:array, :string}),
      field(:sort_order, :integer)
    ]

  @typedoc """
  The CaseStudy type.
  """
  @type t :: %__MODULE__{}

  def custom_render(content) do
    # Add any CaseStudy-specific rendering logic here
    content
  end

  def changeset(case_study, attrs) do
    case_study
    |> super(attrs)
    |> validate_required([:company, :role, :timeline, :platforms, :sort_order])
  end
end
```

# /srv/famichat/backend/lib/famichat/content/schemas/base.ex

```ex
defmodule Famichat.Content.Schemas.BaseSchema do
  @moduledoc """
  Provides a base schema for content types in the Famichat application.
  Defines common fields, validations, and behaviors for content schemas.
  """
  require Logger

  defmacro __using__(opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      alias Famichat.Content.Schemas.Translation
      alias Famichat.Content.MarkdownRendering.Renderer
      alias Famichat.Cache

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
      @max_url_length 255
      @max_title_length unquote(opts[:max_title_length] || 255)

      @markdown_fields unquote(opts[:markdown_fields] || ["content"])

      schema unquote(
               opts[:schema_name] || raise(":schema_name option is required")
             ) do
        field :title, :string
        field :url, :string
        # raw markdown
        field :content, :string
        # compiled html
        field :compiled_content, :string, virtual: true
        field :introduction, :string
        field :read_time, :integer
        field :word_count, :integer
        field :file_path, :string
        field :locale, :string
        field :published_at, :utc_datetime
        field :is_draft, :boolean, default: true

        has_many :translations, Translation, foreign_key: :translatable_id

        timestamps()

        unquote(opts[:do])
      end

      @required_fields [:title, :content, :locale]
      @optional_fields [
        :url,
        :introduction,
        :read_time,
        :file_path,
        :published_at,
        :is_draft,
        :word_count
      ]

      def changeset(struct, attrs) do
        changeset =
          struct
          |> cast(
            attrs,
            @required_fields ++
              @optional_fields ++ unquote(opts[:additional_fields] || [])
          )
          |> validate_required(@required_fields)
          |> validate_length(:title, max: @max_title_length)
          |> validate_length(:url, max: @max_url_length)
          |> unique_constraint(:url)
          |> validate_content()

        changeset
      end

      @spec translatable_type() :: String.t()
      def translatable_type, do: unquote(to_string(opts[:translatable_type]))

      def markdown_fields, do: @markdown_fields

      # Callback for custom rendering in child schemas
      def custom_render(_content), do: nil

      defoverridable changeset: 2, custom_render: 1

      defp validate_content(changeset) do
        case get_change(changeset, :content) do
          nil -> changeset
          content when is_binary(content) -> changeset
          _ -> add_error(changeset, :content, "must be a string")
        end
      end
    end
  end
end
```

# /srv/famichat/backend/lib/famichat/content/schemas/note.ex

```ex
defmodule Famichat.Content.Schemas.Note do
  require Logger

  use Famichat.Content.Schemas.BaseSchema,
    schema_name: "notes",
    translatable_type: "note"

  @moduledoc """
  Defines the schema and behavior for blog notes in the Famichat application.

  This module provides a schema for storing blog notes, inheriting common
  functionality from BaseSchema. It includes features such as:

  - Validation of note attributes including title length
  - Ensuring URL uniqueness

  All fields and validations are inherited from BaseSchema.
  """

  @typedoc """
  The Note type.
  """
  @type t :: %__MODULE__{}

  def custom_render(content) do
    # Add any Note-specific rendering logic here
    content
  end
end
```

# /srv/famichat/backend/lib/famichat/content/schemas/translation.ex

```ex
defmodule Famichat.Content.Schemas.Translation do
  @moduledoc """
  Manages translations for various translatable entities within the application.

  The Translation schema is designed to store localized text for different fields associated with translatable entities. Each translation record includes:
  - The `locale` indicating the language and regional preferences.
  - The `field_name` specifying which field of the entity is translated.
  - The `field_value` containing the actual translated text.
  - The `translatable_id` and `translatable_type` identifying the entity that the translation belongs to.

  This setup allows the application to support multiple languages by fetching the appropriate translations based on the user's selected locale.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          locale: String.t(),
          field_name: String.t(),
          field_value: String.t(),
          translatable_id: Ecto.UUID.t(),
          translatable_type: String.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "translations" do
    field :locale, :string
    field :field_name, :string
    field :field_value, :string
    field :translatable_id, :binary_id
    field :translatable_type, :string

    timestamps()
  end

  @doc false
  def changeset(translation, attrs) do
    translation
    |> cast(attrs, [
      :locale,
      :field_name,
      :field_value,
      :translatable_id,
      :translatable_type
    ])
    |> validate_required([
      :locale,
      :field_name,
      :field_value,
      :translatable_id,
      :translatable_type
    ])
    |> validate_length(:field_name, max: 255)
    |> validate_format(:locale, ~r/^[a-z]{2}(-[A-Z]{2})?$/)
    |> unique_constraint(
      [:translatable_id, :translatable_type, :locale, :field_name],
      name: :translations_unique_index
    )
  end
end
```

# /srv/famichat/backend/lib/famichat/content/managers/entry_manager.ex

```ex
defmodule Famichat.Content.EntryManager do
  @moduledoc """
  Manages the lifecycle of content entries in the Famichat application.

  This module handles creating, updating, deleting, and retrieving content entries
  such as Notes and Case Studies. It serves as an intermediary between the database
  and application logic, coordinating with TranslationManager for non-default locales.
  """
  alias Famichat.Repo
  alias Famichat.Content.Types
  alias Famichat.Content.Schemas.{Note, CaseStudy}
  alias Famichat.Content.TranslationManager
  alias Famichat.Content.MarkdownRendering.Renderer
  import Ecto.Query
  require Logger

  # Wasn't able to debug these dialyzer warnings, but code works as expected.
  @dialyzer [
    {:nowarn_function, compile_content_and_translations: 3},
    {:nowarn_function, compile_content: 3},
    {:nowarn_function, compile_translations: 3},
    {:nowarn_function, get_content_with_translations: 3}
  ]

  @default_locale Application.compile_env(:famichat, :default_locale)
  @type content_type :: Types.content_type()

  @doc """
  Creates a new content entry.

  ## Parameters

    * `attrs` - A map containing the attributes for the new content entry.

  ## Returns

    * `{:ok, content}` if the content was successfully created.
    * `{:error, reason}` if there was an error during creation.
  """
  @spec create_content(map()) ::
          {:ok, Note.t() | CaseStudy.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :invalid_content_type}
          | {:error, any()}
  def create_content(attrs) do
    case get_schema(attrs["content_type"]) do
      {:error, :invalid_content_type} = error ->
        error

      {:ok, schema} ->
        with changeset <- apply_changeset(struct(schema), attrs),
             {:ok, content} <- insert_content(changeset),
             {:ok, compiled_content} <-
               compile_content(content, attrs["content_type"]),
             {:ok, updated_content} <-
               update_compiled_content(content, compiled_content) do
          {:ok, updated_content}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec insert_content(Ecto.Changeset.t()) ::
          {:ok, Note.t() | CaseStudy.t()} | {:error, Ecto.Changeset.t()}
  defp insert_content(changeset) do
    Repo.insert(changeset)
  end

  @spec compile_content(Note.t() | CaseStudy.t(), Types.content_type()) ::
          {:ok, String.t()}
          | {:error, :empty_compiled_content | :empty_content | any()}
  defp compile_content(content, content_type) do
    case Renderer.render_and_cache(content.content, content_type, content.id) do
      {:ok, compiled_content}
      when is_binary(compiled_content) and compiled_content != "" ->
        {:ok, compiled_content}

      {:ok, _} ->
        {:error, :empty_compiled_content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec update_compiled_content(Note.t() | CaseStudy.t(), String.t()) ::
          {:ok, Note.t() | CaseStudy.t()} | {:error, Ecto.Changeset.t()}
  defp update_compiled_content(content, compiled_content) do
    Repo.update(
      Ecto.Changeset.change(content, compiled_content: compiled_content)
    )
  end

  @doc """
  Updates an existing content entry.

  ## Parameters

    * `content` - The existing content entry to update.
    * `attrs` - A map containing the updated attributes.
    * `content_type` - The type of the content being updated.

  ## Returns

    * `{:ok, content}` if the content was successfully updated.
    * `{:error, reason}` if there was an error during update.
  """
  @spec update_content(Note.t() | CaseStudy.t(), map(), content_type()) ::
          {:ok, Note.t() | CaseStudy.t()} | {:error, any()}
  def update_content(content, attrs, content_type) do
    Logger.info("Updating content with attrs: #{inspect(attrs)}")

    with changeset <- apply_changeset(content, attrs),
         {:ok, updated_content} <- update_content_transaction(changeset),
         {:ok, compiled_content} <-
           compile_content(updated_content, content_type),
         {:ok, content_with_compiled} <-
           update_compiled_content(updated_content, compiled_content) do
      {:ok, content_with_compiled}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_content_transaction(Ecto.Changeset.t()) ::
          {:ok, Note.t() | CaseStudy.t()} | {:error, Ecto.Changeset.t()}
  defp update_content_transaction(changeset) do
    Repo.transaction(fn ->
      case Repo.update(changeset) do
        {:ok, updated_content} -> updated_content
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Deletes a content entry.

  ## Parameters

    * `content` - The content entry to delete.

  ## Returns

    * `{:ok, content}` if the content was successfully deleted.
    * `{:error, changeset}` if there was an error during deletion.
  """
  @spec delete_content(Note.t() | CaseStudy.t()) ::
          {:ok, Note.t() | CaseStudy.t()} | {:error, Ecto.Changeset.t()}
  def delete_content(content) do
    Repo.delete(content)
  end

  @doc """
  Retrieves content by ID or URL.

  ## Parameters
    - content_type: String representing the type of content ("note" or "case_study")
    - id_or_url: Integer ID or String URL of the content

  ## Returns
    - The content struct if found

  ## Raises
    - Ecto.NoResultsError if no content is found
  """
  @spec get_content_by_id_or_url(content_type(), integer() | String.t()) ::
          Note.t() | CaseStudy.t()
  def get_content_by_id_or_url(content_type, id_or_url) do
    case get_schema(content_type) do
      {:ok, schema} ->
        query =
          cond do
            uuid?(id_or_url) ->
              from e in schema, where: e.id == ^id_or_url

            is_binary(id_or_url) ->
              from e in schema, where: e.url == ^id_or_url

            true ->
              raise ArgumentError,
                    "Invalid id_or_url provided: #{inspect(id_or_url)}"
          end

        case Repo.one(query) do
          nil ->
            raise Ecto.NoResultsError, queryable: query

          content ->
            {:ok, compiled_html} =
              Renderer.render_and_cache(
                content.content,
                content_type,
                content.id
              )

            %{content | compiled_content: compiled_html}
        end

      {:error, :invalid_content_type} ->
        raise ArgumentError, "Invalid content type: #{inspect(content_type)}"
    end
  end

  defp uuid?(string) do
    case UUID.info(string) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Fetches content items based on translatable IDs and type.

  ## Parameters
    - translatable_ids: List of content IDs
    - type: String representing the type of content ("note" or "case_study")

  ## Returns
    - {:ok, list of content items}

  ## Raises
    - Ecto.NoResultsError if no content is found
  """
  @spec fetch_content_items([binary()], String.t()) ::
          {:ok, [Note.t()] | [CaseStudy.t()]}
  def fetch_content_items(translatable_ids, type) do
    content_schema = Types.get_schema(type)
    query = from(c in content_schema, where: c.id in ^translatable_ids)

    case Repo.all(query) do
      [] -> raise Ecto.NoResultsError, queryable: query
      content -> {:ok, content}
    end
  end

  @doc """
  Lists content items of a specific type with optional sorting and locale.

  ## Parameters
    - type: The content type ("note" or "case_study")
    - opts: Keyword list of options (e.g., [sort_by: :published_at, sort_order: :desc])
    - locale: The locale for translations (default: @default_locale)

  ## Returns
    - List of content items with merged translations
  """
  @spec list_contents(Types.content_type(), keyword(), String.t()) ::
          [Note.t()] | [CaseStudy.t()]
  def list_contents(content_type, opts \\ [], locale \\ "en") do
    schema = Types.get_schema(content_type)

    query =
      from c in schema,
        where: c.is_draft == false and not is_nil(c.published_at)

    query = apply_sorting(query, opts[:sort_by], opts[:sort_order])

    contents = Repo.all(query)

    content_ids = Enum.map(contents, & &1.id)

    translations =
      TranslationManager.batch_get_translations(
        content_ids,
        content_type,
        locale
      )

    Logger.debug("Fetched translations: #{inspect(translations)}")

    result =
      Enum.map(contents, fn content ->
        content_translations = Map.get(translations, content.id, %{})

        Logger.debug(
          "Translations for content: #{inspect(content_translations)}"
        )

        merged_content = Map.put(content, :translations, content_translations)
        merged_content
      end)

    result
  end

  defp apply_sorting(query, nil, _), do: query

  defp apply_sorting(query, sort_by, sort_order) do
    order_by(query, [c], [{^sort_order, field(c, ^sort_by)}])
  end

  ##########################################
  # Handle Translations                    #
  ##########################################

  @spec get_content_with_translations(
          Types.content_type(),
          String.t() | integer(),
          String.t()
        ) ::
          {:ok, Note.t() | CaseStudy.t(), map(), String.t()} | {:error, atom()}
  def get_content_with_translations(content_type, id_or_url, locale) do
    Logger.debug(
      "Fetching #{content_type} with translations for locale: #{locale}"
    )

    try do
      content = get_content_by_id_or_url(content_type, id_or_url)

      translations =
        TranslationManager.get_translations(content.id, content_type, locale)

      case compile_content_and_translations(content, content_type, translations) do
        {:ok, compiled_content, compiled_translations} ->
          updated_content = %{content | compiled_content: compiled_content}
          {:ok, updated_content, compiled_translations, compiled_content}

        {:error, reason} ->
          Logger.error(
            "Failed to compile content or translations: #{inspect(reason)}"
          )

          {:error, :compilation_failed}
      end
    rescue
      Ecto.NoResultsError ->
        Logger.warning(
          "No #{content_type} found for identifier: #{inspect(id_or_url)}"
        )

        {:error, :not_found}
    end
  end

  @spec compile_content_and_translations(
          Note.t() | CaseStudy.t(),
          Types.content_type(),
          map()
        ) ::
          {:ok, String.t(), map()}
          | {:error, atom()}
          | {:error, :empty_content}
          | {:error, :unexpected_result}
          | {:error, :exception}
  defp compile_content_and_translations(content, content_type, translations) do
    schema = content.__struct__
    markdown_fields = schema.markdown_fields()

    with {:ok, compiled_content} <-
           compile_content(content, content_type, markdown_fields),
         {:ok, compiled_translations} <-
           compile_translations(translations, content_type, markdown_fields) do
      {:ok, compiled_content, compiled_translations}
    end
  end

  @spec compile_content(Note.t() | CaseStudy.t(), Types.content_type(), [
          String.t()
        ]) ::
          {:ok, String.t()}
          | {:error, atom()}
          | {:error, :empty_content}
          | {:error, :unexpected_result}
          | {:error, :exception}
  defp compile_content(content, content_type, markdown_fields) do
    is_markdown = "content" in markdown_fields

    try do
      case Renderer.render_and_cache(content.content, content_type, content.id,
             is_markdown: is_markdown
           ) do
        {:ok, compiled} when is_binary(compiled) and compiled != "" ->
          Logger.debug(
            "Successfully compiled content for #{content_type} with ID: #{content.id}"
          )

          {:ok, compiled}

        {:ok, ""} ->
          Logger.warning(
            "Compiled content is empty for #{content_type} with ID: #{content.id}"
          )

          {:error, :empty_content}

        {:error, reason} ->
          Logger.error(
            "Error compiling content for #{content_type} with ID: #{content.id}. Error: #{inspect(reason)}"
          )

          {:error, reason}

        unexpected ->
          Logger.error(
            "Unexpected result from render_and_cache for #{content_type} with ID: #{content.id}. Result: #{inspect(unexpected)}"
          )

          {:error, :unexpected_result}
      end
    rescue
      e ->
        Logger.error(
          "Exception raised while compiling content for #{content_type} with ID: #{content.id}. Exception: #{inspect(e)}"
        )

        {:error, :exception}
    end
  end

  @spec compile_translations(map(), Types.content_type(), [String.t()]) ::
          {:ok, map()} | {:error, atom()}
  defp compile_translations(translations, content_type, markdown_fields) do
    Enum.reduce_while(translations, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      is_markdown = to_string(key) in markdown_fields

      case Renderer.render_and_cache(value, content_type, "#{key}_translation",
             is_markdown: is_markdown
           ) do
        {:ok, compiled} when is_binary(compiled) and compiled != "" ->
          Logger.debug("Successfully compiled translation for key: #{key}")
          {:cont, {:ok, Map.put(acc, key, compiled)}}

        {:ok, ""} ->
          Logger.warning("Compiled translation is empty for key: #{key}")
          {:halt, {:error, :empty_translation}}

        {:error, reason} ->
          Logger.error(
            "Error compiling translation for key: #{key}. Error: #{inspect(reason)}"
          )

          {:halt, {:error, reason}}
      end
    end)
  end

  ##########################################
  # Updates from the markdown file changes #
  ##########################################

  def upsert_from_file(content_type, attrs) when is_atom(content_type) do
    upsert_from_file(Atom.to_string(content_type), attrs)
  end

  @doc """
  Upserts content from file attributes, considering both URL and locale.

  For the default locale, it creates or updates the main content entry.
  For non-default locales, it creates or updates translations.

  ## Parameters
    - content_type: String representing the type of content ("note" or "case_study")
    - attrs: Map of attributes including "url", "locale", and other content fields

  ## Returns
    - {:ok, content} if the operation was successful
    - {:error, changeset} if there was an error
  """
  @spec upsert_from_file(content_type(), map()) ::
          {:ok, Note.t() | CaseStudy.t()}
          | {:error, atom() | Ecto.Changeset.t()}
  def upsert_from_file(content_type, attrs) when is_binary(content_type) do
    with {:ok, schema} <- get_schema(content_type),
         {:ok, content} <- upsert_content(schema, attrs, content_type),
         {:ok, compiled_content} <- compile_content(content, content_type) do
      {:ok, %{content | compiled_content: compiled_content}}
    else
      {:error, reason} ->
        Logger.error("Error in upsert_from_file: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_schema(content_type) do
    case Types.get_schema(content_type) do
      {:error, :invalid_content_type} = error -> error
      schema -> {:ok, schema}
    end
  end

  defp upsert_content(schema, attrs, content_type) do
    if attrs["locale"] == @default_locale do
      upsert_default_locale_content(schema, attrs, content_type)
    else
      upsert_non_default_locale_content(schema, attrs, content_type)
    end
  end

  defp upsert_default_locale_content(schema, attrs, content_type) do
    Logger.info(
      "Upserting default locale content with URL: #{inspect(attrs["url"])}"
    )

    if is_nil(attrs["url"]) do
      Logger.error("URL is nil in attrs: #{inspect(attrs)}")
      {:error, :nil_url}
    else
      case Repo.get_by(schema, url: attrs["url"]) do
        nil ->
          Logger.info("Creating new content for URL: #{attrs["url"]}")
          create_content(Map.put(attrs, "content_type", content_type))

        entry ->
          Logger.info("Updating existing content for URL: #{attrs["url"]}")
          update_content(entry, attrs, content_type)
      end
    end
  end

  defp upsert_non_default_locale_content(schema, attrs, content_type) do
    case Repo.get_by(schema, url: attrs["url"]) do
      nil -> create_entry_with_translations(attrs, content_type)
      entry -> update_entry_translations(entry, attrs)
    end
  end

  defp create_entry_with_translations(attrs, content_type) do
    with {:ok, entry} <-
           create_content(Map.put(attrs, "content_type", content_type)),
         {:ok, _translations} <- create_or_update_translations(entry, attrs) do
      {:ok, entry}
    end
  end

  defp update_entry_translations(entry, attrs) do
    case create_or_update_translations(entry, attrs) do
      {:ok, _translations} -> {:ok, entry}
      error -> error
    end
  end

  defp create_or_update_translations(entry, attrs) do
    case TranslationManager.create_or_update_translations(
           entry,
           attrs["locale"],
           attrs
         ) do
      {:ok, _translations} -> {:ok, entry}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_changeset(%Note{} = note, attrs), do: Note.changeset(note, attrs)

  defp apply_changeset(%CaseStudy{} = case_study, attrs),
    do: CaseStudy.changeset(case_study, attrs)
end
```

# /srv/famichat/backend/lib/famichat/content/managers/translation_manager.ex

```ex
defmodule Famichat.Content.TranslationManager do
  @moduledoc """
  Manages translations for content items in the Famichat application.

  This module provides functionality to create, update, and retrieve translations
  for various content types such as Notes and Case Studies. It interacts with the
  Translation schema and handles the logic for managing multilingual content.

  Key features:
  - Create or update translations for content items
  - Fetch translations for specific content and locale
  - Merge original content with translated fields

  The module uses Ecto for database operations and includes logging for debugging
  and error tracking.
  """
  alias Famichat.Repo
  alias Famichat.Content.TranslatableFields
  alias Famichat.Content.Schemas.{Translation, Note, CaseStudy}
  import Ecto.Query
  require Logger

  @type content :: Note.t() | CaseStudy.t()
  @type translation_result :: {:ok, [Translation.t()]} | {:error, any()}

  @supported_locales Application.compile_env(:famichat, :supported_locales)

  @doc """
  Creates or updates translations for a content item.

  ## Parameters
    - content: The content item (Note or CaseStudy)
    - locale: String representing the locale of the translations
    - attrs: Map of attributes containing the translated values

  ## Returns
    - {:ok, list of translations} if successful
    - {:error, reason} if there was an error

  Note: Nil values in attrs are ignored. Empty strings clear existing translations.
  """
  @spec create_or_update_translations(struct(), String.t(), map()) ::
          {:ok, [Translation.t()]} | {:error, any()}
  def create_or_update_translations(content, locale, attrs) do
    validate_locale(locale)

    translatable_fields =
      TranslatableFields.translatable_fields(content.__struct__)

    results =
      Enum.map(
        translatable_fields,
        &process_translatable_field(&1, content, locale, attrs)
      )

    aggregate_translation_results(results)
  end

  @doc """
  Fetches translations for a specific content item and locale.

  ## Parameters
  - `content_id`: The ID of the content item.
  - `content_type`: The type of the content ("note" or "case_study").
  - `locale`: The locale of the translations to fetch.

  ## Returns
  - `%{String.t() => String.t()}`: A map of field names to translated values.
  """
  @spec get_translations(binary(), String.t(), String.t()) :: %{
          String.t() => String.t()
        }
  def get_translations(content_id, content_type, locale) do
    Logger.debug(
      "Fetching translations for content_id: #{content_id}, content_type: #{content_type}, locale: #{locale}"
    )

    translations =
      from(t in Translation,
        where:
          t.translatable_id == ^content_id and
            t.translatable_type == ^content_type and
            t.locale == ^locale,
        select: {t.field_name, t.field_value}
      )
      |> Repo.all()
      |> Enum.into(%{})

    Logger.debug("Fetched translations: #{inspect(translations)}")
    translations
  end

  @doc """
  Preloads translations for a list of content items.

  ## Parameters
    - query: The initial query for content items
    - locale: The locale to preload translations for

  ## Returns
    - A query with preloaded translations
  """
  @spec preload_translations(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def preload_translations(query, locale) do
    from q in query,
      preload: [
        translations: ^from(t in Translation, where: t.locale == ^locale)
      ]
  end

  @doc """
  Batch retrieves translations for multiple content items.

  ## Parameters
    - content_ids: List of content IDs
    - content_type: The type of the content ("note" or "case_study")
    - locale: The locale of the translations to fetch

  ## Returns
    - A map where keys are content IDs and values are maps of translations
  """
  @spec batch_get_translations([binary()], String.t(), String.t()) :: %{
          binary() => %{String.t() => String.t()}
        }
  def batch_get_translations(content_ids, content_type, locale) do
    Logger.debug(
      "Batch fetching translations for content_type: #{content_type}, locale: #{locale}"
    )

    from(t in Translation,
      where:
        t.translatable_id in ^content_ids and
          t.translatable_type == ^content_type and
          t.locale == ^locale,
      select: {t.translatable_id, {t.field_name, t.field_value}}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_, translation} -> translation end)
    |> Map.new(fn {id, translations} -> {id, Enum.into(translations, %{})} end)
  end

  # Private functions
  defp validate_locale(locale) do
    unless locale in @supported_locales do
      Logger.warning(
        "Creating/updating translations for unsupported locale: #{locale}"
      )
    end
  end

  defp process_translatable_field(field, content, locale, attrs) do
    field_name = Atom.to_string(field)
    field_value = Map.get(attrs, field_name)

    if is_nil(field_value) do
      nil
    else
      normalized_value = normalize_field_value(field_value)
      upsert_translation(content, locale, field_name, normalized_value)
    end
  end

  defp normalize_field_value(value) when is_integer(value),
    do: Integer.to_string(value)

  defp normalize_field_value(value), do: value

  defp aggregate_translation_results(results) do
    if Enum.any?(results, &match?({:error, _}, &1)) do
      {:error, "Failed to create or update some translations"}
    else
      {:ok, Enum.reject(results, &is_nil/1)}
    end
  end

  defp upsert_translation(content, locale, field_name, field_value) do
    attrs = %{
      translatable_id: content.id,
      translatable_type: content.__struct__.translatable_type(),
      locale: locale,
      field_name: field_name,
      field_value: field_value
    }

    existing_translation =
      Repo.get_by(
        Translation,
        Map.take(attrs, [
          :translatable_id,
          :translatable_type,
          :locale,
          :field_name
        ])
      )

    (existing_translation || %Translation{})
    |> Translation.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, translation} ->
        translation

      {:error, changeset} ->
        Logger.error(
          "Failed to upsert translation: #{inspect(changeset.errors)}"
        )

        nil
    end
  end

  # defp create_translation(attrs) do
  #   %Translation{}
  #   |> Translation.changeset(attrs)
  #   |> Repo.insert()
  #   |> case do
  #     {:ok, translation} ->
  #       {:ok, translation}

  #     {:error, changeset} ->
  #       {:error, "Failed to create translation: #{inspect(changeset.errors)}"}
  #   end
  # end

  # defp update_translation(translation, attrs) do
  #   translation
  #   |> Translation.changeset(attrs)
  #   |> Repo.update()
  #   |> case do
  #     {:ok, translation} ->
  #       {:ok, translation}

  #     {:error, changeset} ->
  #       {:error, "Failed to update translation: #{inspect(changeset.errors)}"}
  #   end
  # end
end
```

# /srv/famichat/backend/lib/famichat/repo.ex

```ex
defmodule Famichat.Repo do
  use Ecto.Repo,
    otp_app: :famichat,
    adapter: Ecto.Adapters.Postgres
end
```

