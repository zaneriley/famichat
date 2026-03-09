defmodule FamichatWeb.Integration.SecurityBaselineTest do
  @moduledoc """
  Security baseline tests that prevent "dev defaults leak to prod" regressions.

  Origin: 2026-03-09 bug bash found 5 separate issues sharing one root cause —
  nothing asserted that prod config differs from dev config:

    1. HEEx debug annotations (85 HTML comments leaking file paths)
    2. Permissive CSP (report-only in prod)
    3. console.log leaks in production JS
    4. Missing HSTS header
    5. Server identity header disclosure

  This file combines security header assertions, config divergence assertions,
  and response body assertions. Each test documents what bug it prevents.

  Adding a new security requirement = adding one assertion here.
  """

  # ---------------------------------------------------------------------------
  # Section 1: Security Response Headers
  #
  # Integration tests through the real plug pipeline. These use ConnCase to
  # boot a connection through the full :browser pipeline and assert on actual
  # HTTP response headers.
  # ---------------------------------------------------------------------------

  use FamichatWeb.ConnCase

  describe "security response headers" do
    setup %{conn: conn} do
      # Hit a page that goes through the full :browser pipeline.
      # /en/login is a public route that renders through the browser pipeline
      # including CSPHeader, put_secure_browser_headers, and all other plugs.
      conn = get(conn, "/en/login")
      %{resp_conn: conn}
    end

    test "CSP header is present and enforcing (not report-only)", %{resp_conn: conn} do
      # Bug bash 2026-03-09: dev.exs had report_only: true, and nothing
      # prevented that from leaking to prod. CSP in report-only mode provides
      # zero protection — it only logs violations.
      #
      # The CSPHeader plug checks @report_only (compile-time config) to decide
      # which header name to use. In test/prod, report_only must be false,
      # producing the enforcing "content-security-policy" header.
      assert get_resp_header(conn, "content-security-policy") != [],
             "content-security-policy header is missing — CSP is not enforcing"

      assert get_resp_header(conn, "content-security-policy-report-only") == [],
             "content-security-policy-report-only is set — CSP is report-only, not enforcing"
    end

    test "CSP script-src does not contain unsafe-eval outside dev", %{resp_conn: conn} do
      # Bug bash 2026-03-09: the CSP plug included 'unsafe-eval' in script-src
      # in all environments. unsafe-eval allows arbitrary JS execution, which
      # defeats the purpose of CSP against XSS.
      #
      # Fixed: script_src is now delegated to the env module. The Prod module
      # returns 'self' only (no unsafe-eval). The Dev module keeps unsafe-eval
      # for hot-reload compatibility.
      [csp] = get_resp_header(conn, "content-security-policy")

      script_src =
        csp
        |> String.split(";")
        |> Enum.find(&String.contains?(&1, "script-src"))

      env = Application.get_env(:famichat, :environment)

      if env != :dev do
        assert script_src != nil, "script-src directive missing from CSP"

        refute script_src =~ "unsafe-eval",
               "script-src contains 'unsafe-eval' — remove it for non-dev environments"
      end
    end

    test "standard secure headers are present (x-content-type-options, x-frame-options)",
         %{resp_conn: conn} do
      # These headers are set by Phoenix's :put_secure_browser_headers plug in
      # the :browser pipeline. This test catches accidental removal of that plug.
      #
      # x-content-type-options: nosniff — prevents MIME-type sniffing attacks
      # x-frame-options — prevents clickjacking via iframe embedding
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"],
             "x-content-type-options header missing or wrong — check :put_secure_browser_headers in router"

      assert get_resp_header(conn, "x-frame-options") != [],
             "x-frame-options header missing — check :put_secure_browser_headers in router"
    end

    test "HSTS header is present with adequate max-age", %{resp_conn: conn} do
      # Bug bash 2026-03-09 finding #4: no HSTS header was set.
      # Fixed: put_secure_browser_headers in :browser pipeline now includes
      # strict-transport-security with 2-year max-age.
      [hsts] = get_resp_header(conn, "strict-transport-security")
      assert hsts =~ "max-age="
      {max_age, _} =
        hsts
        |> String.split(";")
        |> hd()
        |> String.trim()
        |> String.replace("max-age=", "")
        |> Integer.parse()
      # OWASP recommends at least 1 year (31536000 seconds).
      assert max_age >= 31_536_000
    end

    test "server header strip plug is wired in endpoint" do
      # Bug bash 2026-03-09 finding #5: Cowboy sets `server: Cowboy` on all
      # responses. ConnCase bypasses Cowboy, so we can't assert on the header
      # directly. Instead, verify the strip plug source exists in the endpoint.
      # This is a structural check (prevention hierarchy level 2: static analysis).
      endpoint_source =
        FamichatWeb.Endpoint.module_info(:compile)[:source]
        |> to_string()
        |> File.read!()

      assert endpoint_source =~ "strip_server_header",
             "strip_server_header not found in endpoint.ex source — " <>
               "Cowboy's `server` header will leak in production"

      assert endpoint_source =~ "delete_resp_header" and endpoint_source =~ ~s("server"),
             "strip_server_header does not delete the 'server' header"
    end
  end

  # ---------------------------------------------------------------------------
  # Section 2: Security-Sensitive Config
  #
  # Pure config assertions — no HTTP requests needed. These catch "forgot to
  # configure for prod" drift by verifying config values at test time.
  # The test environment mirrors prod for security-relevant keys, so these
  # assertions fire in CI.
  # ---------------------------------------------------------------------------

  describe "security-sensitive config" do
    test "HEEx debug_annotations is not enabled outside dev" do
      # Bug bash 2026-03-09 finding #1: dev.exs sets debug_heex_annotations: true,
      # which injects HTML comments like <!-- <Module.Name> lib/path/file.heex:N -->
      # into every rendered template. 85 such comments were found leaking internal
      # file paths. Prod relied on the implicit default (nil/false). If the upstream
      # default ever changes, prod silently leaks paths.
      #
      # This test verifies the config value is not true in the current environment.
      # In test env (which mirrors prod), annotations must be off.
      env = Application.get_env(:famichat, :environment)

      if env != :dev do
        annotations = Application.get_env(:phoenix_live_view, :debug_heex_annotations)

        refute annotations == true,
               "debug_heex_annotations is true in #{env} environment — " <>
                 "this leaks internal file paths in HTML. " <>
                 "Only dev.exs should set this to true."
      end
    end

    test "CSP report_only is not enabled outside dev" do
      # Bug bash 2026-03-09 finding #2: dev.exs sets csp report_only: true so
      # developers can iterate without CSP blocking resources. If this leaks to
      # prod, CSP provides zero protection (violations are only logged, not blocked).
      #
      # The CSPHeader plug reads this at compile time via @report_only. In test/prod,
      # it must be false (the default when unset, but prod.exs explicitly sets it).
      env = Application.get_env(:famichat, :environment)

      if env != :dev do
        csp_config = Application.get_env(:famichat, :csp, [])
        report_only = Keyword.get(csp_config, :report_only)

        refute report_only == true,
               "CSP report_only is true in #{env} — " <>
                 "CSP is report-only, providing no protection. " <>
                 "Set `config :famichat, :csp, report_only: false` in #{env}.exs."
      end
    end

    test "debug_errors is not enabled outside dev" do
      # debug_errors: true causes Phoenix to render detailed error pages with
      # stack traces, source code snippets, and internal state. dev.exs sets it;
      # it must not leak to test or prod.
      env = Application.get_env(:famichat, :environment)

      if env != :dev do
        endpoint_config = Application.get_env(:famichat, FamichatWeb.Endpoint) || []

        refute Keyword.get(endpoint_config, :debug_errors, false),
               "debug_errors is true in #{env} — " <>
                 "this exposes stack traces and source code in error pages."
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Section 3: Response Body Security
  #
  # Asserts on the actual rendered HTML, catching leaks that config checks alone
  # might miss (e.g., if a future Phoenix version changes how annotations work).
  # ---------------------------------------------------------------------------

  describe "response body security" do
    test "no HEEx debug annotations in rendered HTML" do
      # Bug bash 2026-03-09 finding #1 (output-level check, complementing the
      # config check in section 2). Even if the config assertion passes, this
      # catches annotations that appear through a different mechanism.
      #
      # HEEx debug annotations look like:
      #   <!-- <ModuleName> lib/famichat_web/live/auth/login_live.html.heex:1 (famichat) -->
      # They leak internal module names and file paths.
      conn = build_conn() |> get("/en/login")

      # The app may redirect (e.g., /en/login → /en/setup when not bootstrapped).
      # Follow one redirect to get a page with rendered HTML.
      conn =
        if conn.status in [301, 302] do
          build_conn() |> get(redirected_to(conn))
        else
          conn
        end

      body = html_response(conn, 200)

      # Pattern matches: <!-- <SomeModule or <!-- <Some.Nested.Module
      refute body =~ ~r/<!-- <[A-Z][\w.]*>/,
             "HEEx debug annotations found in rendered HTML — " <>
               "set `config :phoenix_live_view, :debug_heex_annotations, false` " <>
               "or ensure it is not set to true outside dev.exs"

      # Also catch the @caller variant that some Phoenix versions emit
      refute body =~ ~r/<!-- @caller /,
             "HEEx @caller annotations found in rendered HTML"
    end
  end
end
