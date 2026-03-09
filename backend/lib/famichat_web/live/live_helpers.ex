defmodule FamichatWeb.LiveHelpers do
  @moduledoc """
  Helper functions for Phoenix LiveView in the Famichat application.

  Provides utilities for managing LiveView sockets, internationalization,
  page metadata, and navigation.

  ## Features

  * LiveView Socket Management: Configures common socket assigns for default and admin mounts
  * Internationalization: Integrates with Gettext for multi-language support (EN/JA)
  * Page Metadata: Functions for setting and managing page titles and descriptions
  * Navigation: Manages current path information and handles locale-based path changes

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

  @default_title gettext("Famichat")
  @default_description gettext("Private, self-hosted messaging for families.")
  @supported_locales Application.compile_env(:famichat, :supported_locales, ~w(en ja))
  @default_locale Application.compile_env(:famichat, :default_locale, "en")

  def on_mount(:default, params, session, socket) do
    socket = setup_common_assigns(socket, params, session)
    {:cont, socket}
  end

  def on_mount(:admin, params, session, socket) do
    # NOTE: Plug.BasicAuth in the :admin pipeline enforces authentication
    # before this mount is reached. This callback only adds the :admin
    # assign for template conditionals; it is NOT an access control gate.
    socket = setup_common_assigns(socket, params, session)
    {:cont, assign(socket, :admin, true)}
  end

  def on_mount(:require_authenticated, params, session, socket) do
    socket = setup_common_assigns(socket, params, session)
    token = session["access_token"]

    case Famichat.Auth.Sessions.verify_access_token(token) do
      {:ok, %{user_id: user_id, device_id: device_id}} ->
        {:cont,
         socket
         |> assign(:current_user_id, user_id)
         |> assign(:current_device_id, device_id)}

      _ ->
        locale = socket.assigns[:user_locale] || "en"
        {:halt, Phoenix.LiveView.push_navigate(socket, to: "/#{locale}/login")}
    end
  end

  defp setup_common_assigns(socket, params, session) do
    url_locale = params["locale"]
    existing_locale = socket.assigns[:user_locale]
    session_locale = session["user_locale"]

    user_locale =
      cond do
        url_locale in @supported_locales -> url_locale
        existing_locale in @supported_locales -> existing_locale
        session_locale in @supported_locales -> session_locale
        true -> @default_locale
      end

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
    session["user_locale"] || @default_locale
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

  @doc """
  Returns a locale-prefixed path using the current socket's or assigns' locale.
  Use instead of hardcoding "/\#{locale}/path" everywhere.

      locale_path(socket, "/login")     # => "/en/login"
      locale_path(socket, "/")          # => "/en/"
      locale_path(assigns, "/login")    # => "/en/login"
  """
  def locale_path(socket_or_assigns, path) do
    locale =
      case socket_or_assigns do
        %Phoenix.LiveView.Socket{} ->
          socket_or_assigns.assigns[:user_locale] || "en"

        %{user_locale: locale} ->
          locale || "en"

        _ ->
          "en"
      end

    "/#{locale}#{path}"
  end
end
