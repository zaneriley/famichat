defmodule Famichat.Accounts.Username do
  @moduledoc """
  Shared sanitisation and fingerprint helpers for usernames.
  """

  @fingerprint_algorithm :sha256
  @default_base "family_member"

  @type fingerprint :: binary()

  @doc """
  Trims whitespace from the provided username.

  Returns `nil` when the resulting username is blank.
  """
  @spec sanitize(term()) :: String.t() | nil
  def sanitize(username) when is_binary(username) do
    username
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def sanitize(_), do: nil

  @doc """
  Normalises a username for comparisons by lowercasing the sanitised value.
  """
  @spec normalize(term()) :: String.t() | nil
  def normalize(username) do
    username
    |> sanitize()
    |> case do
      nil -> nil
      trimmed -> String.downcase(trimmed)
    end
  end

  @doc """
  Computes a deterministic fingerprint for the provided username.
  """
  @spec fingerprint(term()) :: fingerprint() | nil
  def fingerprint(username) do
    username
    |> normalize()
    |> fingerprint_from_normalized()
  end

  @doc """
  Ensures a username is unique inside the provided `assigned` set of fingerprints.

  Returns `{candidate, fingerprint, updated_assigned, changed?}` where
  `changed?` is `true` when the candidate differs from the sanitised input.
  """
  @spec maybe_suffix(term(), MapSet.t(fingerprint())) ::
          {String.t(), fingerprint(), MapSet.t(fingerprint()), boolean()}
  def maybe_suffix(username, assigned) do
    base = sanitize(username) || @default_base
    do_maybe_suffix(base, assigned, 0)
  end

  @doc """
  Helper to compute a fingerprint from an already normalised username.
  """
  @spec fingerprint_from_normalized(String.t() | nil) :: fingerprint() | nil
  def fingerprint_from_normalized(nil), do: nil

  def fingerprint_from_normalized(normalized) when is_binary(normalized) do
    :crypto.hash(@fingerprint_algorithm, normalized)
  end

  defp do_maybe_suffix(base, assigned, attempt) do
    candidate = candidate(base, attempt)
    normalized = normalize(candidate)
    fingerprint = fingerprint_from_normalized(normalized)

    cond do
      normalized == nil ->
        do_maybe_suffix(@default_base, assigned, attempt + 1)

      MapSet.member?(assigned, fingerprint) ->
        do_maybe_suffix(base, assigned, attempt + 1)

      true ->
        {candidate, fingerprint, MapSet.put(assigned, fingerprint),
         candidate != base}
    end
  end

  defp candidate(base, 0), do: base
  defp candidate(base, attempt), do: "#{base}_#{attempt + 1}"
end
