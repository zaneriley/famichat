defmodule FamichatWeb.RouteTableTest do
  @moduledoc """
  Compile-time assertions on the route table structure.

  These tests introspect FamichatWeb.Router.__routes__/0 to catch
  ordering bugs where broad scopes shadow narrow ones. The primary
  risk: `/:locale` matching "api" before `/api` routes.

  Prevents: silent 200 HTML responses when `/api/*` is swallowed by
  the locale scope (2026-03-09 bug bash finding).
  """
  use ExUnit.Case, async: true

  # Prefixes that must never be swallowed by /:locale parameter routes.
  @protected_prefixes ~w(api admin up)

  @supported_locales Application.compile_env(:famichat, :supported_locales, ["en", "ja"])

  test "no locale-scoped route can shadow a protected prefix" do
    routes = FamichatWeb.Router.__routes__()

    locale_routes =
      routes
      |> Enum.filter(fn route ->
        String.contains?(route.path, ":locale")
      end)

    for route <- locale_routes, prefix <- @protected_prefixes do
      # Find real routes under this prefix that do NOT use :locale.
      # Exclude catch-all routes (e.g. /api/*path) -- they are intentionally
      # last and have their own dedicated ordering test below.
      non_locale_routes =
        routes
        |> Enum.filter(fn r ->
          not String.contains?(r.path, ":locale") and
            String.starts_with?(r.path, "/#{prefix}") and
            not String.contains?(r.path, "*")
        end)

      if non_locale_routes != [] do
        locale_route_index = Enum.find_index(routes, &(&1 == route))

        for real_route <- non_locale_routes do
          real_index = Enum.find_index(routes, &(&1 == real_route))

          assert real_index < locale_route_index,
            "Route #{real_route.path} (#{real_route.verb}) at index #{real_index} must be declared " <>
              "before locale route #{route.path} at index #{locale_route_index} to avoid shadowing. " <>
              "Move the locale scope below all /#{prefix} routes in router.ex."
        end
      end
    end
  end

  test "protected prefixes are not valid locale values" do
    for prefix <- @protected_prefixes do
      refute prefix in @supported_locales,
        "#{prefix} must not be in :supported_locales -- it would collide with /#{prefix} routes"
    end
  end

  test "API catch-all route is declared after all /api/v1 routes" do
    routes = FamichatWeb.Router.__routes__()

    api_v1_routes =
      Enum.filter(routes, fn r -> String.starts_with?(r.path, "/api/v1") end)

    api_catchall =
      Enum.filter(routes, fn r ->
        r.path == "/api/*path" or r.path == "/api/:path"
      end)

    if api_catchall != [] and api_v1_routes != [] do
      last_v1_index =
        api_v1_routes
        |> Enum.map(fn r -> Enum.find_index(routes, &(&1 == r)) end)
        |> Enum.max()

      first_catchall_index =
        api_catchall
        |> Enum.map(fn r -> Enum.find_index(routes, &(&1 == r)) end)
        |> Enum.min()

      assert last_v1_index < first_catchall_index,
        "API catch-all route must be declared after all /api/v1 routes. " <>
          "Last /api/v1 route at index #{last_v1_index}, but catch-all at #{first_catchall_index}."
    end
  end

  test "route table is non-empty (sanity check)" do
    routes = FamichatWeb.Router.__routes__()
    assert length(routes) > 0, "Router has no routes -- something is very wrong"
  end
end
