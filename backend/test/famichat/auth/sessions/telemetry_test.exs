defmodule Famichat.Auth.Sessions.TelemetryTest do
  use Famichat.DataCase, async: false

  alias Famichat.Auth.Sessions
  alias Famichat.ChatFixtures

  @refresh_event [:famichat, :auth, :sessions, :refresh]

  test "refresh success emits telemetry" do
    %{user: user, device_id: device_id, refresh_token: refresh_token} =
      start_session()

    events =
      capture(@refresh_event, fn ->
        assert {:ok, %{refresh_token: new_refresh}} =
                 Sessions.refresh_session(device_id, refresh_token)

        new_refresh
      end)

    assert [event] = filter_metric_events(events)
    assert event.event == @refresh_event
    assert event.measurements == %{count: 1}
    assert event.metadata[:device_id] == device_id
    assert event.metadata[:user_id] == user.id
    assert event.metadata[:result] == :success
  end

  test "refresh reuse emits telemetry" do
    %{user: user, device_id: device_id, refresh_token: refresh_token} =
      start_session()

    {:ok, %{refresh_token: new_refresh}} =
      Sessions.refresh_session(device_id, refresh_token)

    events =
      capture(@refresh_event, fn ->
        assert {:error, :reuse_detected} =
                 Sessions.refresh_session(device_id, refresh_token)

        new_refresh
      end)

    assert [event] = filter_metric_events(events)
    assert event.event == @refresh_event
    assert event.measurements == %{count: 1}
    assert event.metadata[:device_id] == device_id
    assert event.metadata[:user_id] == user.id
    assert event.metadata[:result] == :reuse_detected
  end

  test "invalid refresh emits telemetry" do
    %{device_id: device_id} = start_session()

    events =
      capture(@refresh_event, fn ->
        assert {:error, _reason} =
                 Sessions.refresh_session(device_id, "bogus-token")
      end)

    assert [event] = filter_metric_events(events)
    assert event.event == @refresh_event
    assert event.measurements == %{count: 1}
    assert event.metadata[:device_id] == device_id
    assert event.metadata[:reason]
    assert event.metadata[:result] == :invalid
  end

  defp start_session do
    family = ChatFixtures.family_fixture()
    user = ChatFixtures.user_fixture(%{family_id: family.id})

    device_info = %{
      id: Ecto.UUID.generate(),
      user_agent: "telemetry-test",
      ip: "127.0.0.1"
    }

    {:ok, session} =
      Sessions.start_session(user, device_info, remember_device?: true)

    %{
      user: user,
      device_id: session.device_id,
      refresh_token: session.refresh_token
    }
  end

  defp capture(event, fun) do
    handler_id = "auth-sessions-telemetry-#{System.unique_integer([:positive])}"

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

  defp filter_metric_events(events) do
    Enum.filter(events, fn %{metadata: metadata} ->
      Map.has_key?(metadata, :result)
    end)
  end
end
