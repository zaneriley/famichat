defmodule FamichatWeb.MessageTestControllerTest do
  use FamichatWeb.ConnCase, async: true

  alias Famichat.Auth.Sessions
  alias Famichat.Chat.{Message, MessageRateLimiter}
  alias Famichat.ChatFixtures
  alias Famichat.Repo

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

    group_conversation =
      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :group,
        user1: user
      })

    family_conversation =
      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :family
      })

    authed_conn = authed_conn(conn, user)
    outsider_conn = authed_conn(conn, outsider)

    %{
      conn: conn,
      authed_conn: authed_conn,
      outsider_conn: outsider_conn,
      user: user,
      partner: partner,
      conversation: conversation,
      self_conversation: self_conversation,
      partner_self_conversation: partner_self_conversation,
      group_conversation: group_conversation,
      family_conversation: family_conversation
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
      assert Map.has_key?(payload, "device_id")

      assert_single_broadcast(topic, "new_msg", payload)

      persisted =
        Repo.get_by(Message,
          conversation_id: conversation.id,
          sender_id: user.id,
          content: "hello from canonical endpoint"
        )

      assert persisted
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

    test "returns 404 for authenticated non-member and does not broadcast", %{
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

      assert json_response(conn, 404) == %{
               "status" => "error",
               "error" => "not_found"
             }

      assert_no_broadcast_on_topic(topic)
    end

    test "returns indistinguishable not_found for inaccessible vs unknown conversation ids",
         %{
           outsider_conn: outsider_conn,
           conversation: conversation
         } do
      existing_topic = topic(:direct, conversation.id)
      random_id = Ecto.UUID.generate()
      unknown_topic = topic(:direct, random_id)

      @endpoint.subscribe(existing_topic)
      @endpoint.subscribe(unknown_topic)

      existing_response =
        outsider_conn
        |> post(~p"/api/test/broadcast", %{
          "conversation_type" => "direct",
          "conversation_id" => conversation.id,
          "body" => "enumeration probe existing id"
        })
        |> json_response(404)

      unknown_response =
        outsider_conn
        |> post(~p"/api/test/broadcast", %{
          "conversation_type" => "direct",
          "conversation_id" => random_id,
          "body" => "enumeration probe unknown id"
        })
        |> json_response(404)

      assert existing_response == %{"status" => "error", "error" => "not_found"}
      assert unknown_response == %{"status" => "error", "error" => "not_found"}
      assert existing_response == unknown_response

      assert_no_broadcast_on_topic(existing_topic)
      assert_no_broadcast_on_topic(unknown_topic)
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

    test "broadcasts successfully for the caller's own self conversation", %{
      authed_conn: authed_conn,
      user: user,
      self_conversation: self_conversation
    } do
      topic = topic(:self, user.id)
      @endpoint.subscribe(topic)

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "self",
          "conversation_id" => self_conversation.id,
          "body" => "note to self",
          "topic" => "message:direct:#{Ecto.UUID.generate()}"
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["topic"] == topic
      assert response["event_name"] == "new_msg"
      assert response["payload"]["body"] == "note to self"
      assert response["payload"]["user_id"] == user.id

      assert_single_broadcast(topic, "new_msg", response["payload"])
    end

    test "returns 403 when trying to target another user's self conversation even with a caller-supplied topic",
         %{
           authed_conn: authed_conn,
           user: user,
           partner: partner,
           partner_self_conversation: partner_self_conversation
         } do
      partner_topic = topic(:self, partner.id)
      spoofed_topic = topic(:self, user.id)
      @endpoint.subscribe(partner_topic)
      @endpoint.subscribe(spoofed_topic)

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "self",
          "conversation_id" => partner_self_conversation.id,
          "body" => "should be rejected",
          "topic" => spoofed_topic
        })

      assert json_response(conn, 403) == %{
               "status" => "error",
               "error" => "forbidden"
             }

      assert_no_broadcast_on_topic(partner_topic)
      assert_no_broadcast_on_topic(spoofed_topic)
    end

    test "ignores topic-only self spoof attempts and broadcasts to caller self topic",
         %{
           authed_conn: authed_conn,
           user: user,
           partner: partner
         } do
      caller_topic = topic(:self, user.id)
      spoofed_topic = topic(:self, partner.id)

      @endpoint.subscribe(caller_topic)
      @endpoint.subscribe(spoofed_topic)

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "topic" => spoofed_topic,
          "content" => "topic-only spoof attempt"
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["topic"] == caller_topic
      assert response["event_name"] == "new_msg"
      assert response["payload"]["body"] == "topic-only spoof attempt"
      assert response["payload"]["user_id"] == user.id

      assert_single_broadcast(caller_topic, "new_msg", response["payload"])
      assert_no_broadcast_on_topic(spoofed_topic)
    end

    test "broadcasts successfully for group conversations", %{
      authed_conn: authed_conn,
      user: user,
      group_conversation: group_conversation
    } do
      topic = topic(:group, group_conversation.id)
      @endpoint.subscribe(topic)

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "group",
          "conversation_id" => group_conversation.id,
          "body" => "group message"
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["topic"] == topic
      assert response["event_name"] == "new_msg"
      assert response["payload"]["body"] == "group message"
      assert response["payload"]["user_id"] == user.id

      assert_single_broadcast(topic, "new_msg", response["payload"])
    end

    test "broadcasts successfully for family conversations", %{
      authed_conn: authed_conn,
      user: user,
      family_conversation: family_conversation
    } do
      topic = topic(:family, family_conversation.id)
      @endpoint.subscribe(topic)

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "family",
          "conversation_id" => family_conversation.id,
          "body" => "family message"
        })

      response = json_response(conn, 200)
      assert response["status"] == "success"
      assert response["topic"] == topic
      assert response["event_name"] == "new_msg"
      assert response["payload"]["body"] == "family message"
      assert response["payload"]["user_id"] == user.id

      assert_single_broadcast(topic, "new_msg", response["payload"])
    end

    test "returns 422 when conversation_type does not match stored conversation and does not broadcast",
         %{
           authed_conn: authed_conn,
           conversation: conversation
         } do
      direct_topic = topic(:direct, conversation.id)
      spoofed_topic = topic(:group, conversation.id)
      @endpoint.subscribe(direct_topic)
      @endpoint.subscribe(spoofed_topic)

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "group",
          "conversation_id" => conversation.id,
          "body" => "mismatch should fail"
        })

      response = json_response(conn, 422)
      assert response["status"] == "error"
      assert response["error"] == "invalid_request"

      assert response["details"]["conversation_type"] ==
               "does not match conversation"

      assert_no_broadcast_on_topic(direct_topic)
      assert_no_broadcast_on_topic(spoofed_topic)
    end

    test "returns 404 for unknown but well-formed conversation UUID and does not broadcast",
         %{
           authed_conn: authed_conn
         } do
      random_id = Ecto.UUID.generate()
      topic = topic(:direct, random_id)
      @endpoint.subscribe(topic)

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "direct",
          "conversation_id" => random_id,
          "body" => "missing conversation should fail"
        })

      response = json_response(conn, 404)
      assert response["status"] == "error"
      assert response["error"] == "not_found"

      assert_no_broadcast_on_topic(topic)
    end

    test "returns 413 for oversized body and does not broadcast or persist", %{
      authed_conn: authed_conn,
      conversation: conversation,
      user: user
    } do
      topic = topic(:direct, conversation.id)
      @endpoint.subscribe(topic)

      oversized_body = String.duplicate("a", Message.max_content_bytes() + 1)

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "direct",
          "conversation_id" => conversation.id,
          "body" => oversized_body
        })

      response = json_response(conn, 413)

      assert response == %{
               "status" => "error",
               "error" => "message_too_large",
               "max_bytes" => Message.max_content_bytes()
             }

      assert_no_broadcast_on_topic(topic)

      refute Repo.get_by(Message,
               conversation_id: conversation.id,
               sender_id: user.id,
               content: oversized_body
             )
    end

    test "returns 429 with retry hint when send burst exceeds rate limits", %{
      authed_conn: authed_conn,
      conversation: conversation,
      user: user
    } do
      burst_limit = MessageRateLimiter.window_limit(:msg_device_burst) || 20

      Enum.each(1..burst_limit, fn index ->
        conn =
          post(authed_conn, ~p"/api/test/broadcast", %{
            "conversation_type" => "direct",
            "conversation_id" => conversation.id,
            "body" => "http-burst-#{index}"
          })

        assert json_response(conn, 200)["status"] == "success"
      end)

      blocked_body = "http-burst-over-limit"

      conn =
        post(authed_conn, ~p"/api/test/broadcast", %{
          "conversation_type" => "direct",
          "conversation_id" => conversation.id,
          "body" => blocked_body
        })

      response = json_response(conn, 429)
      assert response["status"] == "error"
      assert response["error"] == "rate_limited"
      assert is_integer(response["retry_in"])
      assert response["retry_in"] > 0

      assert get_resp_header(conn, "retry-after") == [
               Integer.to_string(response["retry_in"])
             ]

      refute Repo.get_by(Message,
               conversation_id: conversation.id,
               sender_id: user.id,
               content: blocked_body
             )
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
