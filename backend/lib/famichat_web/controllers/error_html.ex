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
