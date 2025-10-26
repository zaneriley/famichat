defmodule Famichat.Auth.Infra.Audit do
  @moduledoc "Deprecated alias; use `Famichat.Auth.Runtime.Audit`."

  @typedoc "Audit event metadata."
  @type record :: Famichat.Auth.Runtime.Audit.record()

  @deprecated "use Famichat.Auth.Runtime.Audit.record/2"
  @spec record(String.t(), keyword()) :: :ok
  def record(event, opts \\ []) do
    Famichat.Auth.Runtime.Audit.record(event, opts)
  end
end
