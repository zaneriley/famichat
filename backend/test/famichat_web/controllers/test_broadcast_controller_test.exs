defmodule FamichatWeb.TestBroadcastControllerTest do
  use FamichatWeb.ConnCase, async: true

  alias Famichat.Auth.Sessions
  alias Famichat.ChatFixtures

  @endpoint FamichatWeb.Endpoint

  setup %{conn: conn} do
    family = ChatFixtures.family_fixture()

    user =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "alias_sender"
      })

    partner =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "alias_partner"
      })

    conversation =
      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :direct,
        user1: user,
        user2: partner
      })

    self_conversation =
      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :self,
        user1: user
      })

    partner_self_conversation =
      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :self,
        user1: partner
      })

    %{
      authed_conn: authed_conn(conn, user),
      conversation: conversation,
      self_conversation: self_conversation,
      partner_self_conversation: partner_self_conversation,
      user: user,
      partner: partner
    }
  end

  describe "POST /api/test/test_events (compatibility alias)" do
    test "returns canonical semantics with deprecation headers", %{
      authed_conn: authed_conn,
      conversation: conversation,
      user: user
    } do
      topic = topic(:direct, conversation.id)
      @endpoint.subscribe(topic)

      conn =
        post(authed_conn, ~p"/api/test/test_events", %{
          "conversation_type" => "direct",
          "conversation_id" => conversation.id,
          "body" => "alias canonical payload"
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["topic"] == topic
      assert response["event_name"] == "new_msg"
      assert response["payload"]["user_id"] == user.id

      assert_single_broadcast(topic, "new_msg", response["payload"])
      assert get_resp_header(conn, "deprecation") == ["true"]
      assert get_resp_header(conn, "sunset") != []
      assert get_resp_header(conn, "link") != []
    end

    test "accepts legacy topic/content payload and emits canonical new_msg", %{
      authed_conn: authed_conn,
      conversation: conversation,
      user: user
    } do
      topic = topic(:direct, conversation.id)
      @endpoint.subscribe(topic)

      conn =
        post(authed_conn, ~p"/api/test/test_events", %{
          "type" => "new_message",
          "topic" => topic,
          "content" => "legacy alias payload",
          "encryption" => true
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["topic"] == topic
      assert response["event_name"] == "new_msg"

      payload = response["payload"]
      assert payload["body"] == "legacy alias payload"
      assert payload["user_id"] == user.id
      assert payload["encryption_flag"] == true
      assert payload["key_id"] == "KEY_TEST_v1"
      assert payload["version_tag"] == "v1.0.0"

      assert_single_broadcast(topic, "new_msg", payload)
      assert get_resp_header(conn, "deprecation") == ["true"]
    end

    test "returns 422 with deprecation headers for invalid payload and does not broadcast",
         %{
           authed_conn: authed_conn,
           conversation: conversation
         } do
      topic = topic(:direct, conversation.id)
      @endpoint.subscribe(topic)

      conn =
        post(authed_conn, ~p"/api/test/test_events", %{
          "type" => "new_message",
          "topic" => topic,
          "content" => "",
          "encryption" => true,
          "key_id" => "bad"
        })

      response = json_response(conn, 422)
      assert response["status"] == "error"
      assert response["error"] == "invalid_request"
      assert Map.has_key?(response["details"], "body")
      assert Map.has_key?(response["details"], "key_id")

      assert_no_broadcast_on_topic(topic)
      assert get_resp_header(conn, "deprecation") == ["true"]
      assert get_resp_header(conn, "sunset") != []
    end

    test "self ownership checks still apply on legacy alias endpoint", %{
      authed_conn: authed_conn,
      user: user,
      partner: partner,
      partner_self_conversation: partner_self_conversation
    } do
      target_topic = topic(:self, partner.id)
      spoofed_topic = topic(:self, user.id)
      @endpoint.subscribe(target_topic)
      @endpoint.subscribe(spoofed_topic)

      conn =
        post(authed_conn, ~p"/api/test/test_events", %{
          "conversation_type" => "self",
          "conversation_id" => partner_self_conversation.id,
          "body" => "forbidden self target",
          "topic" => spoofed_topic
        })

      assert json_response(conn, 403) == %{
               "status" => "error",
               "error" => "forbidden"
             }

      assert_no_broadcast_on_topic(target_topic)
      assert_no_broadcast_on_topic(spoofed_topic)
      assert get_resp_header(conn, "deprecation") == ["true"]
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

  defp topic(:self, user_id) do
    "message:self:#{user_id}"
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
