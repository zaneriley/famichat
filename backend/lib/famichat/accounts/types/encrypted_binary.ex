defmodule Famichat.Accounts.Types.EncryptedBinary do
  @moduledoc """
  Cloak-backed binary type for encrypting fields such as user email addresses.
  """

  use Cloak.Ecto.Type, vault: Famichat.Vault
end
