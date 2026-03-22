defmodule FamichatWeb.FamilyContextController do
  @moduledoc """
  Handles family context switching via form POST.

  LiveView cannot write to the Plug session after mount, so family switching
  is handled by this controller. It validates the switch, updates both the
  session cookie and the DB column, then redirects back to HomeLive.
  """
  use FamichatWeb, :controller

  alias Famichat.Accounts.FamilyContext
  alias Famichat.Auth.{Identity, Sessions}
  alias FamichatWeb.SessionKeys

  def switch(conn, %{"family_id" => family_id} = params) do
    with {:ok, user_id} <- extract_user_id(conn),
         {:ok, _family, _source} <- FamilyContext.resolve(user_id, family_id),
         {:ok, _user} <- Identity.set_last_active_family(user_id, family_id) do
      return_to = safe_return_to(params["return_to"], conn)

      conn
      |> put_session(SessionKeys.active_family_id(), family_id)
      |> redirect(to: return_to)
    else
      {:error, :not_authenticated} ->
        conn
        |> redirect(to: login_path(conn))

      {:error, :not_a_member} ->
        conn
        |> put_flash(
          :error,
          gettext("That family space is no longer available to you.")
        )
        |> redirect(to: home_path(conn))

      {:error, :no_family} ->
        conn
        |> put_flash(:error, gettext("That family space could not be found."))
        |> redirect(to: home_path(conn))

      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("Something went wrong. Try refreshing."))
        |> redirect(to: home_path(conn))
    end
  end

  def switch(conn, _params) do
    conn
    |> put_flash(:error, gettext("Something went wrong. Try refreshing."))
    |> redirect(to: home_path(conn))
  end

  defp extract_user_id(conn) do
    token = get_session(conn, SessionKeys.access_token())

    case Sessions.verify_access_token(token) do
      {:ok, %{user_id: user_id}} -> {:ok, user_id}
      _ -> {:error, :not_authenticated}
    end
  end

  defp locale(conn) do
    conn.assigns[:user_locale] || conn.params["locale"] || "en"
  end

  defp home_path(conn), do: "/#{locale(conn)}/"
  defp login_path(conn), do: "/#{locale(conn)}/login"

  # Only allow same-origin relative paths. No protocol, no host.
  defp safe_return_to(nil, conn), do: home_path(conn)
  defp safe_return_to("", conn), do: home_path(conn)

  defp safe_return_to(path, conn) when is_binary(path) do
    case URI.parse(path) do
      %URI{scheme: nil, host: nil, path: p} when is_binary(p) -> p
      _ -> home_path(conn)
    end
  end
end
