defmodule Famichat.Auth.Sessions.DeviceBindingTest do
  use Famichat.DataCase, async: true

  alias Famichat.Auth.Sessions
  alias Famichat.ChatFixtures

  test "refresh tokens are bound to their device and revoked tokens stay revoked" do
    user = ChatFixtures.user_fixture()

    session1 = start_session(user, "binding-device-1")

    assert {:error, :device_not_found} =
             Sessions.refresh_session("other-device", session1.refresh_token)

    session2 = start_session(user, "binding-device-2")
    tampered_token = tamper(session2.refresh_token)

    assert {:error, :revoked} =
             Sessions.refresh_session(session2.device_id, tampered_token)

    assert {:error, :revoked} =
             Sessions.refresh_session(
               session2.device_id,
               session2.refresh_token
             )

    session3 = start_session(user, "binding-device-3")

    assert {:ok, :revoked} = Sessions.revoke_device(user.id, session3.device_id)

    assert {:error, :invalid} =
             Sessions.verify_access_token(session3.access_token)

    assert {:error, :revoked} =
             Sessions.refresh_session(
               session3.device_id,
               session3.refresh_token
             )
  end

  defp start_session(user, suffix) do
    {:ok, session} =
      Sessions.start_session(
        user,
        %{
          id: "#{suffix}-#{System.unique_integer([:positive])}",
          user_agent: "DeviceBindingTest",
          ip: "127.0.0.1"
        },
        remember_device?: true
      )

    session
  end

  defp tamper(<<first::binary-size(1), rest::binary>>) do
    flipped = if first == "a", do: "b", else: "a"
    flipped <> rest
  end

  defp tamper(token), do: token
end
