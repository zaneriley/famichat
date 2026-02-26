defmodule Famichat.Chat.MessageServiceMLSContractTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.{
    ConversationSecurityState,
    ConversationSecurityStateStore,
    ConversationService,
    Message,
    MessageService
  }

  alias Famichat.Crypto.MLS.Adapter.Nif
  alias Famichat.Repo
  import Famichat.ChatFixtures

  defmodule EncryptionFailAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    def nif_version, do: {:ok, %{}}
    def nif_health, do: {:ok, %{status: "ok"}}
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
    def nif_health, do: {:ok, %{status: "ok"}}
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

  defmodule MissingGroupStateAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    def nif_version, do: {:ok, %{}}
    def nif_health, do: {:ok, %{status: "ok"}}
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
      {:error, :storage_inconsistent,
       %{reason: :missing_group_state, operation: :create_application_message}}
    end
  end

  defmodule DecryptionFailAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    def nif_version, do: {:ok, %{}}
    def nif_health, do: {:ok, %{status: "ok"}}
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

  defmodule DegradedHealthAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    def nif_version, do: {:ok, %{adapter: "degraded"}}

    def nif_health,
      do: {:ok, %{status: "degraded", reason: "openmls_not_wired"}}

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
    def create_application_message(_params), do: raise("must not be called")
    def process_incoming(_params), do: raise("must not be called")
  end

  defmodule TelemetryLeakAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter

    def nif_version, do: {:ok, %{}}
    def nif_health, do: {:ok, %{status: "ok"}}
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

  defmodule StaleStateAdapter do
    @behaviour Famichat.Crypto.MLS.Adapter
    import Ecto.Query, warn: false

    alias Famichat.Chat.ConversationSecurityState
    alias Famichat.Repo

    def nif_version, do: {:ok, %{}}
    def nif_health, do: {:ok, %{status: "ok"}}
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

    def create_application_message(params) do
      group_id = Map.get(params, :group_id) || Map.get(params, "group_id")
      body = Map.get(params, :body) || Map.get(params, "body") || ""

      _ =
        Repo.update_all(
          from(s in ConversationSecurityState,
            where: s.conversation_id == ^group_id
          ),
          inc: [lock_version: 1]
        )

      {:ok,
       %{
         ciphertext: "ciphertext:#{body}",
         epoch: 2,
         session_sender_storage: Base.encode64("sender-storage"),
         session_recipient_storage: Base.encode64("recipient-storage"),
         session_sender_signer: Base.encode64("sender-signer"),
         session_recipient_signer: Base.encode64("recipient-signer"),
         session_cache: Base.encode64("cache")
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

  test "real NIF adapter encrypts at rest and keeps read path idempotent",
       %{conversation: conversation, sender: sender} do
    Application.put_env(:famichat, :mls_adapter, Nif)
    seed_real_nif_state!(conversation.id)
    plaintext = "roundtrip via openmls nif"

    assert {:ok, message} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, plaintext)
             )

    reloaded = Repo.get!(Message, message.id)
    refute reloaded.content == plaintext
    assert is_binary(reloaded.content)
    assert byte_size(reloaded.content) > 0
    assert get_in(reloaded.metadata, ["mls", "encrypted"]) == true

    assert {:ok, first_read} =
             MessageService.get_conversation_messages(conversation.id)

    assert Enum.any?(first_read, fn item ->
             item.id == message.id and item.content == plaintext
           end)

    assert {:ok, second_read} =
             MessageService.get_conversation_messages(conversation.id)

    assert Enum.any?(second_read, fn item ->
             item.id == message.id and item.content == plaintext
           end)
  end

  test "real NIF adapter persists encrypted snapshot in conversation_security_states",
       %{conversation: conversation, sender: sender} do
    Application.put_env(:famichat, :mls_adapter, Nif)
    seed_real_nif_state!(conversation.id)

    assert {:ok, _message} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "snapshot-persist")
             )

    persisted_state = Repo.get!(ConversationSecurityState, conversation.id)

    assert is_binary(persisted_state.state_ciphertext)
    assert byte_size(persisted_state.state_ciphertext) > 0
    assert persisted_state.state_format == "vault_term_v1"
    assert persisted_state.protocol == "mls"
    assert persisted_state.lock_version >= 1
  end

  test "read path restores from persisted snapshot after runtime state reset",
       %{conversation: conversation, sender: sender} do
    Application.put_env(:famichat, :mls_adapter, Nif)
    seed_real_nif_state!(conversation.id)
    plaintext = "restore-after-reset"

    assert {:ok, message} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, plaintext)
             )

    reloaded_message = Repo.get!(Message, message.id)

    assert {:ok, _clobbered_runtime} =
             Famichat.Crypto.MLS.create_group(%{
               group_id: conversation.id,
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:error, :commit_rejected, _details} =
             Famichat.Crypto.MLS.process_incoming(%{
               group_id: conversation.id,
               ciphertext: reloaded_message.content
             })

    assert {:ok, messages} =
             MessageService.get_conversation_messages(conversation.id)

    assert Enum.any?(messages, fn item ->
             item.id == message.id and item.content == plaintext
           end)
  end

  test "read path fails closed when persisted state ciphertext is tampered",
       %{conversation: conversation, sender: sender} do
    Application.put_env(:famichat, :mls_adapter, Nif)
    seed_real_nif_state!(conversation.id)

    assert {:ok, message} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "tamper-detection")
             )

    {count, _rows} =
      Repo.update_all(
        from(s in ConversationSecurityState,
          where: s.conversation_id == ^conversation.id
        ),
        set: [state_ciphertext: <<9, 9, 9, 9>>]
      )

    assert count == 1

    reloaded_message = Repo.get!(Message, message.id)

    assert {:ok, _clobbered_runtime} =
             Famichat.Crypto.MLS.create_group(%{
               group_id: conversation.id,
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:error, :commit_rejected, _details} =
             Famichat.Crypto.MLS.process_incoming(%{
               group_id: conversation.id,
               ciphertext: reloaded_message.content
             })

    assert {:error, {:mls_decryption_failed, _code, details}} =
             MessageService.get_conversation_messages(conversation.id)

    refute Map.has_key?(details, :plaintext)
    refute Map.has_key?(details, "plaintext")
    refute Map.has_key?(details, :ciphertext)
    refute Map.has_key?(details, "ciphertext")
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

  test "send_message fails closed with recovery_required when MLS state is missing",
       %{conversation: conversation, sender: sender} do
    Application.put_env(:famichat, :mls_adapter, MissingGroupStateAdapter)
    before_count = Repo.aggregate(Message, :count, :id)

    assert {:error, {:mls_encryption_failed, :recovery_required, details}} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "requires-recovery")
             )

    assert details[:reason] == :missing_group_state
    assert Repo.aggregate(Message, :count, :id) == before_count
  end

  test "send_message fails closed when pending commit is staged",
       %{conversation: conversation, sender: sender} do
    assert {:ok, _persisted_state} =
             Famichat.Chat.ConversationSecurityStateStore.upsert(
               conversation.id,
               %{
                 state: snapshot_payload(),
                 epoch: 2,
                 protocol: "mls",
                 pending_commit: %{
                   "operation" => "mls_commit",
                   "staged_epoch" => 3
                 }
               },
               nil
             )

    before_count = Repo.aggregate(Message, :count, :id)

    assert {:error, {:mls_encryption_failed, :pending_proposals, details}} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "must-fail-pending")
             )

    assert details[:reason] == :pending_proposals
    assert Repo.aggregate(Message, :count, :id) == before_count
  end

  test "send_message fails closed when pending commit metadata is empty map",
       %{conversation: conversation, sender: sender} do
    assert {:ok, _persisted_state} =
             Famichat.Chat.ConversationSecurityStateStore.upsert(
               conversation.id,
               %{
                 state: snapshot_payload(),
                 epoch: 2,
                 protocol: "mls",
                 pending_commit: %{}
               },
               nil
             )

    before_count = Repo.aggregate(Message, :count, :id)

    assert {:error, {:mls_encryption_failed, :pending_proposals, details}} =
             MessageService.send_message(
               message_params(
                 sender.id,
                 conversation.id,
                 "must-fail-empty-pending"
               )
             )

    assert details[:reason] == :pending_proposals
    assert Repo.aggregate(Message, :count, :id) == before_count
  end

  test "send_message rolls back message insert when state lock is stale",
       %{conversation: conversation, sender: sender} do
    Application.put_env(:famichat, :mls_adapter, StaleStateAdapter)

    assert {:ok, _persisted_state} =
             Famichat.Chat.ConversationSecurityStateStore.upsert(
               conversation.id,
               %{state: snapshot_payload(), epoch: 1, protocol: "mls"},
               nil
             )

    before_count = Repo.aggregate(Message, :count, :id)

    assert {:error, {:mls_encryption_failed, :storage_inconsistent, details}} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "lock-conflict")
             )

    assert details[:reason] == :lock_version_mismatch
    assert Repo.aggregate(Message, :count, :id) == before_count
  end

  test "send_message fails closed when mls runtime health is degraded",
       %{conversation: conversation, sender: sender} do
    Application.put_env(:famichat, :mls_adapter, DegradedHealthAdapter)
    before_count = Repo.aggregate(Message, :count, :id)

    assert {:error, {:mls_encryption_failed, :unsupported_capability, details}} =
             MessageService.send_message(
               message_params(sender.id, conversation.id)
             )

    assert details[:reason] == :mls_runtime_not_ready
    assert details[:status] == "degraded"
    assert details[:operation] == :nif_health
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

  test "get_conversation_messages fails closed when mls runtime health is degraded",
       %{conversation: conversation, sender: sender} do
    Application.put_env(
      :famichat,
      :mls_adapter,
      Famichat.TestSupport.MLS.FakeAdapter
    )

    assert {:ok, _message} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "secret payload")
             )

    Application.put_env(:famichat, :mls_adapter, DegradedHealthAdapter)

    assert {:error, {:mls_decryption_failed, :unsupported_capability, details}} =
             MessageService.get_conversation_messages(conversation.id)

    assert details[:reason] == :mls_runtime_not_ready
    assert details[:status] == "degraded"
    assert details[:operation] == :nif_health
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

  defp snapshot_payload do
    %{
      "session_sender_storage" => Base.encode64("sender-storage"),
      "session_recipient_storage" => Base.encode64("recipient-storage"),
      "session_sender_signer" => Base.encode64("sender-signer"),
      "session_recipient_signer" => Base.encode64("recipient-signer"),
      "session_cache" => Base.encode64("cache")
    }
  end

  defp seed_real_nif_state!(conversation_id) do
    {:ok, payload} =
      Famichat.Crypto.MLS.create_group(%{
        group_id: conversation_id,
        ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
      })

    {:ok, _state} =
      ConversationSecurityStateStore.upsert(
        conversation_id,
        %{
          protocol: "mls",
          state: mls_snapshot_from_payload!(payload),
          epoch: mls_epoch_from_payload(payload)
        },
        nil
      )

    :ok
  end

  defp mls_snapshot_from_payload!(payload) do
    [
      "session_sender_storage",
      "session_recipient_storage",
      "session_sender_signer",
      "session_recipient_signer",
      "session_cache"
    ]
    |> Enum.reduce(%{}, fn key, acc ->
      value =
        Map.get(payload, key) ||
          Map.get(payload, String.to_atom(key))

      case value do
        binary when is_binary(binary) ->
          if key == "session_cache" or binary != "" do
            Map.put(acc, key, binary)
          else
            raise "missing MLS snapshot key: #{key}"
          end

        _ ->
          raise "missing MLS snapshot key: #{key}"
      end
    end)
  end

  defp mls_epoch_from_payload(payload) do
    value = Map.get(payload, "epoch") || Map.get(payload, :epoch)

    cond do
      is_integer(value) and value >= 0 ->
        value

      is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} when parsed >= 0 -> parsed
          _ -> 0
        end

      true ->
        0
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end
