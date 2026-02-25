defmodule Mix.Tasks.Famichat.RunbookSeedTest do
  use Famichat.DataCase, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Famichat.RunbookSeed

  setup do
    previous_env = Application.get_env(:famichat, :environment)
    Application.put_env(:famichat, :environment, :test)

    on_exit(fn ->
      Application.put_env(:famichat, :environment, previous_env)
    end)

    :ok
  end

  test "accepts underscore and hyphen options and applies provided values" do
    output =
      capture_io(fn ->
        RunbookSeed.run([
          "--family_name",
          "Red Team Family",
          "--sender-username",
          "red_sender",
          "--receiver_username",
          "red_receiver"
        ])
      end)

    payload = decode_payload(output)

    assert payload["family"]["name"] == "Red Team Family"
    assert payload["sender"]["username"] == "red_sender"
    assert payload["receiver"]["username"] == "red_receiver"
  end

  test "rejects unknown options" do
    assert_raise Mix.Error, ~r/unrecognized options: --bogus/, fn ->
      capture_io(fn ->
        RunbookSeed.run(["--bogus", "value"])
      end)
    end
  end

  test "rejects positional arguments" do
    assert_raise Mix.Error, ~r/unexpected positional arguments: extra/, fn ->
      capture_io(fn ->
        RunbookSeed.run(["extra"])
      end)
    end
  end

  test "rejects blank sender username" do
    assert_raise Mix.Error, ~r/sender_username must be a non-empty string/, fn ->
      capture_io(fn ->
        RunbookSeed.run(["--sender-username", "   "])
      end)
    end
  end

  test "rejects blank family name" do
    assert_raise Mix.Error, ~r/family_name must be a non-empty string/, fn ->
      capture_io(fn ->
        RunbookSeed.run(["--family-name", "   "])
      end)
    end
  end

  test "rejects identical sender and receiver usernames" do
    assert_raise Mix.Error, ~r/sender_username and receiver_username must differ/, fn ->
      capture_io(fn ->
        RunbookSeed.run([
          "--sender_username",
          "same_user",
          "--receiver-username",
          "same_user"
        ])
      end)
    end
  end

  test "rejects non-dev/test environments" do
    Application.put_env(:famichat, :environment, :prod)

    assert_raise Mix.Error, ~r/restricted to dev\/test/, fn ->
      capture_io(fn ->
        RunbookSeed.run([])
      end)
    end
  end

  defp decode_payload(output) do
    output
    |> String.split("\n")
    |> Enum.drop_while(&(not String.starts_with?(&1, "{")))
    |> Enum.join("\n")
    |> Jason.decode!()
  end
end
