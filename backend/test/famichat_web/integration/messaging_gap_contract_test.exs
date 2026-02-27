defmodule FamichatWeb.MessagingGapContractTest do
  use FamichatWeb.ChannelCase, async: false

  import Phoenix.ConnTest,
    only: [build_conn: 0, get: 2, json_response: 2, post: 3]

  import Plug.Conn, only: [put_req_header: 3]

  alias Famichat.Auth.Sessions
  alias Famichat.Chat
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.MLS.RecoveryGateAdapter
  alias FamichatWeb.{MessageChannel, UserSocket}

  @endpoint FamichatWeb.Endpoint

  setup do
    previous_trap_exit = Process.flag(:trap_exit, true)

    on_exit(fn ->
      Process.flag(:trap_exit, previous_trap_exit)
    end)

    previous_adapter = Application.get_env(:famichat, :mls_adapter)
    previous_enforcement = Application.get_env(:famichat, :mls_enforcement)

    Application.put_env(:famichat, :mls_adapter, RecoveryGateAdapter)
    Application.put_env(:famichat, :mls_enforcement, true)

    on_exit(fn ->
      restore_env(:mls_adapter, previous_adapter)
      restore_env(:mls_enforcement, previous_enforcement)
    end)

    family = ChatFixtures.family_fixture()

    sender =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "gap_sender_#{System.unique_integer([:positive])}"
      })

    receiver =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "gap_receiver_#{System.unique_integer([:positive])}"
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

    recovery_ref = "gap-recovery-#{System.unique_integer([:positive])}"

    assert {:ok, recovery} =
             Chat.recover_conversation_security_state(
               conversation.id,
               recovery_ref,
               %{
                 rejoin_token:
                   "gap-rejoin-#{System.unique_integer([:positive])}"
               }
             )

    assert recovery.status == :completed

    {:ok,
     %{
       sender_conn: authed_conn(sender_session.access_token),
       receiver_conn: authed_conn(receiver_session.access_token),
       receiver_token: receiver_session.access_token,
       conversation: conversation,
       topic: "message:direct:#{conversation.id}"
     }}
  end

  test "late joiner can recover the first missed message via read API and continue live",
       %{
         sender_conn: sender_conn,
         receiver_conn: receiver_conn,
         receiver_token: receiver_token,
         conversation: conversation,
         topic: topic
       } do
    first = "message-before-join"
    second = "message-after-join"

    first_response = send_broadcast(sender_conn, conversation.id, first)
    first_id = first_response["data"]["payload"]["message_id"]
    assert is_binary(first_id)

    {:ok, receiver_socket} = connect(UserSocket, %{"token" => receiver_token})

    {:ok, _reply, _channel} =
      subscribe_and_join(receiver_socket, MessageChannel, topic)

    history_after_join = fetch_history(receiver_conn, conversation.id)
    assert Enum.any?(history_after_join, &(&1["id"] == first_id))
    assert Enum.any?(history_after_join, &(&1["content"] == first))

    second_response = send_broadcast(sender_conn, conversation.id, second)
    expected_payload = second_response["data"]["payload"]
    assert_push "new_msg", ^expected_payload

    history_after_second = fetch_history(receiver_conn, conversation.id)
    bodies = Enum.map(history_after_second, & &1["content"])
    assert bodies == [first, second]
  end

  test "reconnected device catches offline gap via read API and keeps receiving live",
       %{
         sender_conn: sender_conn,
         receiver_conn: receiver_conn,
         receiver_token: receiver_token,
         conversation: conversation,
         topic: topic
       } do
    online = "online-first"
    offline_gap = "sent-while-offline"
    resumed = "after-reconnect"

    {:ok, receiver_socket_1} = connect(UserSocket, %{"token" => receiver_token})

    {:ok, _reply, channel_1} =
      subscribe_and_join(receiver_socket_1, MessageChannel, topic)

    online_response = send_broadcast(sender_conn, conversation.id, online)
    online_payload = online_response["data"]["payload"]
    assert_push "new_msg", ^online_payload

    ref = leave(channel_1)
    assert_reply ref, :ok

    gap_response = send_broadcast(sender_conn, conversation.id, offline_gap)
    gap_id = gap_response["data"]["payload"]["message_id"]
    assert is_binary(gap_id)

    {:ok, receiver_socket_2} = connect(UserSocket, %{"token" => receiver_token})

    {:ok, _reply, _channel_2} =
      subscribe_and_join(receiver_socket_2, MessageChannel, topic)

    history_after_reconnect = fetch_history(receiver_conn, conversation.id)
    assert Enum.any?(history_after_reconnect, &(&1["content"] == online))
    assert Enum.any?(history_after_reconnect, &(&1["id"] == gap_id))
    assert Enum.any?(history_after_reconnect, &(&1["content"] == offline_gap))

    resumed_response = send_broadcast(sender_conn, conversation.id, resumed)
    resumed_payload = resumed_response["data"]["payload"]
    assert_push "new_msg", ^resumed_payload

    final_history = fetch_history(receiver_conn, conversation.id)
    final_bodies = Enum.map(final_history, & &1["content"])
    assert final_bodies == [online, offline_gap, resumed]
  end

  defp send_broadcast(conn, conversation_id, body) do
    conn =
      post(conn, "/api/v1/conversations/#{conversation_id}/messages", %{
        "body" => body
      })

    response = json_response(conn, 201)
    assert response["data"]["payload"]["body"] == body
    response
  end

  defp fetch_history(conn, conversation_id) do
    conn
    |> get("/api/v1/conversations/#{conversation_id}/messages")
    |> json_response(200)
    |> Map.fetch!("data")
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
          "gap-contract-#{suffix}-#{System.unique_integer([:positive])}-#{Ecto.UUID.generate()}",
        user_agent: "messaging-gap-contract-test",
        ip: "127.0.0.1"
      },
      remember_device?: true
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
