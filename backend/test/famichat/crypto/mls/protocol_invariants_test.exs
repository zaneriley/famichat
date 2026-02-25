defmodule Famichat.Crypto.MLS.ProtocolInvariantsTest do
  use ExUnit.Case, async: false

  alias Famichat.Crypto.MLS
  alias Famichat.TestSupport.MLS.FakeAdapter

  setup do
    previous_adapter = Application.get_env(:famichat, :mls_adapter)
    Application.put_env(:famichat, :mls_adapter, FakeAdapter)

    on_exit(fn ->
      restore_env(:mls_adapter, previous_adapter)
    end)

    :ok
  end

  test "create_application_message fails closed while pending proposals exist" do
    assert {:error, :pending_proposals, details} =
             MLS.create_application_message(%{
               group_id: "group-1",
               body: "hello",
               pending_proposals: true
             })

    assert details[:operation] == :create_application_message
  end

  test "merge_staged_commit rejects unvalidated staged commits" do
    assert {:error, :commit_rejected, details} =
             MLS.merge_staged_commit(%{
               group_id: "group-1",
               staged_commit_validated: false
             })

    assert details[:reason] == :staged_commit_not_validated
  end

  test "welcome cannot be processed while a commit is pending merge" do
    assert {:error, :commit_rejected, details} =
             MLS.process_incoming(%{
               group_id: "group-1",
               pending_commit: true,
               incoming_type: :welcome
             })

    assert details[:reason] == :welcome_before_commit_merge
  end

  test "clearing pending commit keeps group state usable for application messages" do
    assert {:ok, _} =
             MLS.clear_pending_commit(%{
               group_id: "group-1"
             })

    assert {:ok, payload} =
             MLS.create_application_message(%{
               group_id: "group-1",
               body: "usable after clear",
               pending_proposals: false
             })

    assert payload[:ciphertext] == "ciphertext:usable after clear"
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
