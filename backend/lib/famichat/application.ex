defmodule Famichat.Application do
  @moduledoc false
  use Application

  use Boundary,
    top_level?: true,
    deps: [Famichat, FamichatWeb, Famichat.Auth.PendingUserReaper]

  @impl true
  def start(_type, _args) do
    # Always attach telemetry handler
    unless Application.get_env(:famichat, :environment) == :test do
      Famichat.TelemetryHandler.attach()
    end

    # Can't be a child process for some reason.
    Application.start(:yamerl)

    children = [
      FamichatWeb.Telemetry,
      Famichat.Repo,
      Famichat.Vault,
      {DNSCluster,
       query: Application.get_env(:famichat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Famichat.PubSub},
      {Finch, name: Famichat.Finch},
      {Task.Supervisor, name: Famichat.TaskSupervisor},
      Famichat.Chat.MessageRateLimiter,
      Famichat.Auth.PendingUserReaper,
      FamichatWeb.TokenVerifyCache,
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
