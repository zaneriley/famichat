defmodule FamichatWeb.MessageChannelTest do
  use FamichatWeb.ChannelCase
  import Phoenix.ChannelTest
  require Logger

  alias FamichatWeb.MessageChannel
  alias FamichatWeb.UserSocket

  @endpoint FamichatWeb.Endpoint
  @salt "user_auth"
  @valid_user_id "123e4567-e89b-12d3-a456-426614174000"
  @telemetry_timeout 1000

  setup do
    # Start a telemetry handler for our tests
    test_pid = self()
    handler_id = "message-channel-test-#{:erlang.unique_integer()}"

    Logger.debug("Setting up telemetry handler with id: #{handler_id}")

    :ok =
      :telemetry.attach(
        handler_id,
        [:famichat, :message_channel, :join],
        fn event_name, measurements, metadata, _ ->
          Logger.debug("""
          Telemetry event received in test:
          - event_name: #{inspect(event_name)}
          - measurements: #{inspect(measurements)}
          - metadata: #{inspect(metadata)}
          """)
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

    on_exit(fn ->
      Logger.debug("Detaching telemetry handler: #{handler_id}")
      :telemetry.detach(handler_id)
    end)

    {:ok, %{handler_id: handler_id}}
  end

  describe "socket connection" do
    test "returns error when token is invalid" do
      invalid_token = "invalid_token"
      assert {:error, %{reason: "invalid_token"}} = connect(UserSocket, %{"token" => invalid_token})
    end

    test "successfully connects with valid token" do
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      assert {:ok, socket} = connect(UserSocket, %{"token" => token})
      assert socket.assigns.user_id == @valid_user_id
    end
  end

  describe "channel join" do
    setup do
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      {:ok, %{socket: socket}}
    end

    test "successfully joins channel with valid token", %{socket: socket} do
      Logger.debug("Attempting to join channel with socket assigns: #{inspect(socket.assigns)}")

      # First assert the join is successful
      assert {:ok, _reply, _socket} = subscribe_and_join(socket, MessageChannel, "message:lobby")

      # Then verify the telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join], measurements,
                     metadata}, @telemetry_timeout

      Logger.debug("Received telemetry metadata in test: #{inspect(metadata)}")

      # Assert measurements
      assert is_map(measurements)
      assert Map.has_key?(measurements, :start_time)
      assert Map.has_key?(measurements, :system_time)
      assert Map.has_key?(measurements, :monotonic_time)

      # Assert metadata for successful join
      assert metadata.status == :success
      assert metadata.encryption_status == "enabled"
      assert metadata.user_id == @valid_user_id
      assert metadata.room_id == "lobby"
    end

    test "rejects join without user_id in socket assigns" do
      socket = socket_without_user_id()

      # First assert the join is rejected
      assert {:error, %{reason: "unauthorized"}} = join(socket, "message:lobby", %{})

      # Then verify the telemetry event
      assert_receive {:telemetry_event, [:famichat, :message_channel, :join], measurements,
                     metadata}, @telemetry_timeout

      # Assert measurements
      assert is_map(measurements)
      assert Map.has_key?(measurements, :start_time)
      assert Map.has_key?(measurements, :system_time)
      assert Map.has_key?(measurements, :monotonic_time)

      # Assert metadata for unauthorized join
      assert metadata.status == :error
      assert metadata.error_reason == :unauthorized
      assert metadata.room_id == "lobby"
    end
  end

  describe "message broadcasting" do
    setup do
      token = Phoenix.Token.sign(@endpoint, @salt, @valid_user_id)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      {:ok, _, socket} = subscribe_and_join(socket, MessageChannel, "message:lobby")
      {:ok, %{socket: socket}}
    end

    test "broadcasts messages on the channel", %{socket: socket} do
      message_body = "Hello, world!"
      push(socket, "new_msg", %{"body" => message_body})

      assert_broadcast "new_msg", %{
        "body" => ^message_body,
        "user_id" => @valid_user_id
      }
    end

    test "does not broadcast messages with missing body", %{socket: socket} do
      ref = push(socket, "new_msg", %{})
      refute_broadcast "new_msg", _
      assert_reply ref, :error, %{reason: "invalid_message"}
    end

    test "broadcasts messages with encryption metadata", %{socket: socket} do
      encrypted_message = %{
        "body" => "encrypted_content",
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_USER_v1"
      }

      push(socket, "new_msg", encrypted_message)

      assert_broadcast "new_msg", %{
        "body" => "encrypted_content",
        "user_id" => @valid_user_id,
        "version_tag" => "v1.0.0",
        "encryption_flag" => true,
        "key_id" => "KEY_USER_v1"
      }
    end
  end

  defp socket_without_user_id do
    socket(UserSocket, nil, %{})
  end
end
