defmodule Famichat.Accounts.Errors do
  @moduledoc "Deprecated alias; use `Famichat.Auth.Errors`."
  @type t ::
          :invalid
          | :expired
          | :used
          | :revoked
          | :trust_expired
          | :trust_required
          | :reuse_detected
          | {:rate_limited, pos_integer()}
          | {:forbidden, atom()}
          | {:validation_failed, Ecto.Changeset.t()}

  @deprecated "use Famichat.Auth.Errors.atom_errors/0"
  @spec atom_errors() :: [atom()]
  def atom_errors do
    [
      :invalid,
      :expired,
      :used,
      :revoked,
      :trust_expired,
      :trust_required,
      :reuse_detected
    ]
  end

  @deprecated "use Famichat.Auth.Errors.tuple_errors/0"
  @spec tuple_errors() :: [atom()]
  def tuple_errors do
    [:rate_limited, :forbidden, :validation_failed]
  end
end
