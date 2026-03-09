defmodule Famichat.Schema.Validations do
  @moduledoc """
  Shared changeset validation helpers that encode project-wide conventions.

  Every user-facing string field should call `validate_string_field/3` instead
  of manually composing validate_required + validate_length + trim.
  """

  import Ecto.Changeset

  @default_max_length 255

  @doc """
  Validates a string field with trimming, optional required check, and length bounds.

  ## Options

    * `:required` - whether the field is required (default `true`)
    * `:max` - maximum length (default `#{@default_max_length}`)
    * `:min` - minimum length (default `nil`, no minimum)
    * `:count` - length counting strategy, `:graphemes` or `:bytes` (default `:graphemes`)
  """
  @spec validate_string_field(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_string_field(changeset, field, opts \\ []) do
    required = Keyword.get(opts, :required, true)
    max = Keyword.get(opts, :max, @default_max_length)
    min = Keyword.get(opts, :min, nil)
    count = Keyword.get(opts, :count, :graphemes)

    changeset
    |> trim_field(field)
    |> then(fn cs ->
      if required, do: validate_required(cs, [field]), else: cs
    end)
    |> then(fn cs ->
      length_opts = [max: max, count: count]
      length_opts = if min, do: [{:min, min} | length_opts], else: length_opts
      validate_length(cs, field, length_opts)
    end)
  end

  defp trim_field(changeset, field) do
    update_change(changeset, field, fn
      nil -> nil
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
  end
end
