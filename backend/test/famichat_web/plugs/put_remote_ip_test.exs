defmodule FamichatWeb.Plugs.PutRemoteIpTest do
  use FamichatWeb.ConnCase, async: true

  alias FamichatWeb.Plugs.PutRemoteIp

  describe "resolve_client_ip/1" do
    test "uses conn.remote_ip when no X-Forwarded-For header" do
      conn =
        build_conn()
        |> Map.put(:remote_ip, {203, 0, 113, 42})

      assert PutRemoteIp.resolve_client_ip(conn) == "203.0.113.42"
    end

    test "parses X-Forwarded-For when peer is a trusted proxy (loopback)" do
      conn =
        build_conn()
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> put_req_header("x-forwarded-for", "198.51.100.7")

      assert PutRemoteIp.resolve_client_ip(conn) == "198.51.100.7"
    end

    test "parses X-Forwarded-For when peer is a trusted proxy (docker bridge)" do
      conn =
        build_conn()
        |> Map.put(:remote_ip, {172, 17, 0, 1})
        |> put_req_header("x-forwarded-for", "198.51.100.7")

      assert PutRemoteIp.resolve_client_ip(conn) == "198.51.100.7"
    end

    test "parses X-Forwarded-For when peer is RFC 1918 (192.168.x.x)" do
      conn =
        build_conn()
        |> Map.put(:remote_ip, {192, 168, 1, 1})
        |> put_req_header("x-forwarded-for", "203.0.113.50")

      assert PutRemoteIp.resolve_client_ip(conn) == "203.0.113.50"
    end

    test "ignores X-Forwarded-For when peer is NOT a trusted proxy" do
      conn =
        build_conn()
        |> Map.put(:remote_ip, {203, 0, 113, 1})
        |> put_req_header("x-forwarded-for", "198.51.100.99")

      # Untrusted peer — use conn.remote_ip, ignore header
      assert PutRemoteIp.resolve_client_ip(conn) == "203.0.113.1"
    end

    test "picks rightmost non-trusted IP from multi-hop chain" do
      conn =
        build_conn()
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> put_req_header("x-forwarded-for", "198.51.100.7, 10.0.0.1, 192.168.1.1")

      # 192.168.1.1 and 10.0.0.1 are trusted, so pick 198.51.100.7
      assert PutRemoteIp.resolve_client_ip(conn) == "198.51.100.7"
    end

    test "falls back to peer IP when all forwarded IPs are trusted" do
      conn =
        build_conn()
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> put_req_header("x-forwarded-for", "10.0.0.5, 192.168.1.1")

      assert PutRemoteIp.resolve_client_ip(conn) == "127.0.0.1"
    end

    test "handles empty X-Forwarded-For header" do
      conn =
        build_conn()
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> put_req_header("x-forwarded-for", "")

      assert PutRemoteIp.resolve_client_ip(conn) == "127.0.0.1"
    end

    test "normalizes IPv4-mapped IPv6 address to IPv4 for CIDR matching" do
      # ::ffff:127.0.0.1 represented as an 8-tuple IPv6 address
      # 127.0.0.1 = 0x7F000001 → high=0x7F00, low=0x0001
      conn =
        build_conn()
        |> Map.put(:remote_ip, {0, 0, 0, 0, 0, 65535, 0x7F00, 0x0001})
        |> put_req_header("x-forwarded-for", "198.51.100.7")

      # Should normalize to 127.0.0.1 (trusted), then parse X-Forwarded-For
      assert PutRemoteIp.resolve_client_ip(conn) == "198.51.100.7"
    end
  end

  describe "call/2 (plug integration)" do
    test "stores resolved IP in session" do
      conn =
        session_conn()
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> put_req_header("x-forwarded-for", "203.0.113.42")
        |> PutRemoteIp.call(PutRemoteIp.init([]))

      assert get_session(conn, "remote_ip") == "203.0.113.42"
    end

    test "stores peer IP when no proxy header" do
      conn =
        session_conn()
        |> Map.put(:remote_ip, {203, 0, 113, 7})
        |> PutRemoteIp.call(PutRemoteIp.init([]))

      assert get_session(conn, "remote_ip") == "203.0.113.7"
    end
  end
end
