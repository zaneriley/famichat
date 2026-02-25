defmodule FamichatWeb.API.ChatReadControllerTest do
  use FamichatWeb.ConnCase, async: true

  alias Famichat.Auth.Sessions
  alias Famichat.Chat.{ConversationVisibilityService, MessageService}
  alias Famichat.ChatFixtures

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

  test "lists visible conversations with previews and without PII", %{
    authed_conn: authed_conn,
    conversation: conversation,
    partner: partner,
    user: user,
    long_body: long_body
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

    expected_preview =
      long_body |> String.trim() |> String.slice(0, 120)

    assert conversation_json["last_message_preview"] == expected_preview
    assert String.length(conversation_json["last_message_preview"]) <= 120
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
    assert Enum.map(data, & &1["content"]) == ["msg-1", "msg-2"]

    error_response =
      authed_conn
      |> get(~p"/api/v1/conversations/#{conversation.id}/messages", %{
        limit: "oops"
      })
      |> json_response(422)

    assert error_response["error"] == "invalid_pagination"
    assert Map.has_key?(error_response["details"], "limit")
  end

  test "returns forbidden for conversations the user does not belong to", %{
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

    authed_conn
    |> get(~p"/api/v1/conversations/#{other_conversation.id}/messages")
    |> json_response(403)
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
