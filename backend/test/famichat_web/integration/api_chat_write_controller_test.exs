defmodule FamichatWeb.APIChatWriteControllerTest do
  use FamichatWeb.ChannelCase, async: false

  import Phoenix.ConnTest,
    only: [build_conn: 0, get: 2, json_response: 2, post: 3]

  import Plug.Conn, only: [put_req_header: 3]

  alias Famichat.Auth.Sessions
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.MLS.RecoveryGateAdapter
  alias FamichatWeb.{MessageChannel, UserSocket}

  @endpoint FamichatWeb.Endpoint

  setup do
    previous_adapter = Application.get_env(:famichat, :mls_adapter)
    previous_enforcement = Application.get_env(:famichat, :mls_enforcement)

    Application.put_env(:famichat, :mls_enforcement, false)

    on_exit(fn ->
      restore_env(:mls_adapter, previous_adapter)
      restore_env(:mls_enforcement, previous_enforcement)
    end)

    family = ChatFixtures.family_fixture()

    sender =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "api_write_sender_#{System.unique_integer([:positive])}"
      })

    receiver =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "api_write_receiver_#{System.unique_integer([:positive])}"
      })

    conversation =
      ChatFixtures.conversation_fixture(%{
        family_id: family.id,
        conversation_type: :direct,
        user1: sender,
        user2: receiver
      })

    {:ok, sender_session} = start_session(sender, "sender")
    {:ok, receiver_session} = start_session(receiver, "receiver")

    {:ok,
     %{
       sender_conn: authed_conn(sender_session.access_token),
       sender_token: sender_session.access_token,
       receiver_conn: authed_conn(receiver_session.access_token),
       receiver_token: receiver_session.access_token,
       conversation: conversation,
       topic: "message:direct:#{conversation.id}"
     }}
  end

  test "POST /api/v1/conversations/:id/messages broadcasts + persists", %{
    sender_conn: sender_conn,
    receiver_conn: receiver_conn,
    receiver_token: receiver_token,
    conversation: conversation,
    topic: topic
  } do
    {:ok, receiver_socket} = connect(UserSocket, %{"token" => receiver_token})

    {:ok, _reply, _channel} =
      subscribe_and_join(receiver_socket, MessageChannel, topic)

    conn =
      post(sender_conn, "/api/v1/conversations/#{conversation.id}/messages", %{
        "body" => "hello from production endpoint"
      })

    response = json_response(conn, 201)
    assert response["data"]["topic"] == topic
    assert response["data"]["event_name"] == "new_msg"

    assert response["data"]["payload"]["body"] ==
             "hello from production endpoint"

    assert is_binary(response["data"]["payload"]["message_id"])

    expected_payload = response["data"]["payload"]
    assert_push "new_msg", ^expected_payload

    history =
      receiver_conn
      |> get("/api/v1/conversations/#{conversation.id}/messages")
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.any?(
             history,
             &(&1["content"] == "hello from production endpoint")
           )
  end

  test "POST /api/v1/conversations/:id/messages returns 422 on invalid body", %{
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
  end

  test "POST /api/v1/conversations/:id/security/recover is idempotent and unblocks send",
       %{
         sender_conn: sender_conn,
         conversation: conversation
       } do
    Application.put_env(:famichat, :mls_adapter, RecoveryGateAdapter)
    Application.put_env(:famichat, :mls_enforcement, true)

    blocked =
      post(sender_conn, "/api/v1/conversations/#{conversation.id}/messages", %{
        "body" => "blocked-before-recovery"
      })

    blocked_response = json_response(blocked, 409)
    assert blocked_response["error"]["code"] == "recovery_required"

    assert blocked_response["error"]["action"] ==
             "recover_conversation_security_state"

    recovery_ref = "api-recovery-#{System.unique_integer([:positive])}"

    recover_conn =
      post(
        sender_conn,
        "/api/v1/conversations/#{conversation.id}/security/recover",
        %{
          "recovery_ref" => recovery_ref,
          "rejoin_token" => "rejoin-token-#{System.unique_integer([:positive])}"
        }
      )

    recover_response = json_response(recover_conn, 200)
    assert recover_response["data"]["recovery_ref"] == recovery_ref
    assert recover_response["data"]["idempotent"] == false

    replay_conn =
      post(
        sender_conn,
        "/api/v1/conversations/#{conversation.id}/security/recover",
        %{
          "recovery_ref" => recovery_ref,
          "rejoin_token" => "ignored-on-replay"
        }
      )

    replay_response = json_response(replay_conn, 200)
    assert replay_response["data"]["idempotent"] == true

    assert replay_response["data"]["recovery_id"] ==
             recover_response["data"]["recovery_id"]

    delivered =
      post(sender_conn, "/api/v1/conversations/#{conversation.id}/messages", %{
        "body" => "delivered-after-recovery"
      })

    delivered_response = json_response(delivered, 201)

    assert delivered_response["data"]["payload"]["body"] ==
             "delivered-after-recovery"
  end

  test "POST /api/v1/conversations/:id/security/recover validates params", %{
    sender_conn: sender_conn,
    conversation: conversation
  } do
    conn =
      post(
        sender_conn,
        "/api/v1/conversations/#{conversation.id}/security/recover",
        %{}
      )

    response = json_response(conn, 422)
    assert response["error"]["code"] == "invalid_request"

    assert response["error"]["details"]["recovery_ref"] ==
             "must be a non-empty string"
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
          "api-write-#{suffix}-#{System.unique_integer([:positive])}-#{Ecto.UUID.generate()}",
        user_agent: "api-chat-write-controller-test",
        ip: "127.0.0.1"
      },
      remember_device?: true
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
