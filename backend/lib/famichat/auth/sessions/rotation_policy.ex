defmodule Famichat.Auth.Sessions.RotationPolicy do
  @moduledoc "Deprecated shim. Use `Famichat.Auth.Sessions.RefreshRotation` instead."
  @deprecated "use Famichat.Auth.Sessions.RefreshRotation"

  defdelegate verify_and_rotate(device, raw_refresh, issue_fun),
    to: Famichat.Auth.Sessions.RefreshRotation
end
