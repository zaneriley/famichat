defmodule Mix.Tasks.Famichat.BackfillSnapshotMacs do
  @moduledoc """
  Backfills `snapshot_mac` for every `ConversationSecurityState` row that
  has a `NULL` MAC — rows written before the N5-a migration.

  Without this task, deploying the nil-MAC rejection gate (N5-a) breaks every
  existing conversation: each row with `snapshot_mac IS NULL` will be rejected
  on the next snapshot load.

  ## Idempotence

  The task only touches rows where `snapshot_mac IS NULL`.  Re-running it after
  a partial run (or after a full successful run) is always safe: rows that
  already have a MAC are skipped entirely.

  ## Logging

  Progress is logged every `@progress_interval` rows and a final summary is
  printed: total rows found, success count, failure count.

  ## Per-row failure handling

  A single row that fails to decrypt or sign does **not** abort the backfill.
  The error is logged at `error` level and the run continues.  A non-zero exit
  code is returned if any rows failed.

  ## Dry-run mode

      mix famichat.backfill_snapshot_macs --dry-run

  In dry-run mode the task reports what it *would* do but writes nothing to the
  database.

  ## Deployment sequence for N5-a

      1. Run migration:   mix ecto.migrate
      2. Run backfill:    mix famichat.backfill_snapshot_macs
      3. Verify output:   check that failure count is 0
      4. Deploy the code that enforces nil-MAC rejection
  """

  use Boundary,
    top_level?: true,
    deps: [
      Famichat,
      Famichat.Chat
    ],
    exports: []

  use Mix.Task

  import Ecto.Query, warn: false
  require Logger

  alias Famichat.Chat.ConversationSecurityState
  alias Famichat.Chat.ConversationSecurityStateStore
  alias Famichat.Crypto.MLS.SnapshotMac
  alias Famichat.Repo

  @shortdoc "Backfills snapshot_mac for pre-N5-a ConversationSecurityState rows"

  @progress_interval 100

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_opts(args)
    dry_run? = Keyword.get(opts, :dry_run, false)

    if dry_run? do
      Mix.shell().info(
        "[backfill_snapshot_macs] DRY-RUN mode — no writes will be made"
      )
    end

    rows = fetch_rows_needing_mac()
    total = length(rows)

    Mix.shell().info(
      "[backfill_snapshot_macs] Found #{total} row(s) with NULL snapshot_mac"
    )

    if total == 0 do
      Mix.shell().info("[backfill_snapshot_macs] Nothing to do. Exiting.")
    else
      hmac_key = SnapshotMac.configured_key!()

      {success_count, failure_count} =
        rows
        |> Enum.with_index(1)
        |> Enum.reduce({0, 0}, fn {record, index}, {ok_acc, err_acc} ->
          result = process_row(record, hmac_key, dry_run?)

          {ok_acc, err_acc} =
            case result do
              :ok -> {ok_acc + 1, err_acc}
              :error -> {ok_acc, err_acc + 1}
            end

          if rem(index, @progress_interval) == 0 do
            Mix.shell().info(
              "[backfill_snapshot_macs] Progress: #{index}/#{total} processed " <>
                "(#{ok_acc} ok, #{err_acc} failed so far)"
            )
          end

          {ok_acc, err_acc}
        end)

      Mix.shell().info(
        "[backfill_snapshot_macs] Done. total=#{total} success=#{success_count} failures=#{failure_count}"
      )

      if failure_count > 0 do
        Mix.shell().error(
          "[backfill_snapshot_macs] #{failure_count} row(s) failed — inspect logs above for details"
        )

        exit({:shutdown, 1})
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp parse_opts(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [dry_run: :boolean])

    opts
  end

  # Query only the primary-key column; we will call load/1 per row so the store
  # handles decryption.  Fetching IDs only keeps the initial query lightweight.
  defp fetch_rows_needing_mac do
    Repo.all(
      from s in ConversationSecurityState,
        where: is_nil(s.snapshot_mac),
        select: s.conversation_id
    )
  end

  defp process_row(conversation_id, hmac_key, dry_run?) do
    with {:ok, payload} <- ConversationSecurityStateStore.load(conversation_id),
         {:ok, mac} <- compute_mac(conversation_id, payload, hmac_key) do
      if dry_run? do
        Logger.info(
          "[backfill_snapshot_macs] [dry-run] would write mac for conversation_id=#{conversation_id}"
        )

        :ok
      else
        write_mac(conversation_id, mac, payload.lock_version)
      end
    else
      {:error, code, details} ->
        Logger.error(
          "[backfill_snapshot_macs] failed for conversation_id=#{conversation_id} " <>
            "code=#{inspect(code)} details=#{inspect(details)}"
        )

        :error

      {:error, reason} ->
        Logger.error(
          "[backfill_snapshot_macs] failed for conversation_id=#{conversation_id} " <>
            "reason=#{inspect(reason)}"
        )

        :error
    end
  end

  # Reproduce exactly the same payload that sign_snapshot/3 in the store and
  # verify_snapshot_mac/2 in MessageService build:
  #   state_map |> Map.put("group_id", conversation_id) |> Map.put("epoch", to_string(epoch))
  defp compute_mac(conversation_id, %{state: state, epoch: epoch}, hmac_key)
       when is_map(state) do
    mac_payload =
      state
      |> Map.put("group_id", conversation_id)
      |> Map.put("epoch", to_string(epoch))

    case SnapshotMac.sign(mac_payload, hmac_key) do
      {:ok, mac} ->
        {:ok, mac}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compute_mac(conversation_id, payload, _hmac_key) do
    {:error, :invalid_state,
     %{
       reason: :state_not_a_map,
       conversation_id: conversation_id,
       state_type:
         payload
         |> Map.get(:state)
         |> then(&if(is_nil(&1), do: nil, else: :unknown))
     }}
  end

  # Write only the snapshot_mac column; use a lock-version guard to avoid
  # racing with concurrent state transitions.
  defp write_mac(conversation_id, mac, lock_version) do
    {updated_count, _rows} =
      Repo.update_all(
        from(s in ConversationSecurityState,
          where:
            s.conversation_id == ^conversation_id and
              s.lock_version == ^lock_version and
              is_nil(s.snapshot_mac)
        ),
        set: [
          snapshot_mac: mac,
          updated_at: DateTime.utc_now(:microsecond)
        ]
      )

    if updated_count == 1 do
      Logger.debug(
        "[backfill_snapshot_macs] wrote mac for conversation_id=#{conversation_id}"
      )

      :ok
    else
      # Either lock_version changed (concurrent write) or MAC was already set.
      # Both are acceptable — the row is or will be in a good state.
      Logger.info(
        "[backfill_snapshot_macs] skipped write for conversation_id=#{conversation_id} " <>
          "(lock_version mismatch or MAC already set by concurrent writer)"
      )

      :ok
    end
  end
end
