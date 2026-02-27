defmodule FamichatWeb.RecoveryRejoinSecurityFlowTest do
  use FamichatWeb.ChannelCase, async: false

  import Phoenix.ConnTest,
    only: [build_conn: 0, json_response: 2, post: 3]

  import Plug.Conn, only: [put_req_header: 3]

  alias Famichat.Auth.Sessions
  alias Famichat.Chat.ConversationSecurityStateStore
  alias Famichat.Chat.Message
  alias Famichat.ChatFixtures
  alias Famichat.Repo
  alias Famichat.TestSupport.MLS.RecoveryGateAdapter
  alias FamichatWeb.{MessageChannel, UserSocket}

  @endpoint FamichatWeb.Endpoint

  setup do
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
        username: "recovery_flow_sender_#{System.unique_integer([:positive])}"
      })

    receiver =
      ChatFixtures.user_fixture(%{
        family_id: family.id,
        username: "recovery_flow_receiver_#{System.unique_integer([:positive])}"
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

    {:ok, receiver_socket} =
      connect(UserSocket, %{"token" => receiver_session.access_token})

    topic = "message:direct:#{conversation.id}"

    {:ok, _reply, _receiver_channel} =
      subscribe_and_join(receiver_socket, MessageChannel, topic)

    {:ok,
     %{
       sender: sender,
       sender_conn: authed_conn(sender_session.access_token),
       conversation: conversation,
       topic: topic
     }}
  end

  test "recovery-required failure is explicit and recovered device resumes protected messaging",
       %{
         sender: sender,
         sender_conn: sender_conn,
         conversation: conversation,
         topic: topic
       } do
    blocked_body = "blocked-before-recovery"

    blocked_conn =
      post(sender_conn, "/api/v1/conversations/#{conversation.id}/messages", %{
        "body" => blocked_body
      })

    blocked_response = json_response(blocked_conn, 409)
    assert blocked_response["error"]["code"] == "recovery_required"

    assert blocked_response["error"]["action"] ==
             "recover_conversation_security_state"

    assert blocked_response["error"]["details"]["reason"] ==
             "missing_group_state"

    refute_push "new_msg", _

    refute Repo.get_by(Message,
             conversation_id: conversation.id,
             sender_id: sender.id,
             content: blocked_body
           )

    recovery_ref = "recovery-ref-#{System.unique_integer([:positive])}"

    recovered =
      sender_conn
      |> post("/api/v1/conversations/#{conversation.id}/security/recover", %{
        "recovery_ref" => recovery_ref,
        "rejoin_token" => "rejoin-token-#{System.unique_integer([:positive])}"
      })
      |> json_response(200)

    assert recovered["data"]["idempotent"] == false
    assert recovered["data"]["conversation_id"] == conversation.id

    replayed =
      sender_conn
      |> post("/api/v1/conversations/#{conversation.id}/security/recover", %{
        "recovery_ref" => recovery_ref,
        "rejoin_token" => "rejoin-token-ignored"
      })
      |> json_response(200)

    assert replayed["data"]["idempotent"] == true
    assert replayed["data"]["recovery_id"] == recovered["data"]["recovery_id"]

    recovered_body = "delivered-after-recovery"

    recovered_conn =
      post(sender_conn, "/api/v1/conversations/#{conversation.id}/messages", %{
        "body" => recovered_body
      })

    recovered_response = json_response(recovered_conn, 201)
    assert recovered_response["data"]["topic"] == topic
    assert recovered_response["data"]["event_name"] == "new_msg"
    assert recovered_response["data"]["payload"]["body"] == recovered_body
    assert recovered_response["data"]["payload"]["user_id"] == sender.id

    expected_payload = recovered_response["data"]["payload"]
    assert_push "new_msg", ^expected_payload

    assert Repo.get_by(Message,
             conversation_id: conversation.id,
             sender_id: sender.id,
             content: recovered_body
           )
  end

  test "pending commit blocks send with explicit conversation security state",
       %{
         sender: sender,
         sender_conn: sender_conn,
         conversation: conversation
       } do
    assert {:ok, _persisted} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{
                 protocol: "mls",
                 state: snapshot_payload("pending-state"),
                 epoch: 2,
                 pending_commit: %{
                   "operation" => "mls_commit",
                   "staged_epoch" => 3
                 }
               },
               nil
             )

    blocked_body = "blocked-by-pending-commit"

    blocked_conn =
      post(sender_conn, "/api/v1/conversations/#{conversation.id}/messages", %{
        "body" => blocked_body
      })

    blocked_response = json_response(blocked_conn, 409)
    assert blocked_response["error"]["code"] == "conversation_security_blocked"
    assert blocked_response["error"]["action"] == "wait_for_pending_commit"
    assert blocked_response["error"]["details"]["code"] == "pending_proposals"
    assert blocked_response["error"]["details"]["reason"] == "pending_proposals"

    refute_push "new_msg", _

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
        id: "recovery-flow-#{suffix}-#{System.unique_integer([:positive])}",
        user_agent: "recovery-rejoin-security-flow-test",
        ip: "127.0.0.1"
      },
      remember_device?: true
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)

  defp snapshot_payload(token) do
    %{
      "session_sender_storage" => Base.encode64("sender-storage:#{token}"),
      "session_recipient_storage" =>
        Base.encode64("recipient-storage:#{token}"),
      "session_sender_signer" => Base.encode64("sender-signer:#{token}"),
      "session_recipient_signer" => Base.encode64("recipient-signer:#{token}"),
      "session_cache" => ""
    }
  end
end
