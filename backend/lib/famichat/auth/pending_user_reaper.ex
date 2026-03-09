defmodule Famichat.Auth.PendingUserReaper do
  @moduledoc """
  Periodically runs `PendingUserCleanup.run/0` to delete abandoned `:pending`
  users. Sweeps every 15 minutes.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat.Auth.PendingUserCleanup
    ]

  use GenServer

  require Logger

  alias Famichat.Auth.PendingUserCleanup

  @sweep_interval :timer.minutes(15)

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
    case PendingUserCleanup.run() do
      {:ok, count} when count > 0 ->
        Logger.info("[PendingUserReaper] Cleaned up #{count} abandoned pending user(s)")

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
