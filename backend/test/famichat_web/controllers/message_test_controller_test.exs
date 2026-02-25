defmodule FamichatWeb.MessageTestControllerTest do
  use FamichatWeb.ConnCase, async: true

  alias Famichat.Auth.Sessions
  alias Famichat.ChatFixtures

  @endpoint FamichatWeb.Endpoint

  setup %{conn: conn} do
    family = ChatFixtures.family_fixture()

    user =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "cli_sender"
      })

    partner =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "cli_partner"
      })

    outsider = ChatFixtures.user_fixture()

    conversation =
      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :direct,
        user1: user,
        user2: partner
      })

    authed_conn = authed_conn(conn, user)
    outsider_conn = authed_conn(conn, outsider)

    %{
      conn: conn,
      authed_conn: authed_conn,
      outsider_conn: outsider_conn,
      user: user,
      conversation: conversation
    }
  end

  describe "POST /api/test/broadcast (canonical)" do
    test "returns 200 and broadcasts exactly once for authorized request", %{
      authed_conn: authed_conn,
      user: user,
      conversation: conversation
    } do
      topic = topic(:direct, conversation.id)
      @endpoint.subscribe(topic)

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "direct",
          "conversation_id" => conversation.id,
          "body" => "hello from canonical endpoint",
          "topic" => "message:group:should-not-be-used"
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["topic"] == topic
      assert response["event_name"] == "new_msg"

      payload = response["payload"]
      assert payload["body"] == "hello from canonical endpoint"
      assert payload["user_id"] == user.id

      assert_single_broadcast(topic, "new_msg", payload)
    end

    test "returns 401 when bearer token is missing and does not broadcast", %{
      conn: conn,
      conversation: conversation
    } do
      topic = topic(:direct, conversation.id)
      @endpoint.subscribe(topic)

      conn =
        post(conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "direct",
          "conversation_id" => conversation.id,
          "body" => "should not broadcast"
        })

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
      assert_no_broadcast_on_topic(topic)
    end

    test "returns 401 when bearer token is invalid and does not broadcast", %{
      conn: conn,
      conversation: conversation
    } do
      topic = topic(:direct, conversation.id)
      @endpoint.subscribe(topic)

      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> post(~p"/api/test/broadcast", %{
          "conversation_type" => "direct",
          "conversation_id" => conversation.id,
          "body" => "should not broadcast"
        })

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
      assert_no_broadcast_on_topic(topic)
    end

    test "returns 403 for authenticated non-member and does not broadcast", %{
      outsider_conn: outsider_conn,
      conversation: conversation
    } do
      topic = topic(:direct, conversation.id)
      @endpoint.subscribe(topic)

      conn =
        post(outsider_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "direct",
          "conversation_id" => conversation.id,
          "body" => "unauthorized send"
        })

      assert json_response(conn, 403) == %{
               "status" => "error",
               "error" => "forbidden"
             }

      assert_no_broadcast_on_topic(topic)
    end

    test "returns 422 for invalid payload and does not broadcast", %{
      authed_conn: authed_conn,
      conversation: conversation
    } do
      topic = topic(:direct, conversation.id)
      @endpoint.subscribe(topic)

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "invalid",
          "conversation_id" => "not-a-uuid",
          "body" => "   "
        })

      response = json_response(conn, 422)
      assert response["status"] == "error"
      assert response["error"] == "invalid_request"
      assert Map.has_key?(response["details"], "conversation_type")
      assert Map.has_key?(response["details"], "conversation_id")
      assert Map.has_key?(response["details"], "body")

      assert_no_broadcast_on_topic(topic)
    end

    test "returns 422 for invalid encryption metadata and does not broadcast",
         %{
           authed_conn: authed_conn,
           conversation: conversation
         } do
      topic = topic(:direct, conversation.id)
      @endpoint.subscribe(topic)

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "direct",
          "conversation_id" => conversation.id,
          "body" => "encrypted",
          "encryption_flag" => true,
          "key_id" => "bad",
          "version_tag" => "v1.0.0"
        })

      response = json_response(conn, 422)
      assert response["status"] == "error"
      assert response["error"] == "invalid_request"
      assert response["details"]["key_id"] == "must match KEY_[A-Z]+_v[0-9]+"

      assert_no_broadcast_on_topic(topic)
    end
  end

  defp authed_conn(conn, user) do
    {:ok, session} =
      Sessions.start_session(
        user,
        %{id: Ecto.UUID.generate(), user_agent: "test-agent", ip: "127.0.0.1"},
        remember_device?: true
      )

    put_req_header(conn, "authorization", "Bearer #{session.access_token}")
  end

  defp topic(type, conversation_id) do
    "message:#{type}:#{conversation_id}"
  end

  defp assert_single_broadcast(topic, event, payload) do
    assert_receive %Phoenix.Socket.Broadcast{
      topic: ^topic,
      event: ^event,
      payload: ^payload
    }

    assert_no_broadcast_on_topic(topic)
  end

  defp assert_no_broadcast_on_topic(topic) do
    refute_receive %Phoenix.Socket.Broadcast{topic: ^topic}, 50
  end
end
