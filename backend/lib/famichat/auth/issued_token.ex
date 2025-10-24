defmodule Famichat.Auth.IssuedToken do
  @moduledoc """
  Canonical result returned by `Famichat.Auth.Tokens`.
  """

  @enforce_keys [:kind, :class, :raw, :issued_at]
  defstruct [
    :kind,
    :class,
    :raw,
    :hash,
    :record,
    :audience,
    :subject_id,
    :issued_at,
    :expires_at
  ]

  @typedoc "Storage class used for the token."
  @type class :: :ledgered | :signed | :device_secret

  @typedoc "Public token return payload."
  @type t :: %__MODULE__{
          kind: Famichat.Auth.Tokens.kind(),
          class: class(),
          raw: String.t(),
          hash: binary() | nil,
          record: Famichat.Accounts.UserToken.t() | nil,
          audience: atom() | nil,
          subject_id: term() | nil,
          issued_at: DateTime.t(),
          expires_at: DateTime.t() | nil
        }
end
