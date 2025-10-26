defmodule Famichat.Accounts.Errors do
  @moduledoc "Deprecated alias; use `Famichat.Auth.Errors`."
  @type t :: Famichat.Auth.Errors.t()

  @deprecated "use Famichat.Auth.Errors.atom_errors/0"
  @spec atom_errors() :: [atom()]
  def atom_errors do
    Famichat.Auth.Errors.atom_errors()
  end

  @deprecated "use Famichat.Auth.Errors.tuple_errors/0"
  @spec tuple_errors() :: [atom()]
  def tuple_errors do
    Famichat.Auth.Errors.tuple_errors()
  end
end
