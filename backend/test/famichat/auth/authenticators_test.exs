defmodule Famichat.Auth.AuthenticatorsTest do
  use Famichat.DataCase, async: false

  import Ecto.Query
  import Famichat.ChatFixtures

  alias Famichat.Auth.Authenticators
  alias Famichat.Auth.Authenticators.Challenge
  alias Famichat.Repo

  @issued_event [:famichat, :auth, :authenticators, :challenge_issued]
  @consumed_event [:famichat, :auth, :authenticators, :challenge_consumed]
  @invalid_event [:famichat, :auth, :authenticators, :challenge_invalid]

  setup do
    %{user: user_fixture()}
  end

  test "registration challenge emits telemetry", %{user: user} do
    events =
      capture(@issued_event, fn ->
        assert {:ok, payload} =
                 Authenticators.issue_registration_challenge(user)

        payload
      end)

    assert [event] = events
    assert event.event == @issued_event
    assert event.measurements == %{count: 1}
    assert event.metadata.type == :registration
    assert event.metadata.user_id == user.id
    assert event.metadata.challenge_id

    assert {:ok, payload} = Authenticators.issue_registration_challenge(user)
    refute Map.has_key?(payload, "challenge_token")
  end

  test "consume challenge emits telemetry and prevents replay", %{user: user} do
    {:ok, payload} = Authenticators.issue_registration_challenge(user)
    handle = payload["challenge_handle"]

    {:ok, challenge} = Authenticators.fetch_registration_challenge(handle)

    events =
      capture(@consumed_event, fn ->
        assert {:ok, _} = Authenticators.consume_challenge(challenge)
      end)

    assert [event] = events
    assert event.event == @consumed_event
    assert event.measurements == %{count: 1}
    assert event.metadata.challenge_id == challenge.id
    assert event.metadata.user_id == challenge.user_id

    assert {:error, :already_used} = Authenticators.consume_challenge(challenge)
  end

  test "invalid handle emits telemetry", %{user: _user} do
    events =
      capture(@invalid_event, fn ->
        assert {:error, :invalid_challenge} =
                 Authenticators.fetch_registration_challenge("bad-handle")
      end)

    assert [event] = events
    assert event.event == @invalid_event
    assert event.measurements == %{count: 1}
    assert event.metadata.type == :registration
    assert event.metadata.reason in [:invalid, :invalid_challenge]
  end

  test "expired challenge returns :expired", %{user: user} do
    {:ok, payload} = Authenticators.issue_registration_challenge(user)
    handle = payload["challenge_handle"]

    challenge = latest_challenge(user)

    Repo.update_all(
      from(c in Challenge, where: c.id == ^challenge.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)]
    )

    events =
      capture(@invalid_event, fn ->
        assert {:error, :expired} =
                 Authenticators.fetch_registration_challenge(handle)
      end)

    assert [event] = events
    assert event.metadata.reason == :expired
  end

  test "type mismatch returns invalid challenge", %{user: user} do
    {:ok, payload} = Authenticators.issue_registration_challenge(user)
    handle = payload["challenge_handle"]

    events =
      capture(@invalid_event, fn ->
        assert {:error, :invalid_challenge} =
                 Authenticators.fetch_assertion_challenge(handle)
      end)

    assert [event] = events
    assert event.metadata.reason in [:type_mismatch, :invalid_challenge]
  end

  test "consume prevents replay and invalid telemetry not emitted", %{
    user: user
  } do
    {:ok, payload} = Authenticators.issue_registration_challenge(user)
    handle = payload["challenge_handle"]

    {:ok, challenge} = Authenticators.fetch_registration_challenge(handle)

    assert {:ok, _} = Authenticators.consume_challenge(challenge)

    events =
      capture(@invalid_event, fn ->
        assert {:error, :already_used} =
                 Authenticators.consume_challenge(challenge)
      end)

    assert events == []
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
      "authenticators-telemetry-#{System.unique_integer([:positive])}"

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
