defmodule FamichatWeb.Navigation do
  @moduledoc """
  Main navigation LiveComponent for Famichat.

  Renders the top-level application bar with:
  - Famichat logo (links to home)
  - EN/JA language switcher

  Usage:
      <.live_component module={FamichatWeb.Navigation} id="nav" current_path={@current_path} user_locale={@locale} />

  Assigns:
  - `current_path`: Current URL path (default: "/")
  - `user_locale`: User's locale string, e.g. "en" or "ja" (default: "en")

  All user-visible labels use `gettext/1` for i18n support.

  Helper functions:
  - `build_localized_path/2`: Generates locale-prefixed paths for the language switcher
  """
  use FamichatWeb, :live_component
  alias FamichatWeb.Router.Helpers, as: Routes
  import FamichatWeb.Components.Typography

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:current_path, fn -> assigns[:current_path] || "/" end)
      |> assign_new(:user_locale, fn -> assigns[:user_locale] || "en" end)

    {:ok, socket}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        en_path: build_localized_path(assigns.current_path, "en"),
        ja_path: build_localized_path(assigns.current_path, "ja")
      )

    ~H"""
    <nav role="banner" class="flex items-center justify-between p-md">
      <.link
        navigate={Routes.home_path(@socket, :index, @user_locale)}
        aria-label={gettext("Famichat home")}
      >
        <.typography tag="span" size="1xl" font="cardinal">Famichat</.typography>
      </.link>
      <div class="flex flex-wrap items-center gap-md justify-end">
        <nav aria-label={gettext("Language switcher")}>
          <ul class="flex gap-md">
            <li>
              <.link
                href={@en_path}
                aria-current={if @user_locale == "en", do: "page", else: "false"}
              >
                <.typography
                  tag="span"
                  size="1xs"
                  color={if @user_locale == "en", do: "main", else: "deemphasized"}
                >
                  EN
                </.typography>
              </.link>
            </li>
            <li>
              <.link
                href={@ja_path}
                aria-current={if @user_locale == "ja", do: "page", else: "false"}
              >
                <.typography
                  tag="span"
                  size="1xs"
                  color={if @user_locale == "ja", do: "main", else: "deemphasized"}
                >
                  JA
                </.typography>
              </.link>
            </li>
          </ul>
        </nav>
      </div>
    </nav>
    """
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
