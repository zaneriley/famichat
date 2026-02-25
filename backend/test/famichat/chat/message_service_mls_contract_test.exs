defmodule Famichat.Chat.MessageServiceMLSContractTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.{ConversationService, Message, MessageService}
  alias Famichat.Repo
  import Famichat.ChatFixtures

  defmodule EncryptionFailAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    def nif_version, do: {:ok, %{}}
    def nif_health, do: {:ok, %{}}
    def create_key_package(_params), do: {:ok, %{}}
    def create_group(_params), do: {:ok, %{}}
    def join_from_welcome(_params), do: {:ok, %{}}
    def process_incoming(_params), do: {:ok, %{plaintext: "ok"}}
    def commit_to_pending(_params), do: {:ok, %{}}
    def mls_commit(_params), do: {:ok, %{}}
    def mls_update(_params), do: {:ok, %{}}
    def mls_add(_params), do: {:ok, %{}}
    def mls_remove(_params), do: {:ok, %{}}
    def merge_staged_commit(_params), do: {:ok, %{}}
    def clear_pending_commit(_params), do: {:ok, %{}}
    def export_group_info(_params), do: {:ok, %{}}
    def export_ratchet_tree(_params), do: {:ok, %{}}

    def create_application_message(_params) do
      {:error, :crypto_failure,
       %{reason: :encrypt_failed, plaintext: "must-not-leak"}}
    end
  end

  defmodule MissingCiphertextAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    def nif_version, do: {:ok, %{}}
    def nif_health, do: {:ok, %{}}
    def create_key_package(_params), do: {:ok, %{}}
    def create_group(_params), do: {:ok, %{}}
    def join_from_welcome(_params), do: {:ok, %{}}
    def process_incoming(_params), do: {:ok, %{plaintext: "ok"}}
    def commit_to_pending(_params), do: {:ok, %{}}
    def mls_commit(_params), do: {:ok, %{}}
    def mls_update(_params), do: {:ok, %{}}
    def mls_add(_params), do: {:ok, %{}}
    def mls_remove(_params), do: {:ok, %{}}
    def merge_staged_commit(_params), do: {:ok, %{}}
    def clear_pending_commit(_params), do: {:ok, %{}}
    def export_group_info(_params), do: {:ok, %{}}
    def export_ratchet_tree(_params), do: {:ok, %{}}

    def create_application_message(_params), do: {:ok, %{epoch: 1}}
  end

  defmodule DecryptionFailAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    def nif_version, do: {:ok, %{}}
    def nif_health, do: {:ok, %{}}
    def create_key_package(_params), do: {:ok, %{}}
    def create_group(_params), do: {:ok, %{}}
    def join_from_welcome(_params), do: {:ok, %{}}
    def commit_to_pending(_params), do: {:ok, %{}}
    def mls_commit(_params), do: {:ok, %{}}
    def mls_update(_params), do: {:ok, %{}}
    def mls_add(_params), do: {:ok, %{}}
    def mls_remove(_params), do: {:ok, %{}}
    def merge_staged_commit(_params), do: {:ok, %{}}
    def clear_pending_commit(_params), do: {:ok, %{}}
    def export_group_info(_params), do: {:ok, %{}}
    def export_ratchet_tree(_params), do: {:ok, %{}}

    def create_application_message(params) do
      body = Map.get(params, :body) || Map.get(params, "body") || ""
      {:ok, %{ciphertext: "ciphertext:#{body}"}}
    end

    def process_incoming(_params) do
      {:error, :crypto_failure,
       %{reason: :decrypt_failed, ciphertext: "must-not-leak"}}
    end
  end

  defmodule TelemetryLeakAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    def nif_version, do: {:ok, %{}}
    def nif_health, do: {:ok, %{}}
    def create_key_package(_params), do: {:ok, %{}}
    def create_group(_params), do: {:ok, %{}}
    def join_from_welcome(_params), do: {:ok, %{}}
    def process_incoming(_params), do: {:ok, %{plaintext: "ok"}}
    def commit_to_pending(_params), do: {:ok, %{}}
    def mls_commit(_params), do: {:ok, %{}}
    def mls_update(_params), do: {:ok, %{}}
    def mls_add(_params), do: {:ok, %{}}
    def mls_remove(_params), do: {:ok, %{}}
    def merge_staged_commit(_params), do: {:ok, %{}}
    def clear_pending_commit(_params), do: {:ok, %{}}
    def export_group_info(_params), do: {:ok, %{}}
    def export_ratchet_tree(_params), do: {:ok, %{}}

    def create_application_message(_params) do
      {:error, :crypto_failure,
       %{
         reason: %{kind: :nested},
         nested: %{plaintext: "must-not-leak", ok: "keep"},
         events: [%{"private_key" => "must-not-leak", "note" => "keep"}]
       }}
    end
  end

  setup do
    previous_adapter = Application.get_env(:famichat, :mls_adapter)
    previous_enforcement = Application.get_env(:famichat, :mls_enforcement)

    Application.put_env(
      :famichat,
      :mls_adapter,
      Famichat.TestSupport.MLS.FakeAdapter
    )

    Application.put_env(:famichat, :mls_enforcement, true)

    on_exit(fn ->
      restore_env(:mls_adapter, previous_adapter)
      restore_env(:mls_enforcement, previous_enforcement)
    end)

    conversation = conversation_fixture(%{conversation_type: :direct})
    [participant | _] = ConversationService.list_members(conversation)

    {:ok, conversation: conversation, sender: participant}
  end

  test "send_message fails closed when MLS encryption fails and persists nothing",
       %{conversation: conversation, sender: sender} do
    Application.put_env(:famichat, :mls_adapter, EncryptionFailAdapter)

    before_count = Repo.aggregate(Message, :count, :id)

    assert {:error, {:mls_encryption_failed, :crypto_failure, details}} =
             MessageService.send_message(
               message_params(sender.id, conversation.id)
             )

    assert details[:reason] == :encrypt_failed
    refute Map.has_key?(details, :plaintext)
    assert Repo.aggregate(Message, :count, :id) == before_count
  end

  test "send_message does not emit sent telemetry when encryption fails",
       %{conversation: conversation, sender: sender} do
    Application.put_env(:famichat, :mls_adapter, EncryptionFailAdapter)

    handler_name = "mls-send-fail-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_name,
        [:famichat, :message, :sent],
        fn event_name, measurements, metadata, _ ->
          send(self(), {:sent_event, event_name, measurements, metadata})
        end,
        nil
      )

    on_exit(fn ->
      :telemetry.detach(handler_name)
    end)

    assert {:error, {:mls_encryption_failed, :crypto_failure, _details}} =
             MessageService.send_message(
               message_params(sender.id, conversation.id)
             )

    refute_receive {:sent_event, _, _, _}, 200
  end

  test "send_message stores ciphertext (not plaintext) when MLS is required",
       %{conversation: conversation, sender: sender} do
    assert {:ok, message} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "plaintext body")
             )

    reloaded = Repo.get!(Message, message.id)
    assert reloaded.content == "ciphertext:plaintext body"
    refute reloaded.content == "plaintext body"
    assert get_in(reloaded.metadata, ["mls", "encrypted"]) == true
  end

  test "send_message fails when adapter returns success without ciphertext",
       %{conversation: conversation, sender: sender} do
    Application.put_env(:famichat, :mls_adapter, MissingCiphertextAdapter)
    before_count = Repo.aggregate(Message, :count, :id)

    assert {:error, {:mls_encryption_failed, :crypto_failure, details}} =
             MessageService.send_message(
               message_params(sender.id, conversation.id)
             )

    assert details[:reason] == :missing_ciphertext
    assert Repo.aggregate(Message, :count, :id) == before_count
  end

  test "get_conversation_messages surfaces decryption failure with redacted details",
       %{conversation: conversation, sender: sender} do
    assert {:ok, _message} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "secret payload")
             )

    Application.put_env(:famichat, :mls_adapter, DecryptionFailAdapter)

    assert {:error, {:mls_decryption_failed, :crypto_failure, details}} =
             MessageService.get_conversation_messages(conversation.id)

    assert details[:reason] == :decrypt_failed
    refute Map.has_key?(details, :ciphertext)
    refute Map.has_key?(details, :plaintext)
    refute Map.has_key?(details, :key_material)
  end

  test "mls failure telemetry stays scalar and excludes nested sensitive data",
       %{conversation: conversation, sender: sender} do
    Application.put_env(:famichat, :mls_adapter, TelemetryLeakAdapter)

    handler_name =
      "mls-failure-sanitization-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_name,
        [:famichat, :message, :mls_failure],
        fn _event_name, _measurements, metadata, _ ->
          send(self(), {:mls_failure_event, metadata})
        end,
        nil
      )

    on_exit(fn ->
      :telemetry.detach(handler_name)
    end)

    assert {:error, {:mls_encryption_failed, :crypto_failure, details}} =
             MessageService.send_message(
               message_params(sender.id, conversation.id)
             )

    assert details[:nested][:ok] == "keep"
    assert Enum.at(details[:events], 0)["note"] == "keep"
    refute Map.has_key?(details[:nested], :plaintext)
    refute Map.has_key?(Enum.at(details[:events], 0), "private_key")

    assert_receive {:mls_failure_event, metadata}, 500

    assert metadata.action == :encrypt
    assert metadata.error_code == :crypto_failure
    assert metadata.conversation_id == conversation.id
    refute Map.has_key?(metadata, :reason)
    refute Map.has_key?(metadata, :nested)
    refute Map.has_key?(metadata, :events)
  end

  defp message_params(sender_id, conversation_id, content \\ "hello") do
    %{
      sender_id: sender_id,
      conversation_id: conversation_id,
      content: content
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
