defmodule FamichatWeb.UserController do
  use FamichatWeb, :controller

  alias Famichat.Auth.Identity

  def me(conn, _params) do
    user_id = conn.assigns[:current_user_id]

    case Identity.fetch_user(user_id) do
      {:ok, user} ->
        json(conn, %{
          user_id: user.id,
          username: user.username,
          email: user.email
        })

      {:error, :user_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{code: "user_not_found"}})
    end
  end
end
