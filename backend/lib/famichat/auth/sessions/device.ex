defmodule Famichat.Auth.Sessions.Device do
  @moduledoc "Deprecated shim. Use `Famichat.Auth.Sessions.DeviceStore` instead."
  @deprecated "use Famichat.Auth.Sessions.DeviceStore"

  defdelegate normalize_info(device_info),
    to: Famichat.Auth.Sessions.DeviceStore

  defdelegate upsert(user, info, remember?, refresh_ttl),
    to: Famichat.Auth.Sessions.DeviceStore

  defdelegate revoke(device, attrs \\ %{}),
    to: Famichat.Auth.Sessions.DeviceStore
end
