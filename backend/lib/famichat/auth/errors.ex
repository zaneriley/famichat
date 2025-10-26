defmodule Famichat.Auth.Errors do
  @moduledoc """
  Canonical error enumeration exposed by the authentication boundary.
  """

  @typedoc "Structured error contract for auth operations."
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

  @doc """
  Returns the list of atom-only error variants.
  """
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

  @doc """
  Returns the tuple-shaped error tags supported by the façade.
  """
  @spec tuple_errors() :: [atom()]
  def tuple_errors do
    [:rate_limited, :forbidden, :validation_failed]
  end
end
