defmodule FamichatWeb.FallbackController do
  use FamichatWeb, :controller

  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found"}})
  end

  def not_found_html(conn, _params) do
    conn
    |> put_status(:not_found)
    |> put_view(FamichatWeb.ErrorHTML)
    |> render("404.html")
  end

  def call(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found"}})
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
end
