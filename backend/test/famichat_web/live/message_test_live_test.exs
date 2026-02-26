defmodule FamichatWeb.MessageTestLiveTest do
  use ExUnit.Case, async: true

  alias FamichatWeb.MessageTestLive
  alias Phoenix.LiveView.Socket

  describe "handle_event/3 for message_received" do
    test "skips local echo when message is from the same user and same device" do
      socket = test_socket()

      payload = %{
        "body" => "same tab echo",
        "timestamp" => "2026-02-25T09:20:00Z",
        "user_id" => "user-1",
        "device_id" => "device-1"
      }

      assert {:noreply, updated_socket} =
               MessageTestLive.handle_event("message_received", payload, socket)

      assert updated_socket.assigns.messages == []
    end

    test "appends message when same user sends from a different device/tab" do
      socket = test_socket()

      payload = %{
        "body" => "other tab message",
        "timestamp" => "2026-02-25T09:20:00Z",
        "user_id" => "user-1",
        "device_id" => "device-2",
        "encrypted" => false
      }

      assert {:noreply, updated_socket} =
               MessageTestLive.handle_event("message_received", payload, socket)

      assert length(updated_socket.assigns.messages) == 1
      [message] = updated_socket.assigns.messages
      assert message.body == "other tab message"
      assert message.outgoing == false
      assert message.encrypted == false
    end
  end

  defp test_socket do
    %Socket{
      assigns: %{
        __changed__: %{},
        messages: [],
        user_id: "user-1",
        device_id: "device-1"
      }
    }
  end
end
