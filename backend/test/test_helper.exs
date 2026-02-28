# Ensure Repo uses sandbox pool (runtime config may override)
Application.put_env(
  :famichat,
  Famichat.Repo,
  Keyword.put(
    Application.get_env(:famichat, Famichat.Repo) || [],
    :pool,
    Ecto.Adapters.SQL.Sandbox
  )
)

# Configure ExUnit
ExUnit.configure(
  exclude: [pending: true, timing: true],
  formatters: [ExUnit.CLIFormatter, ExUnitNotifier]
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Famichat.Repo, :manual)

# Add to setup_all
:telemetry.detach("famichat-logger")
