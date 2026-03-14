defmodule FamichatWeb.FallbackController do
  use FamichatWeb, :controller

  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found"}})
  end

  def not_found_html(conn, _params) do
    locale = infer_locale(conn)
    Gettext.put_locale(FamichatWeb.Gettext, locale)

    conn
    |> assign(:user_locale, locale)
    |> put_status(:not_found)
    |> put_layout(false)
    |> put_view(FamichatWeb.ErrorHTML)
    |> render("404.html")
  end

  def call(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found"}})
  end

  def call(conn, :not_found_html) do
    not_found_html(conn, conn.params)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found"}})
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "unauthorized"}})
  end

  def call(conn, {:error, reason}) when is_atom(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: to_string(reason)}})
  end

  defp infer_locale(conn) do
    case conn.path_info do
      [maybe_locale | _rest] ->
        supported = FamichatWeb.Plugs.LocaleRedirection.supported_locales()

        if maybe_locale in supported,
          do: maybe_locale,
          else: fallback_locale(conn)

      _ ->
        fallback_locale(conn)
    end
  end

  defp fallback_locale(conn) do
    FamichatWeb.Plugs.SetLocale.extract_preferred_locale(conn)
  end
end
