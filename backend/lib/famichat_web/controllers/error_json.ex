defmodule FamichatWeb.ErrorJSON do
  @moduledoc """
  Renders JSON error responses for unhandled HTTP status codes.
  Canonical envelope: {"error": {"code": "...", "message": "..."}}.
  """

  def render("401.json", _assigns) do
    %{error: %{code: "unauthorized", message: "Unauthorized"}}
  end

  def render("403.json", _assigns) do
    %{error: %{code: "forbidden", message: "Forbidden"}}
  end

  def render("404.json", _assigns) do
    %{error: %{code: "not_found", message: "Not Found"}}
  end

  def render("422.json", _assigns) do
    %{error: %{code: "unprocessable_entity", message: "Unprocessable Entity"}}
  end

  def render("500.json", _assigns) do
    %{error: %{code: "internal_server_error", message: "Internal Server Error"}}
  end

  def render(template, _assigns) do
    message = Phoenix.Controller.status_message_from_template(template)
    code = template |> String.replace(".json", "") |> then(&"http_#{&1}")
    %{error: %{code: code, message: message}}
  end
end
