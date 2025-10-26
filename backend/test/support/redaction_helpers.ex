defmodule Famichat.TestSupport.RedactionHelpers do
  @moduledoc false

  import ExUnit.Assertions

  @forbidden ~w[token code email ciphertext key_id secret raw]

  @doc """
  Asserts that telemetry metadata does not expose sensitive fields.
  """
  def pii_free!(metadata) when is_map(metadata) do
    keys = metadata |> Map.keys() |> Enum.map(&to_string/1)

    refute Enum.any?(keys, fn key ->
             Enum.any?(@forbidden, &String.contains?(String.downcase(key), &1))
           end),
           "Telemetry metadata leaks secrets: #{inspect(keys)}"

    :ok
  end
end
