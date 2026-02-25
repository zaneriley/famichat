defmodule FamichatWeb.MessageTestControllerTest do
  use FamichatWeb.ConnCase

  @endpoint FamichatWeb.Endpoint

  setup do
    # Subscribe to the test channel
    @endpoint.subscribe("message:lobby")
    :ok
  end

  describe "broadcast" do
    test "broadcasts a plain text message", %{conn: conn} do
      params = %{
        "type" => "legacy",
        "id" => "lobby",
        "body" => "Test message"
      }

      conn = post(conn, ~p"/api/test/broadcast", params)

      assert json_response(conn, 200) == %{
               "status" => "ok",
               "message" => "Broadcast sent to message:lobby"
             }

      assert_single_broadcast("message:lobby", "new_msg", %{
        "body" => "Test message",
        "user_id" => "TEST_USER"
      })
    end

    test "broadcasts an encrypted message", %{conn: conn} do
      params = %{
        "type" => "legacy",
        "id" => "lobby",
        "body" => "Encrypted content",
        "encryption" => true
      }

      conn = post(conn, ~p"/api/test/broadcast", params)

      assert json_response(conn, 200) == %{
               "status" => "ok",
               "message" => "Broadcast sent to message:lobby"
             }

      assert_single_broadcast("message:lobby", "new_msg", %{
        "body" => "Encrypted content",
        "user_id" => "TEST_USER",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_TEST_v1"
      })
    end

    test "returns error for missing parameters", %{conn: conn} do
      conn = post(conn, ~p"/api/test/broadcast", %{})

      assert json_response(conn, 400) == %{
               "status" => "error",
               "message" =>
                 "Required parameters: type, id, body. Optional: encryption (boolean)"
             }

      assert_no_broadcast_on_topic("message:lobby")
    end

    test "broadcasts to typed conversation topics", %{conn: conn} do
      conversation_id =
        "characterization-#{System.unique_integer([:positive])}"

      topic = "message:direct:#{conversation_id}"
      @endpoint.subscribe(topic)

      params = %{
        "type" => "direct",
        "id" => conversation_id,
        "body" => "Direct message"
      }

      conn = post(conn, ~p"/api/test/broadcast", params)

      assert json_response(conn, 200) == %{
               "status" => "ok",
               "message" => "Broadcast sent to #{topic}"
             }

      assert_single_broadcast(topic, "new_msg", %{
        "body" => "Direct message",
        "user_id" => "TEST_USER"
      })
    end

    test "returns error for unsupported conversation type", %{conn: conn} do
      conn =
        post(conn, ~p"/api/test/broadcast", %{
          "type" => "unsupported",
          "id" => "lobby",
          "body" => "Should fail"
        })

      assert json_response(conn, 400) == %{
               "status" => "error",
               "message" =>
                 "Type must be one of: self, direct, group, family, legacy"
             }

      assert_no_broadcast_on_topic("message:lobby")
    end
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
end
