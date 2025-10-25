defmodule Mix.Tasks.Famichat.VerifyUsernames do
  @moduledoc """
  Reports username fingerprint collisions and their case-preserving display values.
  """

  use Boundary, deps: [Famichat], exports: []
  use Mix.Task

  alias Famichat.Auth.Identity

  @shortdoc "Lists usernames and highlights fingerprint collisions"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    users = Identity.list_users_for_username_audit()

    grouped =
      users
      |> Enum.group_by(fn {_id, username, _fingerprint} ->
        Identity.normalize_username(username)
      end)
      |> Enum.reject(fn {normalized, list} ->
        normalized == nil or length(list) <= 1
      end)

    grouped
    |> case do
      [] ->
        Mix.shell().info("No username fingerprint collisions detected ✅")

      collisions ->
        Mix.shell().info("Username collisions detected:")
        Enum.each(collisions, &print_collision/1)
    end
  end

  defp print_collision({normalized, entries}) do
    Mix.shell().info("  normalized=#{normalized} (#{length(entries)} records)")

    Enum.each(entries, &print_entry/1)
  end

  defp print_entry({id, username, fingerprint}) do
    Mix.shell().info(
      "    - #{username} (id=#{id}, fingerprint=#{Base.encode16(fingerprint)})"
    )
  end
end
