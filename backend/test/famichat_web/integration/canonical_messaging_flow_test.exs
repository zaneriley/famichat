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
      post(sender_conn, "/api/test/broadcast", %{
        "conversation_type" => "direct",
        "conversation_id" => conversation.id,
        "body" => "runbook canonical message",
        "topic" => "message:group:spoof-attempt"
      })

    response = json_response(conn, 200)
    assert response["status"] == "success"
    assert response["topic"] == topic
    assert response["event_name"] == "new_msg"
    assert response["payload"]["body"] == "runbook canonical message"

    expected_payload = response["payload"]
    assert_push "new_msg", ^expected_payload

    history_conn =
      sender_conn
      |> get("/api/v1/conversations/#{conversation.id}/messages")

    history = json_response(history_conn, 200)

    assert Enum.any?(history["data"], fn message ->
             message["content"] == "runbook canonical message"
           end)
  end

  test "missing bearer token returns 401 and emits no message", %{
    conversation: conversation
  } do
    conn =
      build_conn()
      |> post("/api/test/broadcast", %{
        "conversation_type" => "direct",
        "conversation_id" => conversation.id,
        "body" => "should not emit"
      })

    assert json_response(conn, 401) == %{"error" => "unauthorized"}
    refute_receive %Phoenix.Socket.Message{event: "new_msg"}, 100
  end

  test "authenticated outsider returns 404 and emits no message", %{
    outsider_conn: outsider_conn,
    conversation: conversation
  } do
    conn =
      post(outsider_conn, "/api/test/broadcast", %{
        "conversation_type" => "direct",
        "conversation_id" => conversation.id,
        "body" => "should not emit"
      })

    assert json_response(conn, 404) == %{
             "status" => "error",
             "error" => "not_found"
           }

    refute_receive %Phoenix.Socket.Message{event: "new_msg"}, 100
  end

  test "invalid payload returns 422 and emits no message", %{
    sender_conn: sender_conn
  } do
    conn =
      post(sender_conn, "/api/test/broadcast", %{
        "conversation_type" => "invalid",
        "conversation_id" => "not-a-uuid",
        "body" => " "
      })

    response = json_response(conn, 422)
    assert response["status"] == "error"
    assert response["error"] == "invalid_request"
    assert Map.has_key?(response["details"], "conversation_type")
    assert Map.has_key?(response["details"], "conversation_id")
    assert Map.has_key?(response["details"], "body")

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
        post(sender_conn, "/api/test/broadcast", %{
          "conversation_type" => "direct",
          "conversation_id" => conversation.id,
          "body" => "mixed-http-#{index}"
        })

      assert json_response(conn, 200)["status"] == "success"
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
        id: "runbook-flow-#{suffix}-#{System.unique_integer([:positive])}",
        user_agent: "canonical-messaging-flow-test",
        ip: "127.0.0.1"
      },
      remember_device?: true
    )
  end
end
