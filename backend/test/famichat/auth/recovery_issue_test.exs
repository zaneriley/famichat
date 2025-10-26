defmodule Famichat.Auth.Recovery.IssueTest do
  use Famichat.DataCase, async: true

  alias Famichat.Auth.Recovery
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.{RedactionHelpers, TelemetryHelpers}

  @issue_event [:famichat, :auth, :recovery, :issue]

  test "household admins and self can issue recovery; cross-household rejected" do
    family = ChatFixtures.family_fixture()
    other_family = ChatFixtures.family_fixture()

    admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
    member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    outsider =
      ChatFixtures.user_fixture(%{family_id: other_family.id, role: :member})

    result_ref = make_ref()

    events =
      TelemetryHelpers.capture([@issue_event], fn ->
        result = Recovery.issue_recovery(admin.id, member.id)
        send(self(), {result_ref, result})
      end)

    assert_receive {^result_ref, {:ok, token, record}}
    assert is_binary(token)
    assert record.user_id == admin.id

    assert [%{metadata: metadata}] = events
    assert metadata[:admin_id] == admin.id
    assert metadata[:user_id] == member.id
    RedactionHelpers.pii_free!(metadata)

    assert {:error, :forbidden} = Recovery.issue_recovery(admin.id, outsider.id)

    assert {:ok, _, _} = Recovery.issue_recovery(member.id, member.id)
  end
end
