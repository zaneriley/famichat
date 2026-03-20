defmodule FamichatWeb.RootRedirectController do
  use FamichatWeb, :controller

  alias Famichat.Auth.Identity
  alias Famichat.Auth.Sessions
  alias FamichatWeb.SessionKeys

  def index(conn, _params) do
    locale = resolve_locale(conn)
    redirect(conn, to: "/#{locale}/")
  end

  # Try session locale first (fast path), then verify access token → DB locale,
  # then fall back to Accept-Language.
  defp resolve_locale(conn) do
    session_locale = Plug.Conn.get_session(conn, SessionKeys.user_locale())

    if is_binary(session_locale) and session_locale != "" do
      session_locale
    else
      resolve_locale_from_token(conn)
    end
  end

  defp resolve_locale_from_token(conn) do
    with token when is_binary(token) <-
           Plug.Conn.get_session(conn, SessionKeys.access_token()),
         {:ok, %{user_id: user_id}} <- Sessions.verify_access_token(token),
         locale when is_binary(locale) and locale != "" <-
           Identity.get_locale_for_user(user_id) do
      locale
    else
      _ -> FamichatWeb.Plugs.SetLocale.extract_preferred_locale(conn)
    end
  rescue
    _ -> FamichatWeb.Plugs.SetLocale.extract_preferred_locale(conn)
  end
end
