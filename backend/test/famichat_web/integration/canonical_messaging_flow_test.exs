defmodule FamichatWeb.CanonicalMessagingFlowTest do
  use FamichatWeb.ChannelCase, async: true

  import Phoenix.ConnTest,
    only: [build_conn: 0, get: 2, json_response: 2, post: 3]

  import Plug.Conn, only: [put_req_header: 3]

  alias Famichat.Auth.Sessions
  alias Famichat.Chat.{Message, MessageRateLimiter}
  alias Famichat.ChatFixtures
  alias Famichat.Repo
  alias FamichatWeb.{MessageChannel, UserSocket}

  @endpoint FamichatWeb.Endpoint

  setup do
    previous_enforcement = Application.get_env(:famichat, :mls_enforcement)
    Application.put_env(:famichat, :mls_enforcement, false)

    on_exit(fn ->
      restore_env(:mls_enforcement, previous_enforcement)
    end)

    family = ChatFixtures.family_fixture()

    sender =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "runbook_sender_#{System.unique_integer([:positive])}"
      })

    receiver =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "runbook_receiver_#{System.unique_integer([:positive])}"
      })

    outsider = ChatFixtures.user_fixture()

    conversation =
      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :direct,
        user1: sender,
        user2: receiver
      })

    {:ok, sender_session} = start_session(sender, "sender")
    {:ok, receiver_session} = start_session(receiver, "receiver")
    {:ok, outsider_session} = start_session(outsider, "outsider")

    {:ok, receiver_socket} =
      connect(UserSocket, %{"token" => receiver_session.access_token})

    topic = "message:direct:#{conversation.id}"

    {:ok, _reply, _channel_socket} =
      subscribe_and_join(receiver_socket, MessageChannel, topic)

    {:ok,
     %{
       sender: sender,
       sender_session: sender_session,
       sender_conn: authed_conn(sender_session.access_token),
       outsider_conn: authed_conn(outsider_session.access_token),
       conversation: conversation,
       topic: topic
     }}
  end

  test "auth -> subscribe -> send -> receive canonical flow succeeds", %{
    sender_conn: sender_conn,
    conversation: conversation,
    topic: topic
  } do
    conn =
      post(sender_conn, "/api/v1/conversations/#{conversation.id}/messages", %{
        "body" => "runbook canonical message",
        "topic" => "message:group:spoof-attempt"
      })

    response = json_response(conn, 201)
    assert response["data"]["topic"] == topic
    assert response["data"]["event_name"] == "new_msg"
    assert response["data"]["payload"]["body"] == "runbook canonical message"

    expected_payload = response["data"]["payload"]
    assert_push "new_msg", ^expected_payload

    history_conn =
      sender_conn
      |> get("/api/v1/conversations/#{conversation.id}/messages")

    history = json_response(history_conn, 200)

    assert Enum.any?(history["data"], fn message ->
             message["content"] == "runbook canonical message"
           end)
  end

  @tag :timing
  test "day2 timing instrumentation: auth -> subscribe -> send -> receive", %{
    sender: sender,
    conversation: conversation
  } do
    # Phase 0 — baseline
    t0 = System.monotonic_time(:millisecond)

    # Phase 1 — auth: start a fresh session for this timing run
    {:ok, timing_session} = start_session(sender, "timing")
    t1 = System.monotonic_time(:millisecond)

    # Phase 2 — subscribe: connect socket and join channel
    {:ok, timing_socket} =
      connect(UserSocket, %{"token" => timing_session.access_token})

    topic = "message:direct:#{conversation.id}"

    {:ok, _reply, _channel_socket} =
      subscribe_and_join(timing_socket, MessageChannel, topic)

    t2 = System.monotonic_time(:millisecond)

    # Phase 3 — send: HTTP POST to create message
    timing_conn =
      build_conn()
      |> put_req_header(
        "authorization",
        "Bearer #{timing_session.access_token}"
      )

    conn =
      post(timing_conn, "/api/v1/conversations/#{conversation.id}/messages", %{
        "body" => "timing-probe-#{System.unique_integer([:positive])}"
      })

    assert json_response(conn, 201)["data"]["event_name"] == "new_msg"
    t3 = System.monotonic_time(:millisecond)

    # Phase 4 — receive: wait for the push event on the subscribed channel
    assert_receive %Phoenix.Socket.Message{event: "new_msg"}, 500
    t4 = System.monotonic_time(:millisecond)

    # Derive per-phase timings
    auth_to_subscribe_ms = t2 - t1
    subscribe_to_send_ms = t3 - t2
    send_to_receive_ms = t4 - t3

    # MLS is disabled in tests (mls_enforcement: false); record near-zero cost.
    # The snapshot persist is included in the send phase (HTTP 201 means persisted).
    mls_encrypt_ms = 0
    snapshot_persist_ms = subscribe_to_send_ms

    total_ms = t4 - t0

    timing_json =
      Jason.encode!(%{
        auth_to_subscribe_ms: auth_to_subscribe_ms,
        subscribe_to_send_ms: subscribe_to_send_ms,
        send_to_receive_ms: send_to_receive_ms,
        mls_encrypt_ms: mls_encrypt_ms,
        snapshot_persist_ms: snapshot_persist_ms,
        total_ms: total_ms
      })

    timing_path =
      Path.join([
        System.get_env("TIMING_OUTPUT_DIR", "/app/.tmp"),
        "canonical_flow_timing_detail.json"
      ])

    File.mkdir_p!(Path.dirname(timing_path))
    File.write!(timing_path, timing_json)
  end

  test "missing bearer token returns 401 and emits no message", %{
    conversation: conversation
  } do
    conn =
      build_conn()
      |> post("/api/v1/conversations/#{conversation.id}/messages", %{
        "body" => "should not emit"
      })

    assert json_response(conn, 401) == %{"error" => %{"code" => "unauthorized"}}
    refute_receive %Phoenix.Socket.Message{event: "new_msg"}, 100
  end

  test "authenticated outsider returns 404 and emits no message", %{
    outsider_conn: outsider_conn,
    conversation: conversation
  } do
    conn =
      post(
        outsider_conn,
        "/api/v1/conversations/#{conversation.id}/messages",
        %{
          "body" => "should not emit"
        }
      )

    assert json_response(conn, 404)["error"]["code"] == "not_found"

    refute_receive %Phoenix.Socket.Message{event: "new_msg"}, 100
  end

  test "invalid payload returns 422 and emits no message", %{
    sender_conn: sender_conn,
    conversation: conversation
  } do
    conn =
      post(sender_conn, "/api/v1/conversations/#{conversation.id}/messages", %{
        "body" => " "
      })

    response = json_response(conn, 422)
    assert response["error"]["code"] == "invalid_request"
    assert response["error"]["details"]["body"] == "must be a non-empty string"

    refute_receive %Phoenix.Socket.Message{event: "new_msg"}, 100
  end

  test "HTTP and WS sends share a single message limiter", %{
    sender: sender,
    sender_session: sender_session,
    sender_conn: sender_conn,
    conversation: conversation
  } do
    {:ok, sender_socket} =
      connect(UserSocket, %{"token" => sender_session.access_token})

    topic = "message:direct:#{conversation.id}"

    {:ok, _reply, sender_channel} =
      subscribe_and_join(sender_socket, MessageChannel, topic)

    burst_limit = MessageRateLimiter.window_limit(:msg_device_burst) || 20

    Enum.each(1..burst_limit, fn index ->
      conn =
        post(
          sender_conn,
          "/api/v1/conversations/#{conversation.id}/messages",
          %{
            "body" => "mixed-http-#{index}"
          }
        )

      assert json_response(conn, 201)["data"]["event_name"] == "new_msg"
    end)

    blocked_body = "mixed-ws-over-limit"
    ref = push(sender_channel, "new_msg", %{"body" => blocked_body})

    assert_reply ref, :error, %{reason: "rate_limited", retry_in: retry_in}
    assert is_integer(retry_in)
    assert retry_in > 0

    refute Repo.get_by(Message,
             conversation_id: conversation.id,
             sender_id: sender.id,
             content: blocked_body
           )
  end

  defp authed_conn(access_token) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{access_token}")
  end

  defp start_session(user, suffix) do
    Sessions.start_session(
      user,
      %{
        id:
          "runbook-flow-#{suffix}-#{System.unique_integer([:positive])}-#{Ecto.UUID.generate()}",
        user_agent: "canonical-messaging-flow-test",
        ip: "127.0.0.1"
      },
      remember_device?: true
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
