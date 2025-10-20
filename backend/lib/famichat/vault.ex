defmodule Famichat.Vault do
  @moduledoc """
  Cloak vault used for field-level encryption (for example, user emails).
  """
  use Cloak.Vault, otp_app: :famichat
end
