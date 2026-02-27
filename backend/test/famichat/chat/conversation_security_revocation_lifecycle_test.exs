defmodule Famichat.Chat.ConversationSecurityRevocationLifecycleTest do
  use Famichat.DataCase, async: false

  alias Famichat.Auth.Sessions
  alias Famichat.Chat
  alias Famichat.Chat.ConversationSecurityRevocationLifecycle
  alias Famichat.Chat.ConversationSecurityRevocationStore
  import Famichat.ChatFixtures

  test "stage_user_revocation stages pending-commit entries across user conversations and is idempotent" do
    %{user: user, conversation_ids: conversation_ids} =
      user_with_two_conversations()

    assert {:ok, first} =
             Chat.stage_user_revocation(user.id, "user-revocation-1", %{
               revocation_reason: "account_recovery",
               actor_id: user.id
             })

    assert first.conversation_count == 2
    assert first.started_count == 2
    assert first.existing_count == 0
    assert first.pending_commit_count == 2

    assert {:ok, second} =
             Chat.stage_user_revocation(user.id, "user-revocation-1", %{
               revocation_reason: "account_recovery",
               actor_id: user.id
             })

    assert second.conversation_count == 2
    assert second.started_count == 0
    assert second.existing_count == 2
    assert second.pending_commit_count == 2

    assert_pending_commit_rows(
      conversation_ids,
      "user-revocation-1",
      :user,
      user.id
    )
  end

  test "stage_client_revocation resolves user by client id and stages pending-commit entries" do
    %{user: user, conversation_ids: conversation_ids} =
      user_with_two_conversations()

    client_id = start_client_session!(user)

    assert {:ok, result} =
             Chat.stage_client_revocation(client_id, "client-revocation-1", %{
               revocation_reason: "device_compromised",
               actor_id: user.id
             })

    assert result.conversation_count == 2
    assert result.started_count == 2
    assert result.pending_commit_count == 2

    assert_pending_commit_rows(
      conversation_ids,
      "client-revocation-1",
      :client,
      client_id
    )
  end

  test "stage_client_revocation fails for unknown client id" do
    assert {:error, :not_found, details} =
             Chat.stage_client_revocation(
               "missing-client",
               "client-revocation-2"
             )

    assert details[:reason] == :client_not_found
  end

  test "stage_user_revocation rejects subject mismatch reuse for the same revocation_ref" do
    %{user: user} = user_with_two_conversations()
    client_id = start_client_session!(user)

    assert {:ok, _first} =
             Chat.stage_user_revocation(user.id, "shared-revocation-ref", %{
               revocation_reason: "account_recovery"
             })

    assert {:error, :idempotency_conflict, details} =
             Chat.stage_client_revocation(
               client_id,
               "shared-revocation-ref",
               %{revocation_reason: "device_compromised"}
             )

    assert details[:reason] == :revocation_ref_subject_mismatch
  end

  test "concurrent stage_user_revocation calls converge with no duplicate records" do
    %{user: user, conversation_ids: conversation_ids} =
      user_with_two_conversations()

    results =
      1..8
      |> Task.async_stream(
        fn _ ->
          Chat.stage_user_revocation(user.id, "user-revocation-concurrent", %{
            revocation_reason: "account_recovery",
            actor_id: user.id
          })
        end,
        max_concurrency: 8,
        timeout: 5_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _}, &1))

    aggregate_started_count =
      Enum.reduce(results, 0, fn {:ok, payload}, acc ->
        acc + payload.started_count
      end)

    assert aggregate_started_count == length(conversation_ids)

    Enum.each(conversation_ids, fn conversation_id ->
      assert {:ok, revocations} =
               ConversationSecurityRevocationStore.list_for_conversation(
                 conversation_id
               )

      matching =
        Enum.filter(revocations, fn record ->
          record.revocation_ref == "user-revocation-concurrent" and
            record.subject_type == :user and record.subject_id == user.id and
            record.status == :pending_commit
        end)

      assert length(matching) == 1
    end)
  end

  test "complete_conversation_revocation seals a pending revocation and is idempotent" do
    %{user: user, conversation_ids: [conversation_id | _]} =
      user_with_two_conversations()

    assert {:ok, _staged} =
             Chat.stage_user_revocation(user.id, "user-revocation-complete", %{
               revocation_reason: "account_recovery",
               actor_id: user.id
             })

    assert {:ok, completed} =
             Chat.complete_conversation_revocation(
               conversation_id,
               "user-revocation-complete",
               %{committed_epoch: 7, proposal_ref: "proposal-complete-7"}
             )

    assert completed.status == :completed
    assert completed.committed_epoch == 7
    assert completed.proposal_ref == "proposal-complete-7"

    assert {:ok, idempotent} =
             Chat.complete_conversation_revocation(
               conversation_id,
               "user-revocation-complete"
             )

    assert idempotent.id == completed.id
    assert idempotent.status == :completed
    assert idempotent.committed_epoch == 7
  end

  test "complete_conversation_revocation requires committed_epoch for pending records" do
    %{user: user, conversation_ids: [conversation_id | _]} =
      user_with_two_conversations()

    assert {:ok, _staged} =
             Chat.stage_user_revocation(
               user.id,
               "user-revocation-missing-epoch"
             )

    assert {:error, :invalid_input, details} =
             Chat.complete_conversation_revocation(
               conversation_id,
               "user-revocation-missing-epoch"
             )

    assert details[:reason] == :missing_committed_epoch
  end

  test "fail_conversation_revocation marks pending revocation as failed and completion stays fail-closed" do
    %{user: user, conversation_ids: [conversation_id | _]} =
      user_with_two_conversations()

    assert {:ok, _staged} =
             Chat.stage_user_revocation(user.id, "user-revocation-failed", %{
               revocation_reason: "account_recovery",
               actor_id: user.id
             })

    assert {:ok, failed} =
             Chat.fail_conversation_revocation(
               conversation_id,
               "user-revocation-failed",
               %{
                 error_code: :proposal_generation_failed,
                 error_reason: "nif_timeout"
               }
             )

    assert failed.status == :failed
    assert failed.error_code == "proposal_generation_failed"
    assert failed.error_reason == "nif_timeout"

    assert {:ok, failed_idempotent} =
             Chat.fail_conversation_revocation(
               conversation_id,
               "user-revocation-failed"
             )

    assert failed_idempotent.id == failed.id
    assert failed_idempotent.status == :failed

    assert {:error, :revocation_failed, details} =
             Chat.complete_conversation_revocation(
               conversation_id,
               "user-revocation-failed",
               %{committed_epoch: 8}
             )

    assert details[:reason] == :revocation_previously_failed
  end

  test "fail_conversation_revocation requires error_code while revocation is pending" do
    %{user: user, conversation_ids: [conversation_id | _]} =
      user_with_two_conversations()

    assert {:ok, _staged} =
             Chat.stage_user_revocation(
               user.id,
               "user-revocation-missing-error"
             )

    assert {:error, :invalid_input, details} =
             Chat.fail_conversation_revocation(
               conversation_id,
               "user-revocation-missing-error"
             )

    assert details[:reason] == :missing_error_code
  end

  test "stage_user_revocation returns async_required when sync fanout limit is exceeded" do
    previous_limit =
      Application.get_env(
        :famichat,
        :conversation_security_revocation_sync_fanout_limit
      )

    Application.put_env(
      :famichat,
      :conversation_security_revocation_sync_fanout_limit,
      1
    )

    on_exit(fn ->
      restore_env(
        :conversation_security_revocation_sync_fanout_limit,
        previous_limit
      )
    end)

    %{user: user} = user_with_two_conversations()

    assert {:error, :async_required, details} =
             ConversationSecurityRevocationLifecycle.stage_user_revocation(
               user.id,
               "user-revocation-limit"
             )

    assert details[:reason] == :fanout_limit_exceeded
    assert details[:conversation_count] == 2
    assert details[:sync_fanout_limit] == 1
  end

  defp user_with_two_conversations do
    family = family_fixture()
    user = user_fixture(%{family: family})
    peer_1 = user_fixture(%{family: family})
    peer_2 = user_fixture(%{family: family})

    conversation_1 =
      conversation_fixture(%{
        conversation_type: :direct,
        family: family,
        user1: user,
        user2: peer_1
      })

    conversation_2 =
      conversation_fixture(%{
        conversation_type: :direct,
        family: family,
        user1: user,
        user2: peer_2
      })

    %{
      user: user,
      conversation_ids: Enum.sort([conversation_1.id, conversation_2.id])
    }
  end

  defp start_client_session!(user) do
    {:ok, session} =
      Sessions.start_session(
        user,
        %{
          id: "client-revocation-#{System.unique_integer([:positive])}",
          user_agent: "ConversationSecurityRevocationLifecycleTest",
          ip: "127.0.0.1"
        },
        remember_device?: true
      )

    session.device_id
  end

  defp assert_pending_commit_rows(
         conversation_ids,
         revocation_ref,
         subject_type,
         subject_id
       ) do
    Enum.each(conversation_ids, fn conversation_id ->
      assert {:ok, revocations} =
               ConversationSecurityRevocationStore.list_for_conversation(
                 conversation_id
               )

      assert Enum.any?(revocations, fn record ->
               record.revocation_ref == revocation_ref and
                 record.status == :pending_commit and
                 record.subject_type == subject_type and
                 record.subject_id == subject_id
             end)
    end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
