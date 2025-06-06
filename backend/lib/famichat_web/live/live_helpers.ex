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
