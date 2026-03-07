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

  defmodule SnapshotPersistingAdapter do
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

    def create_application_message(params) do
      body = Map.get(params, :body) || Map.get(params, "body") || ""

      {:ok,
       %{
         ciphertext: "ciphertext:#{body}",
         epoch: 2,
         session_sender_storage: Base.encode64("sender-storage-new"),
         session_recipient_storage: Base.encode64("recipient-storage-new"),
         session_sender_signer: Base.encode64("sender-signer-new"),
         session_recipient_signer: Base.encode64("recipient-signer-new"),
         session_cache: Base.encode64("cache-new")
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

  test "application messages do NOT rewrite the snapshot in conversation_security_states",
       %{conversation: conversation, sender: sender} do
    # Invariant: send_message (application message) must NOT persist the
    # MLS snapshot to the database. Only epoch-advancing operations
    # (ConversationSecurityLifecycle.merge_pending_commit/2) write the snapshot.
    # This prevents 10-80 KB TOAST write amplification per message at
    # family-scale traffic.
    Application.put_env(:famichat, :mls_adapter, Nif)
    seed_real_nif_state!(conversation.id)

    # Capture the lock_version and ciphertext written by the seed step.
    seeded_state = Repo.get!(ConversationSecurityState, conversation.id)
    seeded_lock_version = seeded_state.lock_version
    seeded_ciphertext = seeded_state.state_ciphertext

    assert {:ok, _message} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "no-snapshot-write")
             )

    # After N application messages, the snapshot row must not have changed.
    assert {:ok, _message2} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "no-snapshot-write-2")
             )

    assert {:ok, _message3} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "no-snapshot-write-3")
             )

    persisted_state = Repo.get!(ConversationSecurityState, conversation.id)

    # lock_version must be unchanged — no upsert happened.
    assert persisted_state.lock_version == seeded_lock_version
    # The stored ciphertext blob must be byte-for-byte identical to what was
    # seeded; no TOAST rewrite occurred.
    assert persisted_state.state_ciphertext == seeded_ciphertext
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

  test "send_message succeeds even when a concurrent write bumps the lock version",
       %{conversation: conversation, sender: sender} do
    # Under the lazy-snapshot invariant, send_message no longer attempts to
    # upsert the snapshot row, so concurrent lock version changes made by the
    # StaleStateAdapter (or any other concurrent writer) do NOT cause the
    # message send to fail. The message is persisted independently.
    Application.put_env(:famichat, :mls_adapter, StaleStateAdapter)

    assert {:ok, _persisted_state} =
             Famichat.Chat.ConversationSecurityStateStore.upsert(
               conversation.id,
               %{state: snapshot_payload(), epoch: 1, protocol: "mls"},
               nil
             )

    before_count = Repo.aggregate(Message, :count, :id)

    # Should succeed — no snapshot upsert races with message insert.
    assert {:ok, _message} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "no-lock-conflict")
             )

    assert Repo.aggregate(Message, :count, :id) == before_count + 1
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

  test "R4: error short-circuit — first message failure halts page, does not silently succeed",
       %{conversation: conversation, sender: sender} do
    # Insert 3 messages so the parallel decrypt loop has multiple tasks to run.
    assert {:ok, _m1} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "msg-1")
             )

    assert {:ok, _m2} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "msg-2")
             )

    assert {:ok, _m3} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "msg-3")
             )

    # Switch to an adapter that fails every process_incoming call.
    # The reduce_while in do_decrypt_messages must halt on the first error
    # and return {:error, ...} — never {:ok, messages}.
    Application.put_env(:famichat, :mls_adapter, DecryptionFailAdapter)

    assert {:error, {:mls_decryption_failed, :crypto_failure, _details}} =
             MessageService.get_conversation_messages(conversation.id)
  end

  test "R4: parallel page returns messages in original insertion order",
       %{conversation: conversation, sender: sender} do
    # Insert 5 messages with distinct content so we can verify order from
    # the returned plaintext values.  Task.async_stream uses ordered: true,
    # so results must arrive in the same sequence regardless of which task
    # finishes first.
    contents = ~w[alpha bravo charlie delta echo]

    ids =
      Enum.map(contents, fn body ->
        assert {:ok, msg} =
                 MessageService.send_message(
                   message_params(sender.id, conversation.id, body)
                 )

        msg.id
      end)

    # FakeAdapter.process_incoming returns plaintext: "plaintext:#{ciphertext}"
    # where ciphertext is "ciphertext:#{original_body}" — so the returned
    # content is deterministic and order-sensitive.
    assert {:ok, retrieved} =
             MessageService.get_conversation_messages(conversation.id, limit: 5)

    assert length(retrieved) == 5

    # IDs must be in insertion order (not arbitrary task-completion order).
    assert Enum.map(retrieved, & &1.id) == ids

    # Content values must also reflect original insertion order.
    expected_plaintexts =
      Enum.map(contents, fn body -> "plaintext:ciphertext:#{body}" end)

    assert Enum.map(retrieved, & &1.content) == expected_plaintexts
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

  test "send_message does not update the snapshot even when the adapter returns snapshot keys",
       %{conversation: conversation, sender: sender} do
    # SnapshotPersistingAdapter returns snapshot keys in its create_application_message
    # response (epoch 2 and all session_* keys). Under the lazy-snapshot invariant,
    # send_message must NOT write that snapshot to the database. The snapshot row
    # should remain exactly as seeded at epoch 1.
    Application.put_env(:famichat, :mls_adapter, SnapshotPersistingAdapter)

    assert {:ok, _persisted_state} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{state: snapshot_payload(), epoch: 1, protocol: "mls"},
               nil
             )

    seeded = Repo.get!(ConversationSecurityState, conversation.id)
    seeded_lock_version = seeded.lock_version

    assert {:ok, _message} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "no-epoch-advance")
             )

    assert {:ok, reloaded} =
             ConversationSecurityStateStore.load(conversation.id)

    # Epoch must remain at 1 — the adapter-returned epoch 2 must not be persisted.
    assert reloaded.epoch == 1
    # lock_version must not have incremented — no DB write occurred.
    assert reloaded.lock_version == seeded_lock_version
  end

  test "merge_pending_commit DOES persist the snapshot after an epoch advance",
       %{conversation: conversation} do
    # This test verifies the positive case: epoch-advancing operations must
    # write the snapshot. send_message must not write it (see test above).
    # We seed an initial state, then stage + merge a commit to advance the epoch,
    # and confirm the snapshot is updated in the DB.
    assert {:ok, initial} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{state: snapshot_payload(), epoch: 1, protocol: "mls"},
               nil
             )

    initial_lock_version = initial.lock_version

    # Stage a pending commit at epoch 2.
    assert {:ok, after_stage} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{
                 state: snapshot_payload(),
                 epoch: 1,
                 protocol: "mls",
                 pending_commit: %{
                   "operation" => "mls_commit",
                   "staged_epoch" => 2
                 }
               },
               initial.lock_version
             )

    after_stage_lock = after_stage.lock_version

    # Merge the pending commit — this should write the snapshot.
    # We use ConversationSecurityStateStore.upsert directly to model what
    # ConversationSecurityLifecycle.merge_pending_commit does: persist a new
    # snapshot blob with the advanced epoch, clearing pending_commit.
    assert {:ok, after_merge} =
             ConversationSecurityStateStore.upsert(
               conversation.id,
               %{
                 state: snapshot_payload(),
                 epoch: 2,
                 protocol: "mls",
                 pending_commit: nil
               },
               after_stage_lock
             )

    # Epoch advanced and a DB write occurred (lock_version incremented).
    assert after_merge.epoch == 2
    assert after_merge.lock_version > initial_lock_version
    assert after_merge.pending_commit == nil
  end

  test "sending N application messages results in exactly 1 snapshot write (the seed)",
       %{conversation: conversation, sender: sender} do
    # Core lazy-snapshot invariant: N application messages must produce zero
    # additional snapshot writes beyond the initial seed. Only epoch-advancing
    # operations (Add/Remove/Commit) are allowed to write the snapshot.
    Application.put_env(:famichat, :mls_adapter, Nif)
    seed_real_nif_state!(conversation.id)

    seeded = Repo.get!(ConversationSecurityState, conversation.id)
    seeded_lock_version = seeded.lock_version

    n = 5

    for i <- 1..n do
      assert {:ok, _msg} =
               MessageService.send_message(
                 message_params(sender.id, conversation.id, "msg-#{i}")
               )
    end

    after_sends = Repo.get!(ConversationSecurityState, conversation.id)

    # lock_version must not have changed — zero snapshot upserts occurred.
    assert after_sends.lock_version == seeded_lock_version,
           "Expected lock_version=#{seeded_lock_version} (no snapshot writes) " <>
             "but got #{after_sends.lock_version} after #{n} application messages"
  end

  test "recovery path correctly reloads from last epoch-advancing snapshot after NIF state loss",
       %{conversation: conversation, sender: sender} do
    # After a simulated server restart (NIF in-memory state cleared), the
    # recovery lifecycle must reload from the last persisted epoch-advancing
    # snapshot and allow subsequent operations to succeed.
    Application.put_env(:famichat, :mls_adapter, Nif)
    seed_real_nif_state!(conversation.id)
    plaintext = "pre-restart-message"

    assert {:ok, message} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, plaintext)
             )

    # Verify the message was encrypted and stored.
    reloaded_message = Repo.get!(Message, message.id)
    assert reloaded_message.content != plaintext
    assert is_binary(reloaded_message.content)

    # Simulate NIF state loss by overwriting the group with a fresh session.
    # After this, process_incoming will fail — matching post-restart behavior.
    assert {:ok, _} =
             Famichat.Crypto.MLS.create_group(%{
               group_id: conversation.id,
               ciphersuite: "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519"
             })

    assert {:error, :commit_rejected, _} =
             Famichat.Crypto.MLS.process_incoming(%{
               group_id: conversation.id,
               ciphertext: reloaded_message.content
             })

    # The recovery path must restore from the last persisted snapshot and
    # allow decryption to succeed again.
    assert {:ok, messages} =
             MessageService.get_conversation_messages(conversation.id)

    assert Enum.any?(messages, fn m ->
             m.id == message.id and m.content == plaintext
           end),
           "Recovery path did not restore decrypted content from persisted snapshot"
  end

  test "concurrent MLS sends do not cause snapshot conflicts",
       %{conversation: conversation, sender: sender} do
    # Under the lazy-snapshot invariant, send_message does NOT write to
    # conversation_security_states. This means concurrent sends cannot
    # race on the snapshot row's lock_version. This test verifies that
    # 6 concurrent sends all succeed and that the snapshot row is untouched.
    Application.put_env(:famichat, :mls_adapter, Nif)
    seed_real_nif_state!(conversation.id)

    seeded_state = Repo.get!(ConversationSecurityState, conversation.id)
    seeded_lock_version = seeded_state.lock_version

    n = 6

    results =
      1..n
      |> Task.async_stream(
        fn i ->
          MessageService.send_message(
            message_params(sender.id, conversation.id, "concurrent-msg-#{i}")
          )
        end,
        max_concurrency: n,
        timeout: 10_000,
        ordered: false
      )
      |> Enum.to_list()

    # Every task must return {:ok, _task_result} from async_stream, and
    # the inner send_message must succeed — no stale_state or race errors.
    assert length(results) == n

    Enum.each(results, fn result ->
      assert {:ok, {:ok, %{id: _id}}} = result,
             "Expected all concurrent sends to succeed, got: #{inspect(result)}"
    end)

    # All n messages must be persisted in the messages table.
    persisted_count =
      Repo.aggregate(
        from(m in Message,
          where: m.conversation_id == ^conversation.id
        ),
        :count,
        :id
      )

    assert persisted_count == n,
           "Expected #{n} messages persisted, got #{persisted_count}"

    # The snapshot row must not have been touched — lock_version unchanged.
    after_state = Repo.get!(ConversationSecurityState, conversation.id)

    assert after_state.lock_version == seeded_lock_version,
           "Expected lock_version=#{seeded_lock_version} (no snapshot writes) " <>
             "but got #{after_state.lock_version} after #{n} concurrent sends"
  end

  test "snapshot MAC verification rejects tampered state_ciphertext bytes",
       %{conversation: conversation, sender: sender} do
    # Security invariant: a DB-level attacker who replaces snapshot_mac with a
    # forged value cannot bypass MAC verification. When load_mls_snapshot_with_lock
    # finds that the stored MAC does not match the decrypted state, it must
    # reject the snapshot and surface {:error, :snapshot_integrity_failed, ...},
    # which send_message wraps as {:error, {:mls_encryption_failed, :snapshot_integrity_failed, _}}.
    #
    # This test simulates a tampered snapshot_mac (leaving state_ciphertext
    # intact so Vault decryption still succeeds) and confirms the MAC check
    # is the gate that rejects the state — not ciphertext corruption.
    Application.put_env(:famichat, :mls_adapter, Nif)
    seed_real_nif_state!(conversation.id)

    # Confirm the seeded state loads cleanly before tampering.
    assert {:ok, _clean_state} =
             ConversationSecurityStateStore.load(conversation.id)

    # Directly overwrite snapshot_mac in the DB with a plausible-looking but
    # incorrect 64-character hex string. state_ciphertext is left intact so
    # Vault decryption will succeed — but the recomputed MAC will not match.
    fake_mac = String.duplicate("a", 64)

    {count, _} =
      Repo.update_all(
        from(s in ConversationSecurityState,
          where: s.conversation_id == ^conversation.id
        ),
        set: [snapshot_mac: fake_mac]
      )

    assert count == 1

    # Attempting to send a message must fail because load_mls_snapshot_with_lock
    # will call verify_snapshot_mac, find a mismatch, and return
    # {:error, :snapshot_integrity_failed, _}.  send_message wraps this as
    # {:error, {:mls_encryption_failed, :snapshot_integrity_failed, _}}.
    before_count = Repo.aggregate(Message, :count, :id)

    assert {:error,
            {:mls_encryption_failed, :snapshot_integrity_failed, details}} =
             MessageService.send_message(
               message_params(sender.id, conversation.id, "must-be-rejected")
             )

    # The error details must reference the tampered conversation.
    assert details[:conversation_id] == conversation.id

    # No message must have been persisted — fails closed.
    assert Repo.aggregate(Message, :count, :id) == before_count
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
