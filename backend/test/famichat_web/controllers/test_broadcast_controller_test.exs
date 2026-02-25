defmodule FamichatWeb.TestBroadcastControllerTest do
  use FamichatWeb.ConnCase

  alias Famichat.TestSupport.TelemetryHelpers

  @endpoint FamichatWeb.Endpoint
  @telemetry_start [:famichat, :test_broadcast, :trigger, :start]
  @telemetry_stop [:famichat, :test_broadcast, :trigger, :stop]

  describe "trigger" do
    test "broadcasts new_message as new_msg with default payload", %{
      conn: conn
    } do
      topic = unique_topic()
      @endpoint.subscribe(topic)

      conn =
        post(conn, ~p"/api/test/test_events", %{
          "type" => "new_message",
          "topic" => topic
        })

      response = json_response(conn, 200)

      assert response["status"] == "success"
      assert response["message"] == "Event broadcast to #{topic}"
      assert response["event_type"] == "new_message"
      assert response["event_name"] == "new_msg"

      payload = response["payload"]
      assert payload["body"] == "Test message from CLI"
      assert payload["user_id"] == "CLITest"
      assert_iso8601!(payload["timestamp"])

      assert_single_broadcast(topic, "new_msg", payload)
    end

    test "broadcasts typing_indicator without event renaming", %{conn: conn} do
      topic = unique_topic()
      @endpoint.subscribe(topic)

      conn =
        post(conn, ~p"/api/test/test_events", %{
          "type" => "typing_indicator",
          "topic" => topic,
          "sender" => "typing-bot",
          "content" => "typing..."
        })

      response = json_response(conn, 200)

      assert response["status"] == "success"
      assert response["event_type"] == "typing_indicator"
      assert response["event_name"] == "typing_indicator"

      payload = response["payload"]
      assert payload["body"] == "typing..."
      assert payload["user_id"] == "typing-bot"
      assert_iso8601!(payload["timestamp"])

      assert_single_broadcast(topic, "typing_indicator", payload)
    end

    test "broadcasts presence_update without event renaming", %{conn: conn} do
      topic = unique_topic()
      @endpoint.subscribe(topic)

      conn =
        post(conn, ~p"/api/test/test_events", %{
          "type" => "presence_update",
          "topic" => topic,
          "sender" => "presence-bot",
          "content" => "online"
        })

      response = json_response(conn, 200)

      assert response["status"] == "success"
      assert response["event_type"] == "presence_update"
      assert response["event_name"] == "presence_update"

      payload = response["payload"]
      assert payload["body"] == "online"
      assert payload["user_id"] == "presence-bot"
      assert_iso8601!(payload["timestamp"])

      assert_single_broadcast(topic, "presence_update", payload)
    end

    test "includes validated encryption metadata when requested", %{
      conn: conn
    } do
      topic = unique_topic()
      @endpoint.subscribe(topic)

      conn =
        post(conn, ~p"/api/test/test_events", %{
          "type" => "new_message",
          "topic" => topic,
          "encryption" => true,
          "key_id" => "KEY_CUSTOM_v2",
          "version_tag" => "v2.3.4"
        })

      response = json_response(conn, 200)
      payload = response["payload"]

      assert payload["encryption_flag"] == true
      assert payload["key_id"] == "KEY_CUSTOM_v2"
      assert payload["version_tag"] == "v2.3.4"

      assert_single_broadcast(topic, "new_msg", payload)
    end

    test "returns 422 for invalid encryption metadata and does not broadcast", %{
      conn: conn
    } do
      topic = unique_topic()
      @endpoint.subscribe(topic)

      conn =
        post(conn, ~p"/api/test/test_events", %{
          "type" => "new_message",
          "topic" => topic,
          "encryption" => true,
          "key_id" => "bad",
          "version_tag" => "v1.0.0"
        })

      assert json_response(conn, 422) == %{
               "status" => "error",
               "message" =>
                 "Invalid key_id format. Expected pattern: KEY_[A-Z]+_v[0-9]+"
             }

      assert_no_broadcast_on_topic(topic)
    end

    test "returns 422 for invalid version_tag metadata and does not broadcast", %{
      conn: conn
    } do
      topic = unique_topic()
      @endpoint.subscribe(topic)

      conn =
        post(conn, ~p"/api/test/test_events", %{
          "type" => "new_message",
          "topic" => topic,
          "encryption" => true,
          "key_id" => "KEY_TEST_v1",
          "version_tag" => "bad-version"
        })

      assert json_response(conn, 422) == %{
               "status" => "error",
               "message" =>
                 "Invalid version_tag format. Expected pattern: v[0-9]+.[0-9]+.[0-9]+"
             }

      assert_no_broadcast_on_topic(topic)
    end

    test "returns 422 when key_id and version_tag are both invalid", %{
      conn: conn
    } do
      topic = unique_topic()
      @endpoint.subscribe(topic)

      conn =
        post(conn, ~p"/api/test/test_events", %{
          "type" => "new_message",
          "topic" => topic,
          "encryption" => true,
          "key_id" => "bad-key",
          "version_tag" => "bad-version"
        })

      assert json_response(conn, 422) == %{
               "status" => "error",
               "message" => "Invalid key_id and version_tag format"
             }

      assert_no_broadcast_on_topic(topic)
    end

    test "returns 400 when required params are missing", %{conn: conn} do
      topic = unique_topic()
      @endpoint.subscribe(topic)

      conn = post(conn, ~p"/api/test/test_events", %{})

      assert json_response(conn, 400) == %{
               "status" => "error",
               "message" =>
                 "Required parameters: type, topic. Optional: content, sender, encryption, key_id, version_tag"
             }

      assert_no_broadcast_on_topic(topic)
    end

    test "returns 400 for invalid event types", %{conn: conn} do
      topic = unique_topic()
      @endpoint.subscribe(topic)

      conn =
        post(conn, ~p"/api/test/test_events", %{
          "type" => "unexpected",
          "topic" => topic
        })

      assert json_response(conn, 400) == %{
               "status" => "error",
               "message" =>
                 "Invalid event type. Supported types: new_message, presence_update, typing_indicator"
             }

      assert_no_broadcast_on_topic(topic)
    end

    test "emits telemetry for successful trigger", %{conn: conn} do
      topic = unique_topic()

      events =
        TelemetryHelpers.capture([@telemetry_start, @telemetry_stop], fn ->
          conn =
            post(conn, ~p"/api/test/test_events", %{
              "type" => "new_message",
              "topic" => topic
            })

          assert response(conn, 200)
        end)

      assert %{metadata: start_meta} =
               Enum.find(events, &(&1.event == @telemetry_start))

      assert is_binary(start_meta[:conn_id])

      assert %{measurements: stop_measurements, metadata: stop_meta} =
               Enum.find(events, &(&1.event == @telemetry_stop))

      assert is_integer(stop_measurements[:duration]) and
               stop_measurements[:duration] >= 0

      assert stop_meta[:broadcast_success] == true
      refute Map.has_key?(stop_meta, :conn_id)
      refute TelemetryHelpers.sensitive_key_present?(stop_meta)
    end

    test "emits telemetry with error metadata on validation failure", %{
      conn: conn
    } do
      topic = unique_topic()

      events =
        TelemetryHelpers.capture([@telemetry_start, @telemetry_stop], fn ->
          conn =
            post(conn, ~p"/api/test/test_events", %{
              "type" => "new_message",
              "topic" => topic,
              "encryption" => true,
              "key_id" => "bad",
              "version_tag" => "v1.0.0"
            })

          assert response(conn, 422)
        end)

      assert %{metadata: start_meta} =
               Enum.find(events, &(&1.event == @telemetry_start))

      assert is_binary(start_meta[:conn_id])

      assert %{measurements: stop_measurements, metadata: stop_meta} =
               Enum.find(events, &(&1.event == @telemetry_stop))

      assert is_integer(stop_measurements[:duration]) and
               stop_measurements[:duration] >= 0

      assert stop_meta[:broadcast_success] == false

      assert stop_meta[:error] ==
               "Invalid key_id format. Expected pattern: KEY_[A-Z]+_v[0-9]+"
    end
  end

  defp unique_topic do
    "message:direct:characterization-#{System.unique_integer([:positive])}"
  end

  defp assert_single_broadcast(topic, event, payload) do
    assert_receive %Phoenix.Socket.Broadcast{
      topic: ^topic,
      event: ^event,
      payload: ^payload
    }

    assert_no_broadcast_on_topic(topic)
  end

  defp assert_no_broadcast_on_topic(topic) do
    refute_receive %Phoenix.Socket.Broadcast{topic: ^topic}, 50
  end

  defp assert_iso8601!(timestamp) when is_binary(timestamp) do
    assert {:ok, _datetime, 0} = DateTime.from_iso8601(timestamp)
  end
end
