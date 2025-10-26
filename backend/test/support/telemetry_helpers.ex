defmodule Famichat.TestSupport.TelemetryHelpers do
  @moduledoc false

  @forbidden_substrings ["token", "code", "email", "cipher", "key_id"]

  @doc """
  Attaches to a list of telemetry events, executes the provided function,
  and returns the events that were emitted while the function ran.
  """
  def capture(events, fun) when is_list(events) and is_function(fun, 0) do
    handler_id = "tcap-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(handler_id, events, &__MODULE__.forward/4, self())

    try do
      _ = fun.()
      drain(handler_id)
    after
      :telemetry.detach(handler_id)
    end
  end

  def forward(event, measurements, metadata, pid),
    do: send(pid, {:telemetry_event, event, measurements, metadata})

  defp drain(_handler_id, acc \\ []) do
    receive do
      {:telemetry_event, event, measurements, metadata} ->
        drain(nil, [
          %{event: event, measurements: measurements, metadata: metadata} | acc
        ])
    after
      100 ->
        Enum.reverse(acc)
    end
  end

  @doc """
  Checks telemetry metadata for potentially sensitive field names.
  """
  def sensitive_key_present?(metadata) when is_map(metadata) do
    Enum.any?(Map.keys(metadata), fn key ->
      key
      |> to_string()
      |> String.downcase()
      |> contains_forbidden_substring?()
    end)
  end

  defp contains_forbidden_substring?(string) do
    Enum.any?(@forbidden_substrings, &String.contains?(string, &1))
  end
end
