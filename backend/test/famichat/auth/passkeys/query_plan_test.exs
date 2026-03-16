defmodule Famichat.Auth.Passkeys.QueryPlanTest do
  use Famichat.DataCase, async: false

  alias Famichat.Auth.Passkeys
  alias Famichat.Auth.Passkeys.Challenge
  alias Famichat.ChatFixtures
  alias Famichat.Repo

  @legacy_index "webauthn_challenges_user_id_type_expires_at_index"
  @legacy_consumed "webauthn_challenges_consumed_at_index"
  @user_type_expires "idx_webauthn_challenges_user_type_expires"
  @discoverable_type_expires "idx_webauthn_challenges_discoverable_type_expires"
  @user_consumed "idx_webauthn_challenges_user_consumed"
  @plan_table "query_plan_webauthn_challenges"

  describe "webauthn_challenges partial indexes" do
    test "creates the expected partial indexes and drops the legacy indexes" do
      indexes = index_details()

      refute Map.has_key?(indexes, @legacy_index)
      refute Map.has_key?(indexes, @legacy_consumed)

      assert_index(indexes, @user_type_expires, %{
        definition: "(user_id, type, expires_at)",
        predicates: ["user_id IS NOT NULL"]
      })

      assert_index(indexes, @discoverable_type_expires, %{
        definition: "(type, expires_at)",
        predicates: ["user_id IS NULL"]
      })

      assert_index(indexes, @user_consumed, %{
        definition: "(user_id, consumed_at)",
        predicates: ["user_id IS NOT NULL", "consumed_at IS NOT NULL"]
      })
    end

    test "still fetches user-bound and discoverable challenges by handle" do
      user = ChatFixtures.user_fixture()
      user_id = user.id

      {:ok, user_bound} = Passkeys.issue_assertion_challenge(user)
      {:ok, discoverable} = Passkeys.issue_discoverable_assertion_challenge()

      assert {:ok, %Challenge{user_id: ^user_id, type: :assertion}} =
               Passkeys.fetch_assertion_challenge(
                 user_bound["challenge_handle"]
               )

      assert {:ok, %Challenge{user_id: nil, type: :assertion}} =
               Passkeys.fetch_assertion_challenge(
                 discoverable["challenge_handle"]
               )
    end
  end

  describe "planner usage for representative cleanup queries" do
    setup do
      user = ChatFixtures.user_fixture()
      other_user = ChatFixtures.user_fixture()
      now = DateTime.utc_now()
      expired_at = DateTime.add(now, -60, :second)
      future_at = DateTime.add(now, 300, :second)
      consumed_at = DateTime.add(now, -30, :second)

      create_plan_table()

      seed_cleanup_rows(
        @plan_table,
        user.id,
        other_user.id,
        expired_at,
        future_at,
        consumed_at
      )

      Repo.query!("ANALYZE #{@plan_table}")
      Repo.query!("SET LOCAL enable_seqscan = off")

      {:ok, user: user, now: now}
    end

    test "expired user-bound cleanup uses the partial user/type/expires index",
         %{user: user, now: now} do
      plan =
        explain(
          @plan_table,
          """
          DELETE FROM %TABLE%
          WHERE user_id = $1::uuid
            AND type = 'assertion'
            AND expires_at < $2::timestamptz
          """,
          [dump_uuid(user.id), now]
        )

      assert_uses_index(plan, @user_type_expires)
    end

    test "expired discoverable cleanup uses the discoverable partial index", %{
      now: now
    } do
      plan =
        explain(
          @plan_table,
          """
          DELETE FROM %TABLE%
          WHERE user_id IS NULL
            AND type = 'assertion'
            AND expires_at < $1::timestamptz
          """,
          [now]
        )

      assert_uses_index(plan, @discoverable_type_expires)
    end

    test "consumed cleanup uses the partial user/consumed index", %{
      user: user,
      now: now
    } do
      plan =
        explain(
          @plan_table,
          """
          DELETE FROM %TABLE%
          WHERE user_id = $1::uuid
            AND consumed_at IS NOT NULL
            AND consumed_at <= $2::timestamptz
          """,
          [dump_uuid(user.id), now]
        )

      assert_uses_index(plan, @user_consumed)
    end
  end

  defp assert_index(indexes, name, %{
         definition: definition,
         predicates: predicates
       }) do
    detail = Map.fetch!(indexes, name)

    assert detail.valid?
    assert detail.ready?
    assert detail.definition =~ definition

    Enum.each(predicates, fn predicate ->
      assert detail.predicate =~ predicate
    end)
  end

  defp assert_uses_index(plan, index_name) do
    assert normalize_sql(plan) =~ index_name
  end

  defp index_details do
    Repo.query!("""
    SELECT
      index_class.relname AS name,
      pg_get_indexdef(index_class.oid) AS definition,
      COALESCE(pg_get_expr(index_data.indpred, index_data.indrelid), '') AS predicate,
      index_data.indisvalid,
      index_data.indisready
    FROM pg_class AS table_class
    JOIN pg_namespace AS namespace
      ON namespace.oid = table_class.relnamespace
    JOIN pg_index AS index_data
      ON index_data.indrelid = table_class.oid
    JOIN pg_class AS index_class
      ON index_class.oid = index_data.indexrelid
    WHERE namespace.nspname = current_schema()
      AND table_class.relname = 'webauthn_challenges'
    ORDER BY index_class.relname
    """).rows
    |> Map.new(fn [name, definition, predicate, valid?, ready?] ->
      {name,
       %{
         definition: normalize_sql(definition),
         predicate: normalize_sql(predicate),
         valid?: valid?,
         ready?: ready?
       }}
    end)
  end

  defp explain(table_name, sql, params) do
    Repo.query!(
      """
      EXPLAIN (ANALYZE, COSTS OFF, BUFFERS OFF, SUMMARY OFF, TIMING OFF)
      #{String.replace(sql, "%TABLE%", table_name)}
      """,
      params
    ).rows
    |> Enum.map_join("\n", &List.first/1)
  end

  defp dump_uuid(uuid) when is_binary(uuid), do: Ecto.UUID.dump!(uuid)

  defp create_plan_table do
    Repo.query!("""
    CREATE TEMP TABLE #{@plan_table} (
      LIKE webauthn_challenges INCLUDING DEFAULTS INCLUDING CONSTRAINTS
    ) ON COMMIT DROP
    """)

    Repo.query!("""
    CREATE INDEX #{@user_type_expires}
    ON #{@plan_table} USING btree (user_id, type, expires_at)
    WHERE user_id IS NOT NULL
    """)

    Repo.query!("""
    CREATE INDEX #{@discoverable_type_expires}
    ON #{@plan_table} USING btree (type, expires_at)
    WHERE user_id IS NULL
    """)

    Repo.query!("""
    CREATE INDEX #{@user_consumed}
    ON #{@plan_table} USING btree (user_id, consumed_at)
    WHERE user_id IS NOT NULL AND consumed_at IS NOT NULL
    """)
  end

  defp seed_cleanup_rows(
         source,
         user_id,
         other_user_id,
         expired_at,
         future_at,
         consumed_at
       ) do
    now = DateTime.utc_now()

    rows =
      Enum.flat_map(1..80, fn seed ->
        [
          user_bound_row(user_id, expired_at, nil, now, seed),
          user_bound_row(user_id, future_at, nil, now, seed + 100),
          user_bound_row(user_id, future_at, consumed_at, now, seed + 200),
          user_bound_row(other_user_id, expired_at, nil, now, seed + 300),
          user_bound_row(
            other_user_id,
            future_at,
            consumed_at,
            now,
            seed + 400
          ),
          discoverable_row(expired_at, now, seed + 500),
          discoverable_row(future_at, now, seed + 600)
        ]
      end)

    Repo.insert_all({source, Challenge}, rows)
  end

  defp user_bound_row(user_id, expires_at, consumed_at, inserted_at, seed) do
    %{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      type: :assertion,
      challenge: :crypto.strong_rand_bytes(32) <> <<seed::16>>,
      expires_at: expires_at,
      consumed_at: consumed_at,
      inserted_at: inserted_at
    }
  end

  defp discoverable_row(expires_at, inserted_at, seed) do
    %{
      id: Ecto.UUID.generate(),
      user_id: nil,
      type: :assertion,
      challenge: :crypto.strong_rand_bytes(32) <> <<seed::16>>,
      expires_at: expires_at,
      consumed_at: nil,
      inserted_at: inserted_at
    }
  end

  defp normalize_sql(sql) do
    sql
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
