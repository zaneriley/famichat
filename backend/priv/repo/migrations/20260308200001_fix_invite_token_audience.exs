defmodule Famichat.Repo.Migrations.FixInviteTokenAudience do
  use Ecto.Migration

  @moduledoc """
  Corrective migration: historical invite and invite_registration tokens
  were stamped with audience = 'user' instead of 'registrant' (the canonical
  audience for unauthenticated invite flows). The original migration
  20251024073731 used 'user' which is incorrect — invitees are not yet
  authenticated users at token issuance time.
  """

  def up do
    execute("""
    UPDATE user_tokens SET audience = 'registrant'
    WHERE kind = 'invite' AND audience = 'user'
    """)

    execute("""
    UPDATE user_tokens SET audience = 'registrant'
    WHERE kind = 'invite_registration' AND audience = 'user'
    """)
  end

  def down do
    execute("""
    UPDATE user_tokens SET audience = 'user'
    WHERE kind = 'invite' AND audience = 'registrant'
    """)

    execute("""
    UPDATE user_tokens SET audience = 'user'
    WHERE kind = 'invite_registration' AND audience = 'registrant'
    """)
  end
end
