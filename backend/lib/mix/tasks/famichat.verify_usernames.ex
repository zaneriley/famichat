defmodule Mix.Tasks.Famichat.VerifyUsernames do
  @moduledoc """
  Reports username fingerprint collisions and their case-preserving display values.
  """

  use Mix.Task

  alias Famichat.Accounts.User
  alias Famichat.Accounts.Username
  alias Famichat.Repo

  import Ecto.Query

  @shortdoc "Lists usernames and highlights fingerprint collisions"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    users =
      from(u in User,
        select: {u.id, u.username, u.username_fingerprint},
        order_by: [asc: u.inserted_at]
      )
      |> Repo.all()

    grouped =
      users
      |> Enum.group_by(fn {_id, username, _fingerprint} ->
        Username.normalize(username)
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
