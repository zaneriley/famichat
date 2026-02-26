defmodule FamichatWeb.Socket.SafeV2JSONSerializerTest do
  use ExUnit.Case, async: true

  alias FamichatWeb.Socket.SafeV2JSONSerializer
  alias Phoenix.Socket.Message

  test "decodes v2 array frames" do
    raw =
      Jason.encode!([
        "1",
        "2",
        "message:direct:conversation-id",
        "phx_join",
        %{}
      ])

    assert %Message{
             join_ref: "1",
             ref: "2",
             topic: "message:direct:conversation-id",
             event: "phx_join",
             payload: %{}
           } = SafeV2JSONSerializer.decode!(raw, opcode: :text)
  end

  test "accepts map-shaped frames for compatibility" do
    raw =
      Jason.encode!(%{
        "topic" => "message:direct:conversation-id",
        "event" => "phx_join",
        "payload" => %{},
        "ref" => "1",
        "join_ref" => "1"
      })

    assert %Message{
             join_ref: "1",
             ref: "1",
             topic: "message:direct:conversation-id",
             event: "phx_join",
             payload: %{}
           } = SafeV2JSONSerializer.decode!(raw, opcode: :text)
  end

  test "returns sentinel message for malformed json" do
    assert %Message{
             topic: "phoenix",
             event: "invalid_message",
             payload: %{}
           } = SafeV2JSONSerializer.decode!("{not-json", opcode: :text)
  end

  test "returns sentinel message for unsupported decoded shapes" do
    raw = Jason.encode!("unsupported")

    assert %Message{
             topic: "phoenix",
             event: "invalid_message",
             payload: %{}
           } = SafeV2JSONSerializer.decode!(raw, opcode: :text)
  end

  test "returns sentinel message for malformed binary frames" do
    assert %Message{
             topic: "phoenix",
             event: "invalid_message",
             payload: %{}
           } = SafeV2JSONSerializer.decode!(<<0, 1, 2, 3>>, opcode: :binary)
  end
end
