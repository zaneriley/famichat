# Configure ExUnit
ExUnit.configure(
  exclude: [pending: true],
  formatters: [ExUnit.CLIFormatter, ExUnitNotifier]
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Famichat.Repo, :manual)

# Add to setup_all
:telemetry.detach("famichat-logger")
