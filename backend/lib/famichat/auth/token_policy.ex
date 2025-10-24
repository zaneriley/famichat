defmodule Famichat.Auth.TokenPolicy do
  @moduledoc "Deprecated shim. Use `Famichat.Auth.Tokens.Policy` instead."
  @deprecated "use Famichat.Auth.Tokens.Policy"

  alias Famichat.Auth.Tokens.Policy
  alias Famichat.Auth.Tokens.Policy.Definition

  @type storage :: Policy.storage()

  @spec policy!(Famichat.Auth.Tokens.kind()) :: Definition.t()
  defdelegate policy!(kind), to: Policy

  @spec default_ttl(Famichat.Auth.Tokens.kind()) :: pos_integer()
  defdelegate default_ttl(kind), to: Policy

  @spec max_ttl(Famichat.Auth.Tokens.kind()) :: pos_integer()
  defdelegate max_ttl(kind), to: Policy

  @spec audience(Famichat.Auth.Tokens.kind()) :: atom()
  defdelegate audience(kind), to: Policy

  @spec legacy_context(Famichat.Auth.Tokens.kind()) :: String.t() | nil
  defdelegate legacy_context(kind), to: Policy

  @spec policy_map() :: %{
          optional(Famichat.Auth.Tokens.kind()) => Definition.t()
        }
  defdelegate policy_map(), to: Policy
end

defmodule Famichat.Auth.TokenPolicy.Policy do
  @moduledoc "Deprecated struct alias. Use `Famichat.Auth.Tokens.Policy.Definition`."

  @type t :: Famichat.Auth.Tokens.Policy.Definition.t()
end
