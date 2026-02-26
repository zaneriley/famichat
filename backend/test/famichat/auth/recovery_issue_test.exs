defmodule Famichat.Auth.Recovery.IssueTest do
  use Famichat.DataCase, async: true

  alias Famichat.Auth.Recovery
  alias Famichat.Auth.Runtime.AuditLog
  alias Famichat.ChatFixtures
  alias Famichat.Repo
  alias Famichat.TestSupport.{RedactionHelpers, TelemetryHelpers}

  @issue_event [:famichat, :auth, :recovery, :issue]

  describe "issue_recovery/3" do
    test "defaults to target_user scope and logs audit + telemetry" do
      family = ChatFixtures.family_fixture()
      admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
      member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

      events =
        TelemetryHelpers.capture([@issue_event], fn ->
          assert {:ok, token, record} =
                   Recovery.issue_recovery(admin.id, member.id)

          assert is_binary(token)
          assert record.user_id == admin.id
          assert record.payload["scope"] == "target_user"
          refute Map.has_key?(record.payload, "household_id")
        end)

      assert [%{metadata: metadata}] = events
      assert metadata[:scope] == :target_user
      assert metadata[:subject_id] == member.id
      assert metadata[:admin_id] == admin.id
      assert metadata[:household_id] == nil
      RedactionHelpers.pii_free!(metadata)

      [audit] = Repo.all(AuditLog)
      assert audit.event == "recovery.issue"
      assert audit.actor_id == admin.id
      assert audit.subject_id == member.id
      assert audit.scope == "target_user"
      assert audit.household_id == nil
    end

    test "issues household scoped recovery when a single household matches" do
      family = ChatFixtures.family_fixture()
      admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
      member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

      events =
        TelemetryHelpers.capture([@issue_event], fn ->
          assert {:ok, _token, record} =
                   Recovery.issue_recovery(admin.id, member.id,
                     scope: :household
                   )

          assert record.payload["scope"] == "household"
          assert record.payload["household_id"] == family.id
        end)

      assert [%{metadata: metadata}] = events
      assert metadata[:scope] == :household
      assert metadata[:household_id] == family.id
      RedactionHelpers.pii_free!(metadata)

      [audit] = Repo.all(AuditLog)
      assert audit.scope == "household"
      assert audit.household_id == family.id
    end

    test "rejects household scope when multiple shared households exist" do
      family_one = ChatFixtures.family_fixture()
      family_two = ChatFixtures.family_fixture()

      admin =
        ChatFixtures.user_fixture(%{family_id: family_one.id, role: :admin})

      member =
        ChatFixtures.user_fixture(%{family_id: family_one.id, role: :member})

      ChatFixtures.membership_fixture(admin, family_two, :admin)
      ChatFixtures.membership_fixture(member, family_two, :member)

      assert {:error, :ambiguous_household} =
               Recovery.issue_recovery(admin.id, member.id, scope: :household)
    end

    test "rejects household scope without shared membership" do
      family = ChatFixtures.family_fixture()
      other_family = ChatFixtures.family_fixture()

      admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})

      outsider =
        ChatFixtures.user_fixture(%{family_id: other_family.id, role: :member})

      assert {:error, :forbidden} =
               Recovery.issue_recovery(admin.id, outsider.id, scope: :household)
    end

    test "rejects unsupported scopes" do
      family = ChatFixtures.family_fixture()
      admin = ChatFixtures.user_fixture(%{family_id: family.id, role: :admin})
      member = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

      assert {:error, :unsupported_scope} =
               Recovery.issue_recovery(admin.id, member.id, scope: :global)
    end
  end
end
