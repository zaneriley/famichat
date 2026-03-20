defmodule Famichat.Chat.OrphanFamilyReaper do
  @moduledoc """
  Periodically runs `OrphanFamilyCleanup.run/0` to delete memberless,
  conversation-less families. Sweeps every 30 minutes.
  """

  # Part of Famichat.Chat boundary (no standalone annotation needed).
  use GenServer

  require Logger

  alias Famichat.Chat.OrphanFamilyCleanup

  @sweep_interval :timer.minutes(30)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    case OrphanFamilyCleanup.run() do
      {:ok, count} when count > 0 ->
        Logger.info(
          "[OrphanFamilyReaper] Cleaned up #{count} orphan family/families"
        )

      _ ->
        :ok
    end

    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end
end
