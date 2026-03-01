defmodule Famichat.Chat.ConversationSecurityStateStore do
  @moduledoc """
  Chat-owned persistence boundary for durable conversation security state.
  """
  import Ecto.Query, warn: false
  require Logger

  alias Famichat.Chat.ConversationSecurityState
  alias Famichat.Crypto.MLS.SnapshotMac
  alias Famichat.Repo
  alias Famichat.Vault

  @state_format "vault_term_v1"
  @default_protocol "mls"

  @type record_payload :: %{
          conversation_id: Ecto.UUID.t(),
          protocol: String.t(),
          state: map(),
          epoch: non_neg_integer(),
          pending_commit: map() | nil,
          snapshot_mac: String.t() | nil,
          lock_version: pos_integer()
        }

  @spec load(Ecto.UUID.t()) ::
          {:ok, record_payload()} | {:error, atom(), map()}
  def load(conversation_id) when is_binary(conversation_id) do
    case Repo.get(ConversationSecurityState, conversation_id) do
      %ConversationSecurityState{} = record ->
        decode_record(record)

      nil ->
        {:error, :not_found, %{reason: :missing_state}}
    end
  end

  def load(_conversation_id) do
    {:error, :invalid_input,
     %{reason: :invalid_conversation_id, operation: :load}}
  end

  @spec upsert(Ecto.UUID.t(), map(), pos_integer() | nil) ::
          {:ok, record_payload()} | {:error, atom(), map()}
  def upsert(conversation_id, attrs, expected_lock_version \\ nil)

  def upsert(conversation_id, attrs, expected_lock_version)
      when is_binary(conversation_id) and is_map(attrs) do
    with :ok <- validate_expected_lock_version(expected_lock_version),
         {:ok, encoded_attrs} <- encode_attrs(conversation_id, attrs) do
      do_upsert(conversation_id, encoded_attrs, expected_lock_version)
    end
  end

  def upsert(_conversation_id, _attrs, _expected_lock_version) do
    {:error, :invalid_input, %{reason: :invalid_upsert_input}}
  end

  @spec delete(Ecto.UUID.t()) :: :ok | {:error, atom(), map()}
  def delete(conversation_id) when is_binary(conversation_id) do
    _ =
      Repo.delete_all(
        from s in ConversationSecurityState,
          where: s.conversation_id == ^conversation_id
      )

    :ok
  end

  def delete(_conversation_id) do
    {:error, :invalid_input,
     %{reason: :invalid_conversation_id, operation: :delete}}
  end

  defp validate_expected_lock_version(nil), do: :ok

  defp validate_expected_lock_version(value)
       when is_integer(value) and value >= 1,
       do: :ok

  defp validate_expected_lock_version(_value) do
    {:error, :invalid_input,
     %{reason: :invalid_expected_lock_version, operation: :upsert}}
  end

  defp encode_attrs(conversation_id, attrs) do
    state = Map.get(attrs, :state) || Map.get(attrs, "state")

    epoch =
      Map.get(attrs, :epoch) || Map.get(attrs, "epoch") || 0

    protocol =
      Map.get(attrs, :protocol) || Map.get(attrs, "protocol") ||
        @default_protocol

    pending_commit =
      Map.get(attrs, :pending_commit) || Map.get(attrs, "pending_commit")

    with {:ok, state_payload} <- normalize_state(state),
         {:ok, pending_payload} <- normalize_optional_state(pending_commit),
         :ok <- validate_epoch(epoch),
         :ok <- validate_protocol(protocol),
         {:ok, state_ciphertext} <- encode_state_payload(state_payload),
         {:ok, pending_ciphertext} <-
           encode_optional_state_payload(pending_payload),
         {:ok, snapshot_mac} <-
           sign_snapshot(conversation_id, epoch, state_payload) do
      {:ok,
       %{
         conversation_id: conversation_id,
         protocol: protocol,
         epoch: epoch,
         state_ciphertext: state_ciphertext,
         state_format: @state_format,
         pending_commit_ciphertext: pending_ciphertext,
         pending_commit_format:
           if(is_binary(pending_ciphertext), do: @state_format, else: nil),
         snapshot_mac: snapshot_mac
       }}
    end
  end

  defp normalize_state(%{} = state), do: {:ok, state}

  defp normalize_state(_invalid) do
    {:error, :invalid_input,
     %{reason: :missing_or_invalid_state, operation: :upsert}}
  end

  defp normalize_optional_state(nil), do: {:ok, nil}
  defp normalize_optional_state(%{} = pending_commit), do: {:ok, pending_commit}

  defp normalize_optional_state(_invalid) do
    {:error, :invalid_input,
     %{reason: :invalid_pending_commit, operation: :upsert}}
  end

  defp validate_epoch(epoch) when is_integer(epoch) and epoch >= 0, do: :ok

  defp validate_epoch(_epoch) do
    {:error, :invalid_input, %{reason: :invalid_epoch, operation: :upsert}}
  end

  defp validate_protocol(protocol)
       when is_binary(protocol) and byte_size(protocol) > 0,
       do: :ok

  defp validate_protocol(_protocol) do
    {:error, :invalid_input, %{reason: :invalid_protocol, operation: :upsert}}
  end

  defp encode_optional_state_payload(nil), do: {:ok, nil}
  defp encode_optional_state_payload(payload), do: encode_state_payload(payload)

  defp sign_snapshot(conversation_id, epoch, state_payload)
       when is_binary(conversation_id) and is_map(state_payload) do
    mac_payload =
      state_payload
      |> Map.put("group_id", conversation_id)
      |> Map.put("epoch", to_string(epoch))

    case SnapshotMac.sign(mac_payload, SnapshotMac.configured_key!()) do
      {:ok, mac} ->
        {:ok, mac}

      {:error, reason} ->
        Logger.warning("snapshot MAC sign failed: #{inspect(reason)}")
        {:ok, nil}
    end
  end

  defp encode_state_payload(payload) do
    try do
      ciphertext =
        payload
        |> :erlang.term_to_binary([:compressed])
        |> Vault.encrypt!()

      {:ok, ciphertext}
    rescue
      e in [RuntimeError, ArgumentError] ->
        {:error, :state_encode_failed,
         %{reason: :state_encode_failed, operation: :upsert, message: Exception.message(e)}}

      e ->
        Logger.error("Unexpected exception in encode_state_payload: #{inspect(e)}")
        reraise e, __STACKTRACE__
    end
  end

  @snapshot_required_keys ~w(session_sender_storage session_recipient_storage
                              session_sender_signer session_recipient_signer session_cache)

  defp decode_state_payload("vault_term_v1", ciphertext) when is_binary(ciphertext) do
    try do
      with decrypted when is_binary(decrypted) <- Vault.decrypt!(ciphertext),
           decoded <- :erlang.binary_to_term(decrypted, [:safe]),
           true <-
             is_map(decoded) and
               Enum.all?(@snapshot_required_keys, &is_binary(Map.get(decoded, &1))) do
        {:ok, decoded}
      else
        _ ->
          {:error, :state_decode_failed,
           %{reason: :state_decode_failed, operation: :load}}
      end
    rescue
      e in [RuntimeError, ArgumentError, Cloak.MissingCipher] ->
        {:error, :state_decode_failed,
         %{reason: :state_decode_failed, operation: :load, message: Exception.message(e)}}

      e ->
        Logger.error("Unexpected exception in decode_state_payload: #{inspect(e)}")
        reraise e, __STACKTRACE__
    end
  end

  defp decode_state_payload("vault_term_v1", _ciphertext) do
    {:error, :state_decode_failed,
     %{reason: :state_decode_failed, operation: :load}}
  end

  defp decode_state_payload(_unknown_format, _ciphertext) do
    {:error, :state_decode_failed, %{reason: :unknown_state_format}}
  end

  defp decode_optional_state_payload(nil, _format), do: {:ok, nil}

  # pending_commit is a control map (operation, staged_epoch, …), not a
  # snapshot — it must NOT be validated against @snapshot_required_keys.
  defp decode_optional_state_payload(ciphertext, format),
    do: decode_pending_commit_payload(format, ciphertext)

  defp decode_pending_commit_payload("vault_term_v1", ciphertext)
       when is_binary(ciphertext) do
    try do
      with decrypted when is_binary(decrypted) <- Vault.decrypt!(ciphertext),
           decoded <- :erlang.binary_to_term(decrypted, [:safe]),
           true <- is_map(decoded) do
        {:ok, decoded}
      else
        _ ->
          {:error, :state_decode_failed,
           %{reason: :pending_commit_decode_failed, operation: :load}}
      end
    rescue
      e in [RuntimeError, ArgumentError, Cloak.MissingCipher] ->
        {:error, :state_decode_failed,
         %{
           reason: :pending_commit_decode_failed,
           operation: :load,
           message: Exception.message(e)
         }}

      e ->
        Logger.error("Unexpected exception in decode_pending_commit_payload: #{inspect(e)}")
        reraise e, __STACKTRACE__
    end
  end

  defp decode_pending_commit_payload("vault_term_v1", _ciphertext) do
    {:error, :state_decode_failed,
     %{reason: :pending_commit_decode_failed, operation: :load}}
  end

  defp decode_pending_commit_payload(_unknown_format, _ciphertext) do
    {:error, :state_decode_failed,
     %{reason: :unknown_pending_commit_format}}
  end

  defp decode_record(%ConversationSecurityState{} = record) do
    pending_format =
      record.pending_commit_format || record.state_format

    with {:ok, state} <- decode_state_payload(record.state_format, record.state_ciphertext),
         {:ok, pending_commit} <-
           decode_optional_state_payload(record.pending_commit_ciphertext, pending_format) do
      {:ok,
       %{
         conversation_id: record.conversation_id,
         protocol: record.protocol,
         state: state,
         epoch: record.epoch,
         pending_commit: pending_commit,
         snapshot_mac: record.snapshot_mac,
         lock_version: record.lock_version
       }}
    end
  end

  defp do_upsert(conversation_id, encoded_attrs, nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    insert_attrs =
      encoded_attrs
      |> Map.put(:lock_version, 1)
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)

    {inserted_count, _rows} =
      Repo.insert_all(
        ConversationSecurityState,
        [insert_attrs],
        on_conflict: :nothing,
        conflict_target: [:conversation_id]
      )

    if inserted_count == 1 do
      load(conversation_id)
    else
      {:error, :stale_state, %{reason: :concurrent_insert}}
    end
  end

  defp do_upsert(conversation_id, encoded_attrs, expected_lock_version) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    next_lock_version = expected_lock_version + 1

    {updated_count, rows} =
      Repo.update_all(
        from(s in ConversationSecurityState,
          where:
            s.conversation_id == ^conversation_id and
              s.lock_version == ^expected_lock_version,
          select: s
        ),
        set: [
          protocol: encoded_attrs.protocol,
          state_ciphertext: encoded_attrs.state_ciphertext,
          state_format: encoded_attrs.state_format,
          epoch: encoded_attrs.epoch,
          pending_commit_ciphertext: encoded_attrs.pending_commit_ciphertext,
          pending_commit_format: encoded_attrs.pending_commit_format,
          snapshot_mac: encoded_attrs.snapshot_mac,
          lock_version: next_lock_version,
          updated_at: now
        ]
      )

    if updated_count == 1 do
      [record] = rows
      decode_record(record)
    else
      {:error, :stale_state, %{reason: :lock_version_mismatch}}
    end
  end
end
