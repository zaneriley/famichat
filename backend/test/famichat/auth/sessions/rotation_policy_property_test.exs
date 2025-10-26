defmodule Famichat.Auth.Sessions.RotationPolicyPropertyTest do
  use Famichat.DataCase, async: false
  use ExUnitProperties

  alias Famichat.Auth.Sessions
  alias Famichat.Accounts.UserDevice
  alias Famichat.ChatFixtures
  alias Famichat.Repo

  property "refresh rotation accepts current token and rejects stale tokens" do
    check all(rotation_count <- StreamData.integer(1..4)) do
      family = ChatFixtures.family_fixture()
      user = ChatFixtures.user_fixture(%{family_id: family.id})

      device_info = %{
        id: Ecto.UUID.generate(),
        user_agent: "property-test",
        ip: "127.0.0.1"
      }

      {:ok, session} =
        Sessions.start_session(user, device_info, remember_device?: true)

      tokens =
        Enum.reduce(1..rotation_count, [session.refresh_token], fn _, acc ->
          current = List.last(acc)

          Famichat.Cache.clear()

          {:ok, refreshed} =
            Sessions.refresh_session(session.device_id, current)

          refute refreshed.refresh_token in acc
          acc ++ [refreshed.refresh_token]
        end)

      # Latest token continues to work
      {:ok, refreshed} =
        Sessions.refresh_session(session.device_id, List.last(tokens))

      tokens_with_latest = tokens ++ [refreshed.refresh_token]
      refute refreshed.refresh_token in tokens

      # Reusing the previous token triggers reuse detection and revokes the device
      previous = Enum.at(tokens_with_latest, -2)

      assert {:error, :reuse_detected} =
               Sessions.refresh_session(session.device_id, previous)

      device = Repo.get_by!(UserDevice, device_id: session.device_id)
      refute is_nil(device.revoked_at)

      # Once revoked, any token (including stale ones) keeps failing
      Enum.each(tokens_with_latest, fn token ->
        Famichat.Cache.clear()

        assert {:error, :revoked} ==
                 Sessions.refresh_session(session.device_id, token)
      end)
    end
  end
end
