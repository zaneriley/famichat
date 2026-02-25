defmodule Famichat.BoundaryEnforcementTest do
  use ExUnit.Case, async: false

  @moduletag :boundary

  test "boundary definitions remain valid" do
    mix = System.find_executable("mix") || "mix"

    env = [
      {"MIX_ENV", "test"}
      | Enum.reject(System.get_env(), fn {k, _v} -> k == "MIX_ENV" end)
    ]

    command =
      "Mix.Task.run(\"compile.boundary\", [\"--quiet\"]); " <>
        "Mix.Task.reenable(\"boundary.spec\"); " <>
        "Mix.Task.run(\"boundary.spec\", [\"--verify\", \"--quiet\"])"

    {output, exit_code} =
      System.cmd(mix, ["run", "--no-start", "-e", command], env: env)

    assert exit_code == 0, "boundary verification failed:\n#{output}"
  end
end
