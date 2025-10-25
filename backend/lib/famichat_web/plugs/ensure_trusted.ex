defmodule FamichatWeb.Plugs.EnsureTrusted do
  @moduledoc """
  Ensures the request is authenticated with a valid access token whose device
  remains inside the trusted window. Assigns `:current_user_id` and
  `:current_device_id` on success.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Famichat.Auth.Sessions

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    action =
      Keyword.get(opts, :action, conn.private[:phoenix_action] || :default)

    with {:ok, token} <- fetch_bearer(conn),
         {:ok, %{user_id: user_id, device_id: device_id}} <-
           Sessions.verify_access_token(token),
         false <- Sessions.require_reauth?(user_id, device_id, action) do
      conn
      |> assign(:current_user_id, user_id)
      |> assign(:current_device_id, device_id)
    else
      :no_token ->
        conn |> unauthorized("invalid_token")

      {:error, {:rate_limited, retry}} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "rate_limited", retry_in: retry}})
        |> halt()

      {:error, _reason} ->
        conn |> unauthorized("invalid_token")

      true ->
        conn |> reauth_required()
    end
  end

  defp fetch_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      ["bearer " <> token] -> {:ok, token}
      _ -> :no_token
    end
  end

  defp unauthorized(conn, code) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: code}})
    |> halt()
  end

  defp reauth_required(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{
      error: %{
        code: "reauth_required",
        reauth_required: true,
        methods: ["passkey", "magic"]
      }
    })
    |> halt()
  end
end
