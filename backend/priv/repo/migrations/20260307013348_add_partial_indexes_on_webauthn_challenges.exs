defmodule Famichat.Repo.Migrations.AddPartialIndexesOnWebauthnChallenges do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @legacy_index "webauthn_challenges_user_id_type_expires_at_index"
  @user_type_expires "idx_webauthn_challenges_user_type_expires"
  @discoverable_type_expires "idx_webauthn_challenges_discoverable_type_expires"
  @user_consumed "idx_webauthn_challenges_user_consumed"
  @legacy_consumed "webauthn_challenges_consumed_at_index"

  def up do
    create_index_concurrently(
      @user_type_expires,
      """
      ON webauthn_challenges USING btree (user_id, type, expires_at)
      WHERE user_id IS NOT NULL
      """
    )

    create_index_concurrently(
      @discoverable_type_expires,
      """
      ON webauthn_challenges USING btree (type, expires_at)
      WHERE user_id IS NULL
      """
    )

    create_index_concurrently(
      @user_consumed,
      """
      ON webauthn_challenges USING btree (user_id, consumed_at)
      WHERE user_id IS NOT NULL AND consumed_at IS NOT NULL
      """
    )

    drop_index_concurrently(@legacy_index)
    drop_index_concurrently(@legacy_consumed)
  end

  def down do
    create_index_concurrently(
      @legacy_index,
      """
      ON webauthn_challenges USING btree (user_id, type, expires_at)
      """
    )

    create_index_concurrently(
      @legacy_consumed,
      """
      ON webauthn_challenges USING btree (consumed_at)
      """
    )

    drop_index_concurrently(@user_consumed)
    drop_index_concurrently(@discoverable_type_expires)
    drop_index_concurrently(@user_type_expires)
  end

  defp create_index_concurrently(name, definition) do
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS #{name}
    #{definition}
    """)
  end

  defp drop_index_concurrently(name) do
    execute("DROP INDEX CONCURRENTLY IF EXISTS #{name}")
  end
end
