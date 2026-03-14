defmodule Famichat.Repo.Migrations.AddStringLengthCheckConstraints do
  @moduledoc """
  Adds DB-level CHECK constraints on user-facing string columns.

  These are a structural safety net: even if application-level
  validate_length is missing or bypassed, the DB rejects oversized input.

  Prevents: unbounded string input reaching PostgreSQL (14 fields across
  6 schemas had no length validation as of 2026-03-09 bug bash).

  CHECK constraints are metadata-only — zero downtime, zero table rewrite.
  """
  use Ecto.Migration

  def up do
    # User-facing fields
    execute "ALTER TABLE families ADD CONSTRAINT families_name_length CHECK (char_length(name) <= 100)"

    execute "ALTER TABLE communities ADD CONSTRAINT communities_name_length CHECK (char_length(name) <= 100)"

    execute "ALTER TABLE users ADD CONSTRAINT users_username_length CHECK (char_length(username) <= 50)"

    execute "ALTER TABLE passkeys ADD CONSTRAINT passkeys_label_length CHECK (char_length(label) <= 100)"

    execute "ALTER TABLE user_devices ADD CONSTRAINT user_devices_user_agent_length CHECK (char_length(user_agent) <= 512)"

    execute "ALTER TABLE user_devices ADD CONSTRAINT user_devices_ip_length CHECK (char_length(ip) <= 45)"

    execute "ALTER TABLE messages ADD CONSTRAINT messages_content_length CHECK (octet_length(content) <= 65536)"

    execute "ALTER TABLE messages ADD CONSTRAINT messages_media_url_length CHECK (char_length(media_url) <= 2048)"

    # Internal but worth bounding (defense in depth)
    execute "ALTER TABLE user_tokens ADD CONSTRAINT user_tokens_context_length CHECK (char_length(context) <= 100)"

    execute "ALTER TABLE user_tokens ADD CONSTRAINT user_tokens_kind_length CHECK (char_length(kind) <= 50)"

    execute "ALTER TABLE user_tokens ADD CONSTRAINT user_tokens_audience_length CHECK (char_length(audience) <= 100)"
  end

  def down do
    execute "ALTER TABLE families DROP CONSTRAINT IF EXISTS families_name_length"
    execute "ALTER TABLE communities DROP CONSTRAINT IF EXISTS communities_name_length"
    execute "ALTER TABLE users DROP CONSTRAINT IF EXISTS users_username_length"
    execute "ALTER TABLE passkeys DROP CONSTRAINT IF EXISTS passkeys_label_length"
    execute "ALTER TABLE user_devices DROP CONSTRAINT IF EXISTS user_devices_user_agent_length"
    execute "ALTER TABLE user_devices DROP CONSTRAINT IF EXISTS user_devices_ip_length"
    execute "ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_content_length"
    execute "ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_media_url_length"
    execute "ALTER TABLE user_tokens DROP CONSTRAINT IF EXISTS user_tokens_context_length"
    execute "ALTER TABLE user_tokens DROP CONSTRAINT IF EXISTS user_tokens_kind_length"
    execute "ALTER TABLE user_tokens DROP CONSTRAINT IF EXISTS user_tokens_audience_length"
  end
end
