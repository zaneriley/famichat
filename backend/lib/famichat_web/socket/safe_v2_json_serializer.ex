defmodule FamichatWeb.Socket.SafeV2JSONSerializer do
  @moduledoc false
  @behaviour Phoenix.Socket.Serializer

  require Logger

  alias Phoenix.Socket.{Message, V2}

  @impl true
  def fastlane!(broadcast), do: V2.JSONSerializer.fastlane!(broadcast)

  @impl true
  def encode!(message_or_reply), do: V2.JSONSerializer.encode!(message_or_reply)

  @impl true
  def decode!(raw_message, opts) do
    case Keyword.fetch(opts, :opcode) do
      {:ok, :text} ->
        decode_text(raw_message)

      {:ok, :binary} ->
        V2.JSONSerializer.decode!(raw_message, opts)
    end
  rescue
    error in [
      ArgumentError,
      FunctionClauseError,
      KeyError,
      MatchError,
      Phoenix.Socket.InvalidMessageError
    ] ->
      Logger.debug(
        "Ignoring malformed websocket frame: #{inspect(error.__struct__)}"
      )

      invalid_message()
  end

  defp decode_text(raw_message) do
    case Phoenix.json_library().decode(raw_message) do
      {:ok, [join_ref, ref, topic, event, payload | _]} ->
        %Message{
          topic: topic,
          event: event,
          payload: payload,
          ref: ref,
          join_ref: join_ref
        }

      {:ok, %{} = payload_map} ->
        Message.from_map!(payload_map)

      {:ok, _other} ->
        invalid_message()

      {:error, _reason} ->
        invalid_message()
    end
  end

  defp invalid_message do
    %Message{
      topic: "phoenix",
      event: "invalid_message",
      payload: %{},
      ref: nil,
      join_ref: nil
    }
  end
end
