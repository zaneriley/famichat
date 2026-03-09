defmodule FamichatWeb.Plugs.PutRemoteIp do
  @moduledoc """
  Stores the client's real IP address as a string in the session.

  Parses `X-Forwarded-For` when the request arrives from a trusted proxy.
  Falls back to `conn.remote_ip` when there is no proxy header or the
  immediate peer is not in the trusted proxy list.

  Downstream LiveViews can read `get_session(socket, "remote_ip")` to pass
  the IP as a rate-limit key (e.g. for self-service family creation).

  ## Configuration

      config :famichat, FamichatWeb.Plugs.PutRemoteIp,
        trusted_proxies: ["127.0.0.1", "::1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  When no configuration is provided, all RFC 1918 private ranges plus
  loopback are trusted by default. This covers Docker, Caddy, nginx, and
  home-network reverse proxies out of the box.
  """

  import Plug.Conn
  import Bitwise

  @default_trusted_proxies [
    # IPv4 loopback
    "127.0.0.0/8",
    # IPv6 loopback
    "::1/128",
    # RFC 1918 private ranges
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    # Docker default bridge
    "172.17.0.0/16"
  ]

  # Parse CIDRs at compile time. Helper functions aren't available yet in module
  # attribute context, so we inline the parsing here.
  @trusted_cidrs (
    proxies =
      Application.compile_env(:famichat, __MODULE__, [])
      |> Keyword.get(:trusted_proxies, @default_trusted_proxies)

    Enum.map(proxies, fn cidr_string ->
      {ip_str, bits} =
        case String.split(cidr_string, "/") do
          [ip, b] -> {ip, String.to_integer(b)}
          [ip] -> {ip, nil}
        end

      {:ok, ip} = ip_str |> String.trim() |> String.to_charlist() |> :inet.parse_address()
      total = if tuple_size(ip) == 4, do: 32, else: 128
      prefix = bits || total
      shift = total - prefix
      mask = Bitwise.bsl(1, total) - 1 - (Bitwise.bsl(1, shift) - 1)
      {ip, mask, total}
    end)
  )

  def init(opts), do: opts

  def call(conn, _opts) do
    ip_string = resolve_client_ip(conn)
    put_session(conn, "remote_ip", ip_string)
  end

  @doc false
  def resolve_client_ip(conn) do
    peer_ip = normalize_ip(conn.remote_ip)

    if peer_trusted?(peer_ip) do
      conn
      |> get_forwarded_for()
      |> pick_client_ip(peer_ip)
    else
      ip_to_string(peer_ip)
    end
  end

  defp get_forwarded_for(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [value | _] -> parse_forwarded_for(value)
      [] -> []
    end
  end

  defp parse_forwarded_for(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Pick the rightmost non-trusted IP from the X-Forwarded-For chain.
  # The rightmost entry was appended by the closest proxy, so we walk
  # right-to-left and return the first IP that is NOT a trusted proxy.
  # If all entries are trusted (or the list is empty), fall back to peer.
  defp pick_client_ip(forwarded_ips, peer_ip) do
    forwarded_ips
    |> Enum.reverse()
    |> Enum.find(fn ip_str ->
      case parse_ip(ip_str) do
        {:ok, ip} -> not peer_trusted?(normalize_ip(ip))
        :error -> false
      end
    end)
    |> case do
      nil -> ip_to_string(peer_ip)
      ip_str -> ip_str
    end
  end

  defp peer_trusted?(ip_tuple) do
    Enum.any?(@trusted_cidrs, fn {net, mask, bits} ->
      ip_in_cidr?(ip_tuple, net, mask, bits)
    end)
  end

  # Normalize IPv4-mapped IPv6 addresses (::ffff:a.b.c.d) to pure IPv4 tuples.
  # This ensures CIDR checks work correctly when proxies report IPv4-mapped IPv6.
  defp normalize_ip({0, 0, 0, 0, 0, 65535, high, low}) do
    {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}
  end

  defp normalize_ip(ip), do: ip

  defp ip_in_cidr?(ip, net, mask, bits) do
    (if tuple_size(ip) == 4, do: 32, else: 128) == bits and
      ip_to_integer(ip) |> Bitwise.band(mask) ==
        ip_to_integer(net) |> Bitwise.band(mask)
  end

  defp ip_to_integer({a, b, c, d}) do
    Bitwise.bsl(a, 24) ||| Bitwise.bsl(b, 16) ||| Bitwise.bsl(c, 8) ||| d
  end

  defp ip_to_integer({a, b, c, d, e, f, g, h}) do
    Bitwise.bsl(a, 112) ||| Bitwise.bsl(b, 96) ||| Bitwise.bsl(c, 80) |||
      Bitwise.bsl(d, 64) ||| Bitwise.bsl(e, 48) ||| Bitwise.bsl(f, 32) |||
      Bitwise.bsl(g, 16) ||| h
  end

  defp parse_ip(ip_str) do
    ip_str
    |> String.trim()
    |> String.to_charlist()
    |> :inet.parse_address()
  end

  defp ip_to_string(ip_tuple) do
    ip_tuple
    |> :inet.ntoa()
    |> to_string()
  end
end
