defmodule FamichatWeb.RevokedDeviceSecurityFlowTest do
  use FamichatWeb.ChannelCase, async: true

  import Phoenix.ConnTest,
    only: [build_conn: 0, json_response: 2, post: 3]

  import Plug.Conn, only: [put_req_header: 3]

  alias Famichat.Auth.Sessions
  alias Famichat.ChatFixtures
  alias FamichatWeb.{MessageChannel, UserSocket}

  @endpoint FamichatWeb.Endpoint

  test "revoked subscribed device receives explicit security state while healthy subscribers still receive new_msg" do
    family = ChatFixtures.family_fixture()

    sender =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "revoked_flow_sender_#{System.unique_integer([:positive])}"
      })

    receiver =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "revoked_flow_receiver_#{System.unique_integer([:positive])}"
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

    {:ok, sender_socket} =
      connect(UserSocket, %{"token" => sender_session.access_token})

    {:ok, receiver_socket} =
      connect(UserSocket, %{"token" => receiver_session.access_token})

    topic = "message:direct:#{conversation.id}"

    {:ok, _reply, _sender_channel} =
      subscribe_and_join(sender_socket, MessageChannel, topic)

    {:ok, _reply, _receiver_channel} =
      subscribe_and_join(receiver_socket, MessageChannel, topic)

    assert {:ok, :revoked} =
             Sessions.revoke_device(sender.id, sender_session.device_id)

    conn =
      post(
        authed_conn(receiver_session.access_token),
        "/api/v1/conversations/#{conversation.id}/messages",
        %{
          "body" => "revoked-visibility-check"
        }
      )

    response = json_response(conn, 201)
    assert response["data"]["event_name"] == "new_msg"

    assert_push "security_state", payload
    assert (payload[:reason] || payload["reason"]) == "device_revoked"
    assert (payload[:action] || payload["action"]) == "reauth_required"

    assert_push "new_msg", delivered_payload
    assert delivered_payload["body"] == "revoked-visibility-check"
    assert delivered_payload["user_id"] == receiver.id
  end

  defp authed_conn(access_token) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{access_token}")
  end

  defp start_session(user, suffix) do
    Sessions.start_session(
      user,
      %{
        id: "revoked-flow-#{suffix}-#{System.unique_integer([:positive])}",
        user_agent: "revoked-device-security-flow-test",
        ip: "127.0.0.1"
      },
      remember_device?: true
    )
  end
end
