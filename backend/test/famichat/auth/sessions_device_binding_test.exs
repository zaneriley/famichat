defmodule Famichat.Auth.Sessions.DeviceBindingTest do
  use Famichat.DataCase, async: true

  import Ecto.Query

  alias Famichat.Auth.Sessions
  alias Famichat.Chat.ConversationSecurityRevocation
  alias Famichat.ChatFixtures
  alias Famichat.Repo

  test "refresh tokens are bound to their device and revoked tokens stay revoked" do
    family = ChatFixtures.family_fixture()

    user = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})
    peer = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    conversation =
      ChatFixtures.conversation_fixture(%{
        conversation_type: :direct,
        family: family,
        user1: user,
        user2: peer
      })

    session1 = start_session(user, "binding-device-1")

    assert {:error, :device_not_found} =
             Sessions.refresh_session("other-device", session1.refresh_token)

    session2 = start_session(user, "binding-device-2")
    tampered_token = tamper(session2.refresh_token)

    assert {:error, :revoked} =
             Sessions.refresh_session(session2.device_id, tampered_token)

    assert {:error, :revoked} =
             Sessions.refresh_session(
               session2.device_id,
               session2.refresh_token
             )

    session3 = start_session(user, "binding-device-3")

    assert {:ok, :revoked} = Sessions.revoke_device(user.id, session3.device_id)

    revocation_query =
      from r in ConversationSecurityRevocation,
        where:
          r.conversation_id == ^conversation.id and
            r.subject_type == :client and
            r.subject_id == ^session3.device_id

    assert Repo.aggregate(revocation_query, :count, :id) == 1

    assert {:ok, :revoked} = Sessions.revoke_device(user.id, session3.device_id)
    assert Repo.aggregate(revocation_query, :count, :id) == 1

    assert {:error, :invalid} =
             Sessions.verify_access_token(session3.access_token)

    assert {:error, :revoked} =
             Sessions.refresh_session(
               session3.device_id,
               session3.refresh_token
             )
  end

  test "revoke_all_for_user stages a single user revocation per conversation across retries" do
    family = ChatFixtures.family_fixture()
    user = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})
    peer = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    conversation =
      ChatFixtures.conversation_fixture(%{
        conversation_type: :direct,
        family: family,
        user1: user,
        user2: peer
      })

    _session = start_session(user, "binding-device-all")

    assert :ok = Sessions.revoke_all_for_user(user.id)
    assert :ok = Sessions.revoke_all_for_user(user.id)

    revocation_query =
      from r in ConversationSecurityRevocation,
        where:
          r.conversation_id == ^conversation.id and
            r.subject_type == :user and r.subject_id == ^user.id and
            r.status == :pending_commit

    assert Repo.aggregate(revocation_query, :count, :id) == 1
  end

  defp start_session(user, suffix) do
    {:ok, session} =
      Sessions.start_session(
        user,
        %{
          id: "#{suffix}-#{System.unique_integer([:positive])}",
          user_agent: "DeviceBindingTest",
          ip: "127.0.0.1"
        },
        remember_device?: true
      )

    session
  end

  defp tamper(<<first::binary-size(1), rest::binary>>) do
    flipped = if first == "a", do: "b", else: "a"
    flipped <> rest
  end

  defp tamper(token), do: token
end
