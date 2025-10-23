defmodule Famichat.Accounts.Errors do
  @moduledoc """
  Canonical error enumeration for account façade responses.
  """

  @typedoc "Structured error contract for account operations."
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
  Returns the list of simple atom errors supported by the façade.
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
  Returns the tuple-shaped errors supported by the façade.
  """
  @spec tuple_errors() :: [atom()]
  def tuple_errors do
    [:rate_limited, :forbidden, :validation_failed]
  end
end
