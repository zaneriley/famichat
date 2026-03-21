defmodule Famichat.Auth.PasskeysTest do
  use Famichat.DataCase, async: false

  import Ecto.Query
  import Famichat.ChatFixtures

  alias Famichat.Auth.Passkeys
  alias Famichat.Auth.Passkeys.Challenge
  alias Famichat.Repo

  @issued_event [:famichat, :auth, :passkeys, :challenge_issued]
  @consumed_event [:famichat, :auth, :passkeys, :challenge_consumed]
  @invalid_event [:famichat, :auth, :passkeys, :challenge_invalid]

  setup do
    %{user: user_fixture()}
  end

  test "registration challenge emits telemetry", %{user: user} do
    events =
      capture(@issued_event, fn ->
        assert {:ok, payload} =
                 Passkeys.issue_registration_challenge(user)

        payload
      end)

    assert [event] = events
    assert event.event == @issued_event
    assert event.measurements == %{count: 1}
    assert event.metadata.type == :registration
    assert event.metadata.user_id == user.id
    assert event.metadata.challenge_id

    assert {:ok, payload} = Passkeys.issue_registration_challenge(user)
    refute Map.has_key?(payload, "challenge_token")
  end

  test "consume challenge emits telemetry and prevents replay", %{user: user} do
    {:ok, payload} = Passkeys.issue_registration_challenge(user)
    handle = payload["challenge_handle"]

    {:ok, challenge} = Passkeys.fetch_registration_challenge(handle)

    events =
      capture(@consumed_event, fn ->
        assert {:ok, _} = Passkeys.consume_challenge(challenge)
      end)

    assert [event] = events
    assert event.event == @consumed_event
    assert event.measurements == %{count: 1}
    assert event.metadata.challenge_id == challenge.id
    assert event.metadata.user_id == challenge.user_id

    assert {:error, :already_used} = Passkeys.consume_challenge(challenge)
  end

  test "invalid handle emits telemetry", %{user: _user} do
    events =
      capture(@invalid_event, fn ->
        assert {:error, :invalid_challenge} =
                 Passkeys.fetch_registration_challenge("bad-handle")
      end)

    assert [event] = events
    assert event.event == @invalid_event
    assert event.measurements == %{count: 1}
    assert event.metadata.type == :registration
    assert event.metadata.reason in [:invalid, :invalid_challenge]
  end

  test "expired challenge returns :expired", %{user: user} do
    {:ok, payload} = Passkeys.issue_registration_challenge(user)
    handle = payload["challenge_handle"]

    challenge = latest_challenge(user)

    Repo.update_all(
      from(c in Challenge, where: c.id == ^challenge.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)]
    )

    events =
      capture(@invalid_event, fn ->
        assert {:error, :expired} =
                 Passkeys.fetch_registration_challenge(handle)
      end)

    assert [event] = events
    assert event.metadata.reason == :expired
  end

  test "type mismatch returns invalid challenge", %{user: user} do
    {:ok, payload} = Passkeys.issue_registration_challenge(user)
    handle = payload["challenge_handle"]

    events =
      capture(@invalid_event, fn ->
        assert {:error, :invalid_challenge} =
                 Passkeys.fetch_assertion_challenge(handle)
      end)

    assert [event] = events
    assert event.metadata.reason in [:type_mismatch, :invalid_challenge]
  end

  test "consume prevents replay and invalid telemetry not emitted", %{
    user: user
  } do
    {:ok, payload} = Passkeys.issue_registration_challenge(user)
    handle = payload["challenge_handle"]

    {:ok, challenge} = Passkeys.fetch_registration_challenge(handle)

    assert {:ok, _} = Passkeys.consume_challenge(challenge)

    events =
      capture(@invalid_event, fn ->
        assert {:error, :already_used} =
                 Passkeys.consume_challenge(challenge)
      end)

    assert events == []
  end

  # ---------------------------------------------------------------------------
  # BUG-R4-005: issue_assertion_challenge must reject user_id maps
  # ---------------------------------------------------------------------------
  describe "issue_assertion_challenge — user_id enumeration prevention" do
    @tag known_failure: "B6: passkey assertion challenge API changed (2026-03-21)"
    test "user_id-only map returns {:error, :invalid_identifier}", %{user: user} do
      # A map containing only user_id must be rejected before any DB lookup.
      # Without this guard, Identity.resolve_user/1 would do a direct DB lookup
      # and return different errors for existing vs nonexistent UUIDs, enabling
      # user ID enumeration.
      assert {:error, :invalid_identifier} =
               Passkeys.issue_assertion_challenge(%{"user_id" => user.id})
    end

    @tag known_failure: "B6: passkey assertion challenge API changed (2026-03-21)"
    test "nonexistent user_id returns the same error as a real user_id", %{
      user: user
    } do
      real = Passkeys.issue_assertion_challenge(%{"user_id" => user.id})

      fake =
        Passkeys.issue_assertion_challenge(%{
          "user_id" => "00000000-0000-0000-0000-000000000000"
        })

      assert real == fake,
             "Different results for existing (#{inspect(real)}) vs nonexistent " <>
               "(#{inspect(fake)}) UUID — enables enumeration"
    end

    test "user_id alongside username is silently dropped and username wins", %{
      user: user
    } do
      # If someone sends both user_id AND username, user_id must be ignored.
      # The result must be identical to sending username alone.
      result_with_both =
        Passkeys.issue_assertion_challenge(%{
          "user_id" => user.id,
          "username" => user.username
        })

      result_username_only =
        Passkeys.issue_assertion_challenge(%{"username" => user.username})

      # Both should succeed (or fail for the same reason — e.g. no passkeys yet).
      # The important thing is they are identical: user_id must not influence the result.
      case {result_with_both, result_username_only} do
        {{:ok, _}, {:ok, _}} ->
          # Both succeeded — user_id was correctly ignored
          :ok

        {{:error, r1}, {:error, r2}} ->
          assert r1 == r2,
                 "user_id in map changed the error: #{inspect(r1)} vs #{inspect(r2)}"

        _ ->
          flunk(
            "user_id changed the outcome: with_both=#{inspect(result_with_both)}, " <>
              "username_only=#{inspect(result_username_only)}"
          )
      end
    end
  end

  defp latest_challenge(user) do
    Repo.one!(
      from c in Challenge,
        where: c.user_id == ^user.id,
        order_by: [desc: c.inserted_at],
        limit: 1
    )
  end

  defp capture(event, fun) do
    handler_id =
      "passkeys-telemetry-#{System.unique_integer([:positive])}"

    :telemetry.attach(handler_id, event, &forward_event/4, self())

    try do
      _ = fun.()
      receive_events(handler_id)
    after
      :telemetry.detach(handler_id)
    end
  end

  defp forward_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  defp receive_events(handler_id, acc \\ []) do
    receive do
      {:telemetry_event, event, measurements, metadata} ->
        receive_events(handler_id, [
          %{event: event, measurements: measurements, metadata: metadata} | acc
        ])
    after
      100 -> Enum.reverse(acc)
    end
  end
end
