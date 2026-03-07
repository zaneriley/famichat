defmodule FamichatWeb.Plugs.SessionRefresh do
  @moduledoc """
  Transparently refreshes an expired access token using the refresh token
  stored in the Plug session.

  When the access_token in the session is expired (or missing) but a valid
  refresh_token + device_id pair exists, this plug calls
  `Sessions.refresh_session/2` and writes the new tokens back into the
  session cookie. Downstream LiveViews then see a valid access_token on
  mount without needing to redirect to login.

  Place this plug in the authenticated browser pipeline, after `:fetch_session`.
  """

  import Plug.Conn

  alias Famichat.Auth.Sessions
  alias FamichatWeb.ConnHelpers
  alias FamichatWeb.SessionKeys
  alias FamichatWeb.TokenVerifyCache
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    start_time = System.monotonic_time()
    {updated_conn, metadata} = maybe_verify_or_refresh(conn)

    duration_ms =
      System.convert_time_unit(
        System.monotonic_time() - start_time,
        :native,
        :millisecond
      )

    :telemetry.execute(
      [:famichat, :plug, :session_refresh, :call],
      %{count: 1, duration_ms: duration_ms},
      metadata
    )

    updated_conn
  end

  defp maybe_verify_or_refresh(conn) do
    access_token = get_session(conn, SessionKeys.access_token())

    if is_binary(access_token) do
      case TokenVerifyCache.verify_cached(access_token) do
        :hit ->
          {conn, %{cache_status: :hit, refreshed?: false, result: :verified}}

        :miss ->
          verify_or_refresh_uncached(conn, access_token)
      end
    else
      maybe_refresh(conn, :none)
    end
  end

  defp verify_or_refresh_uncached(conn, access_token) do
    case Sessions.verify_access_token(access_token) do
      {:ok, _session} ->
        :ok = TokenVerifyCache.cache(access_token)
        {conn, %{cache_status: :miss, refreshed?: false, result: :verified}}

      {:error, _reason} ->
        maybe_refresh(conn, :invalid)
    end
  end

  defp maybe_refresh(conn, cache_status) do
    refresh_token = get_session(conn, SessionKeys.refresh_token())
    device_id = get_session(conn, SessionKeys.device_id())

    if is_binary(refresh_token) and is_binary(device_id) do
      case Sessions.refresh_session(device_id, refresh_token) do
        {:ok, new_tokens} ->
          Logger.info(
            "[SessionRefresh] Auto-refreshed session for device #{device_id}"
          )

          :ok = TokenVerifyCache.cache(new_tokens.access_token)

          {ConnHelpers.put_session_from_issued(conn, new_tokens),
           %{cache_status: cache_status, refreshed?: true, result: :refreshed}}

        {:error, reason} ->
          Logger.debug("[SessionRefresh] Refresh failed: #{inspect(reason)}")

          {conn,
           %{
             cache_status: cache_status,
             refreshed?: false,
             result: :refresh_failed
           }}
      end
    else
      {conn, %{cache_status: cache_status, refreshed?: false, result: :skipped}}
    end
  end
end
