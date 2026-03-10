defmodule Famichat.Auth.TokenReaper do
  @moduledoc """
  Periodically runs `TokenCleanup.run/0` to delete expired tokens.
  Sweeps every 30 minutes.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat.Auth.TokenCleanup
    ]

  use GenServer

  require Logger

  alias Famichat.Auth.TokenCleanup

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
    case TokenCleanup.run() do
      {:ok, count} when count > 0 ->
        Logger.info("[TokenReaper] Cleaned up #{count} expired token(s)")

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
