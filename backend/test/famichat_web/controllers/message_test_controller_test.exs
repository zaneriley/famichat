defmodule FamichatWeb.MessageTestControllerTest do
  use FamichatWeb.ConnCase
  import Phoenix.ChannelTest

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

      assert_broadcast "new_msg", %{
        "body" => "Test message",
        "user_id" => "TEST_USER"
      }
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

      assert_broadcast "new_msg", %{
        "body" => "Encrypted content",
        "user_id" => "TEST_USER",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_TEST_v1"
      }
    end

    test "returns error for missing parameters", %{conn: conn} do
      conn = post(conn, ~p"/api/test/broadcast", %{})

      assert json_response(conn, 400) == %{
               "status" => "error",
               "message" =>
                 "Required parameters: type, id, body. Optional: encryption (boolean)"
             }

      refute_broadcast "new_msg", _
    end
  end
end
