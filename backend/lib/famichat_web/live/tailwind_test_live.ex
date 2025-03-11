defmodule FamichatWeb.TailwindTestLive do
  @moduledoc """
  LiveView for testing Tailwind class processing.

  This is a simple component that uses various Tailwind classes to verify
  that Tailwind is correctly processing files and applying styles.
  """
  use FamichatWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # Initialize with a timestamp to force refreshes to show changes
    {:ok, assign(socket, timestamp: DateTime.utc_now())}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    # Update timestamp to show changes
    {:noreply, assign(socket, timestamp: DateTime.utc_now())}
  end
end
