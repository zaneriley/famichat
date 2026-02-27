defmodule Famichat.Auth.Recovery.RedeemTest do
  use Famichat.DataCase, async: false

  import Ecto.Query

  alias Famichat.Accounts.{User, UserDevice}
  alias Famichat.Auth.{Recovery, Sessions}
  alias Famichat.Auth.Runtime.AuditLog
  alias Famichat.Chat.ConversationSecurityRevocation
  alias Famichat.ChatFixtures
  alias Famichat.Repo
  alias Famichat.TestSupport.{RedactionHelpers, TelemetryHelpers}

  @redeem_event [:famichat, :auth, :recovery, :redeem]

  test "redeeming target_user scope revokes only the target and logs audit" do
    family = ChatFixtures.family_fixture()
    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})
    peer = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    conversation =
      ChatFixtures.conversation_fixture(%{
        conversation_type: :direct,
        family: family,
        user1: member,
        user2: peer
      })

    session = start_session(member)

    {:ok, recovery_token, _record} =
      Recovery.issue_recovery(admin.id, member.id)

    events =
      TelemetryHelpers.capture([@redeem_event], fn ->
        assert {:ok, updated_member} = Recovery.redeem_recovery(recovery_token)
        assert updated_member.id == member.id
        refute is_nil(updated_member.enrollment_required_since)
      end)

    assert [%{metadata: metadata}] = events
    assert metadata[:scope] == :target_user
    assert metadata[:subject_ids] == [member.id]
    RedactionHelpers.pii_free!(metadata)

    device =
      Repo.get_by!(UserDevice,
        user_id: member.id,
        device_id: session.device_id
      )

    refute is_nil(device.revoked_at)

    assert {:error, :revoked} =
             Sessions.refresh_session(session.device_id, session.refresh_token)

    assert_pending_user_revocation(conversation.id, member.id)

    member_id = member.id

    assert [%AuditLog{event: "recovery.redeem", subject_id: ^member_id}] =
             Repo.all(from a in AuditLog, where: a.event == "recovery.redeem")

    # second redeem attempt returns used without telemetry
    second =
      TelemetryHelpers.capture([@redeem_event], fn ->
        assert {:error, :used} = Recovery.redeem_recovery(recovery_token)
      end)

    assert second == []
  end

  test "redeeming household scope revokes all members and audits each subject" do
    family = ChatFixtures.family_fixture()
    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    member_a = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})
    member_b = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    conversation_a =
      ChatFixtures.conversation_fixture(%{
        conversation_type: :direct,
        family: family,
        user1: admin,
        user2: member_a
      })

    conversation_b =
      ChatFixtures.conversation_fixture(%{
        conversation_type: :direct,
        family: family,
        user1: admin,
        user2: member_b
      })

    session_a = start_session(member_a)
    session_b = start_session(member_b)

    {:ok, recovery_token, _record} =
      Recovery.issue_recovery(admin.id, member_a.id, scope: :household)

    events =
      TelemetryHelpers.capture([@redeem_event], fn ->
        assert {:ok, updated_member} = Recovery.redeem_recovery(recovery_token)
        assert updated_member.id == member_a.id
      end)

    assert [%{metadata: metadata}] = events
    assert metadata[:scope] == :household
    expected_ids = Enum.sort([admin.id, member_a.id, member_b.id])
    assert Enum.sort(metadata[:subject_ids]) == expected_ids
    assert metadata[:household_id] == family.id
    RedactionHelpers.pii_free!(metadata)

    Enum.each(
      [
        {member_a, session_a},
        {member_b, session_b}
      ],
      fn {member, session} ->
        device =
          Repo.get_by!(UserDevice,
            user_id: member.id,
            device_id: session.device_id
          )

        refute is_nil(device.revoked_at)

        assert {:error, :revoked} =
                 Sessions.refresh_session(
                   session.device_id,
                   session.refresh_token
                 )

        refreshed_user = Repo.get!(User, member.id)
        refute is_nil(refreshed_user.enrollment_required_since)
      end
    )

    admin_user = Repo.get!(User, admin.id)
    refute is_nil(admin_user.enrollment_required_since)

    redeem_audits =
      Repo.all(
        from a in AuditLog,
          where: a.event == "recovery.redeem",
          order_by: a.subject_id
      )

    assert Enum.map(redeem_audits, & &1.subject_id) |> Enum.sort() ==
             expected_ids

    Enum.each(redeem_audits, fn audit ->
      assert audit.household_id == family.id
      assert audit.scope == "household"
    end)

    assert_pending_user_revocation(conversation_a.id, admin.id)
    assert_pending_user_revocation(conversation_a.id, member_a.id)
    assert_pending_user_revocation(conversation_b.id, admin.id)
    assert_pending_user_revocation(conversation_b.id, member_b.id)
  end

  defp start_session(user) do
    device_info = %{
      id: "device-#{System.unique_integer([:positive])}",
      user_agent: "RecoveryRedeemTest",
      ip: "127.0.0.1"
    }

    {:ok, session} =
      Sessions.start_session(user, device_info, remember_device?: true)

    session
  end

  defp assert_pending_user_revocation(conversation_id, user_id) do
    query =
      from r in ConversationSecurityRevocation,
        where:
          r.conversation_id == ^conversation_id and
            r.subject_type == :user and r.subject_id == ^user_id and
            r.status == :pending_commit

    assert Repo.aggregate(query, :count, :id) == 1
  end
end
