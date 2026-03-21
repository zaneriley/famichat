defmodule FamichatWeb.API.ChatReadControllerTest do
  use FamichatWeb.ConnCase, async: false

  alias Famichat.Auth.Sessions
  alias Famichat.Chat.{ConversationVisibilityService, MessageService}
  alias Famichat.ChatFixtures

  setup do
    previous = Application.get_env(:famichat, :mls_enforcement, false)
    Application.put_env(:famichat, :mls_enforcement, false)

    on_exit(fn ->
      Application.put_env(:famichat, :mls_enforcement, previous)
    end)

    :ok
  end

  setup %{conn: conn} do
    family = ChatFixtures.family_fixture()

    user =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "alpha_user"
      })

    partner =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "beta_partner"
      })

    conversation =
      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :direct,
        user1: user,
        user2: partner
      })

    long_body = String.duplicate("hello world ", 12)

    {:ok, _message} =
      MessageService.send_message(%{
        conversation_id: conversation.id,
        sender_id: partner.id,
        content: long_body
      })

    hidden_conversation =
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

    ConversationVisibilityService.hide_conversation(
      hidden_conversation.id,
      user.id
    )

    {:ok, session} =
      Sessions.start_session(
        user,
        %{id: Ecto.UUID.generate(), user_agent: "test-agent", ip: "127.0.0.1"},
        remember_device?: true
      )

    authed_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{session.access_token}")

    %{
      conn: conn,
      authed_conn: authed_conn,
      user: user,
      partner: partner,
      conversation: conversation,
      partner_self_conversation: partner_self_conversation,
      long_body: long_body
    }
  end

  test "lists visible conversations without PII", %{
    authed_conn: authed_conn,
    conversation: conversation,
    partner: partner,
    user: user
  } do
    response =
      authed_conn
      |> get(~p"/api/v1/me/conversations")
      |> json_response(200)

    assert %{"data" => [conversation_json]} = response
    assert conversation_json["id"] == conversation.id
    assert conversation_json["conversation_type"] == "direct"
    assert conversation_json["title"] == partner.username

    assert Enum.sort(conversation_json["participant_usernames"]) ==
             Enum.sort([user.username, partner.username])

    refute Enum.any?(conversation_json["participant_usernames"], fn username ->
             String.contains?(username, "@")
           end)

    refute Map.has_key?(conversation_json, "last_message_preview")
  end

  test "does not include another user's self conversation in me conversations",
       %{
         authed_conn: authed_conn,
         partner_self_conversation: partner_self_conversation
       } do
    response =
      authed_conn
      |> get(~p"/api/v1/me/conversations")
      |> json_response(200)

    refute Enum.any?(response["data"], fn conversation_json ->
             conversation_json["id"] == partner_self_conversation.id
           end)
  end

  test "does not leak foreign family conversations in me conversations", %{
    conn: conn,
    conversation: conversation,
    partner_self_conversation: partner_self_conversation
  } do
    outsider = ChatFixtures.user_fixture()

    {:ok, outsider_session} =
      Sessions.start_session(
        outsider,
        %{id: Ecto.UUID.generate(), user_agent: "test-agent", ip: "127.0.0.1"},
        remember_device?: true
      )

    outsider_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header(
        "authorization",
        "Bearer #{outsider_session.access_token}"
      )

    response =
      outsider_conn
      |> get(~p"/api/v1/me/conversations")
      |> json_response(200)

    refute Enum.any?(response["data"], fn conversation_json ->
             conversation_json["id"] in [
               conversation.id,
               partner_self_conversation.id
             ]
           end)
  end

  test "paginates messages oldest to newest using cast params", %{
    authed_conn: authed_conn,
    conversation: conversation,
    partner: partner
  } do
    for content <- ["msg-1", "msg-2", "msg-3"] do
      {:ok, _} =
        MessageService.send_message(%{
          conversation_id: conversation.id,
          sender_id: partner.id,
          content: content
        })
    end

    response =
      authed_conn
      |> get(~p"/api/v1/conversations/#{conversation.id}/messages", %{
        limit: "2",
        offset: "1"
      })
      |> json_response(200)

    assert %{"data" => data} = response
    assert response["meta"]["has_more"] == true
    assert is_integer(response["meta"]["next_cursor"])
    assert Enum.map(data, & &1["content"]) == ["msg-1", "msg-2"]

    error_response =
      authed_conn
      |> get(~p"/api/v1/conversations/#{conversation.id}/messages", %{
        limit: "oops"
      })
      |> json_response(422)

    assert error_response["error"] == %{"code" => "invalid_pagination"}
    assert Map.has_key?(error_response["details"], "limit")
  end

  test "supports catch-up via after cursor", %{
    authed_conn: authed_conn,
    conversation: conversation,
    partner: partner
  } do
    {:ok, m1} =
      MessageService.send_message(%{
        conversation_id: conversation.id,
        sender_id: partner.id,
        content: "msg-1"
      })

    {:ok, m2} =
      MessageService.send_message(%{
        conversation_id: conversation.id,
        sender_id: partner.id,
        content: "msg-2"
      })

    {:ok, m3} =
      MessageService.send_message(%{
        conversation_id: conversation.id,
        sender_id: partner.id,
        content: "msg-3"
      })

    {:ok, m4} =
      MessageService.send_message(%{
        conversation_id: conversation.id,
        sender_id: partner.id,
        content: "msg-4"
      })

    page_1 =
      authed_conn
      |> get(~p"/api/v1/conversations/#{conversation.id}/messages", %{
        after: m1.message_seq,
        limit: "2"
      })
      |> json_response(200)

    assert Enum.map(page_1["data"], & &1["id"]) == [m2.id, m3.id]
    assert page_1["meta"]["has_more"] == true
    assert page_1["meta"]["next_cursor"] == m3.message_seq

    page_2 =
      authed_conn
      |> get(~p"/api/v1/conversations/#{conversation.id}/messages", %{
        after: page_1["meta"]["next_cursor"],
        limit: "2"
      })
      |> json_response(200)

    assert Enum.map(page_2["data"], & &1["id"]) == [m4.id]
    assert page_2["meta"]["has_more"] == false
    assert page_2["meta"]["next_cursor"] == m4.message_seq
  end

  test "returns invalid_pagination when after cursor is not a valid integer", %{
    authed_conn: authed_conn,
    conversation: conversation
  } do
    response =
      authed_conn
      |> get(~p"/api/v1/conversations/#{conversation.id}/messages", %{
        after: "not-a-uuid"
      })
      |> json_response(422)

    assert response["error"] == %{"code" => "invalid_pagination"}
    assert Map.has_key?(response["details"], "after")
  end

  test "returns invalid_pagination when after and offset are combined", %{
    authed_conn: authed_conn,
    conversation: conversation,
    partner: partner
  } do
    {:ok, first_message} =
      MessageService.send_message(%{
        conversation_id: conversation.id,
        sender_id: partner.id,
        content: "msg-1"
      })

    response =
      authed_conn
      |> get(~p"/api/v1/conversations/#{conversation.id}/messages", %{
        after: first_message.message_seq,
        offset: "1"
      })
      |> json_response(422)

    assert response["error"] == %{"code" => "invalid_pagination"}
    assert Map.has_key?(response["details"], "offset")
  end

  test "after cursor with message_seq beyond conversation range returns empty data",
       %{
         authed_conn: authed_conn,
         conversation: conversation
       } do
    # With integer message_seq cursors, there is no cross-conversation
    # validation. A message_seq value beyond the conversation's range
    # simply returns no results.
    response =
      authed_conn
      |> get(~p"/api/v1/conversations/#{conversation.id}/messages", %{
        after: 999_999
      })
      |> json_response(200)

    assert response["data"] == []
    assert response["meta"]["has_more"] == false
  end

  test "returns not_found for conversations the user does not belong to", %{
    authed_conn: authed_conn,
    partner: partner
  } do
    outsider = ChatFixtures.user_fixture()

    other_conversation =
      ChatFixtures.conversation_fixture(%{
        conversation_type: :direct,
        user1: partner,
        user2: outsider
      })

    response =
      authed_conn
      |> get(~p"/api/v1/conversations/#{other_conversation.id}/messages")
      |> json_response(404)

    assert response == %{"error" => %{"code" => "not_found"}}
  end

  test "returns indistinguishable not_found for inaccessible vs unknown conversation ids",
       %{
         authed_conn: authed_conn,
         partner: partner
       } do
    outsider = ChatFixtures.user_fixture()

    foreign_conversation =
      ChatFixtures.conversation_fixture(%{
        conversation_type: :direct,
        user1: partner,
        user2: outsider
      })

    existing_response =
      authed_conn
      |> get(~p"/api/v1/conversations/#{foreign_conversation.id}/messages")
      |> json_response(404)

    unknown_response =
      authed_conn
      |> get(~p"/api/v1/conversations/#{Ecto.UUID.generate()}/messages")
      |> json_response(404)

    assert existing_response == %{"error" => %{"code" => "not_found"}}
    assert unknown_response == %{"error" => %{"code" => "not_found"}}
    assert existing_response == unknown_response
  end

  test "returns unauthorized when bearer token is missing", %{
    conn: conn,
    conversation: conversation
  } do
    conn
    |> get(~p"/api/v1/me/conversations")
    |> json_response(401)

    conn
    |> get(~p"/api/v1/conversations/#{conversation.id}/messages")
    |> json_response(401)
  end

  test "returns not_found for unknown conversation id", %{
    authed_conn: authed_conn
  } do
    authed_conn
    |> get(~p"/api/v1/conversations/#{Ecto.UUID.generate()}/messages")
    |> json_response(404)
  end
end
