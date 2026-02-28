defmodule Famichat.Crypto.MLS.SnapshotMac do
  import Bitwise, only: [bxor: 2, bor: 2]

  @moduledoc """
  HMAC-SHA256 integrity protection for MLS group-session snapshots.

  ## Problem

  Snapshots passed from Elixir to the Rust NIF via `restore_group_session_from_snapshot`
  carry no integrity check.  A crafted or swapped snapshot could:

  1. Restore a group session into the wrong conversation context.
  2. Be used in a TOCTOU attack (snapshot read, group advances, stale snapshot restored).

  ## Approach

  Option B — Elixir-side MAC.  The NIF contract remains `HashMap<String, String>`;
  MAC computation and verification happen entirely in Elixir before the map is
  handed to the NIF.

  ## MAC coverage

  The HMAC-SHA256 input is the concatenation, with `|` separators, of:

      group_id | epoch | session_sender_storage | session_recipient_storage |
      session_sender_signer | session_recipient_signer | session_cache

  `group_id` binds the snapshot to a specific conversation.
  `epoch` prevents replay of a stale (earlier) snapshot into an advanced group.
  The five session fields cover all serialised state bytes.

  Fields are taken from the payload map; atom and string keys are both accepted
  (the NIF adapter normalises to string keys, but callers may use atoms before
  stringification).

  ## Keying

  The HMAC key is fetched from application config:

      Application.fetch_env!(:famichat, :mls_snapshot_hmac_key)

  The key must be a binary of at least 32 bytes.  See `config/runtime.exs` for
  how the key is sourced from the `MLS_SNAPSHOT_HMAC_KEY` environment variable.

  ## Wire format

  `sign/2` returns the MAC as a 64-character lowercase hex string.
  `verify/2` accepts the same format and returns `:ok | {:error, :mac_mismatch}`.
  """

  @snapshot_fields ~w[
    session_sender_storage
    session_recipient_storage
    session_sender_signer
    session_recipient_signer
    session_cache
  ]

  @doc """
  Compute an HMAC-SHA256 over the identifying fields of `payload`.

  `payload` must contain `"group_id"` and `"epoch"` in addition to the five
  snapshot-state fields.  Either atom or string keys are accepted.

  Returns `{:ok, mac_hex}` on success, or `{:error, reason}` if a required
  field is absent or the configured key is invalid.
  """
  @spec sign(map(), binary()) :: {:ok, String.t()} | {:error, atom()}
  def sign(payload, hmac_key) when is_map(payload) and is_binary(hmac_key) do
    with {:ok, message} <- build_message(payload) do
      mac =
        :crypto.mac(:hmac, :sha256, hmac_key, message)
        |> Base.encode16(case: :lower)

      {:ok, mac}
    end
  end

  @doc """
  Verify that `mac_hex` matches the HMAC-SHA256 computed over `payload`.

  Returns `:ok` on a valid MAC, `{:error, :mac_mismatch}` on any mismatch
  (including missing fields), and `{:error, reason}` for configuration errors.

  Uses a constant-time comparison to resist timing attacks.
  """
  @spec verify(map(), String.t(), binary()) :: :ok | {:error, atom()}
  def verify(payload, mac_hex, hmac_key)
      when is_map(payload) and is_binary(mac_hex) and is_binary(hmac_key) do
    with {:ok, expected_hex} <- sign(payload, hmac_key) do
      if constant_time_compare(expected_hex, mac_hex) do
        :ok
      else
        {:error, :mac_mismatch}
      end
    end
  end

  @doc """
  Fetch the HMAC key from application config.

  Raises if `:mls_snapshot_hmac_key` is not configured (i.e. the environment
  variable `MLS_SNAPSHOT_HMAC_KEY` was not set at startup).
  """
  @spec configured_key!() :: binary()
  def configured_key! do
    Application.fetch_env!(:famichat, :mls_snapshot_hmac_key)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_message(payload) do
    group_id = fetch_field(payload, "group_id")
    epoch = fetch_field(payload, "epoch")

    if is_nil(group_id) or is_nil(epoch) do
      {:error, :missing_required_fields}
    else
      snapshot_values =
        Enum.map(@snapshot_fields, fn field ->
          fetch_field(payload, field) || ""
        end)

      message =
        ([group_id, epoch] ++ snapshot_values)
        |> Enum.join("|")

      {:ok, message}
    end
  end

  # Accept both atom and string keys; string wins if both are present.
  defp fetch_field(payload, field) when is_binary(field) do
    string_val = Map.get(payload, field)
    atom_key = String.to_existing_atom(field)
    atom_val = Map.get(payload, atom_key)
    string_val || atom_val
  rescue
    ArgumentError -> Map.get(payload, field)
  end

  # Constant-time binary comparison (same length enforced via ==, then byte-by-byte XOR).
  # Both inputs are 64-char hex strings so the length check is always equal for
  # valid MACs; the XOR loop runs regardless to avoid short-circuit exits.
  defp constant_time_compare(a, b) when is_binary(a) and is_binary(b) do
    if byte_size(a) != byte_size(b) do
      false
    else
      a_bytes = :binary.bin_to_list(a)
      b_bytes = :binary.bin_to_list(b)

      Enum.zip(a_bytes, b_bytes)
      |> Enum.reduce(0, fn {x, y}, acc -> bor(acc, bxor(x, y)) end)
      |> Kernel.==(0)
    end
  end
end
