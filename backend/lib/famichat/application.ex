defmodule Famichat.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Only attach in non-test environments
    if Mix.env() != :test do
      Famichat.TelemetryHandler.attach()
    else
      :telemetry.detach("famichat-logger")
    end

    # Can't be a child process for some reason.
    Application.start(:yamerl)

    children = [
      FamichatWeb.Telemetry,
      Famichat.Repo,
      {DNSCluster,
       query: Application.get_env(:famichat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Famichat.PubSub},
      {Finch, name: Famichat.Finch},
      FamichatWeb.Endpoint,
      Famichat.Cache
    ]

    opts = [strategy: :one_for_one, name: Famichat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FamichatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
