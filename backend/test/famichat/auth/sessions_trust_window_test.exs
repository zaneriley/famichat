defmodule Famichat.Auth.Sessions.TrustWindowTest do
  use Famichat.DataCase, async: true

  import Ecto.Changeset
  alias Famichat.Auth.Sessions
  alias Famichat.Accounts.UserDevice
  alias Famichat.ChatFixtures
  alias Famichat.Repo

  test "trusted devices skip reauth until the window expires" do
    user = ChatFixtures.user_fixture()

    {:ok, session} =
      Sessions.start_session(
        user,
        %{
          id: "trust-window-#{System.unique_integer([:positive])}",
          user_agent: "TrustWindowTest",
          ip: "127.0.0.1"
        },
        remember_device?: true
      )

    refute Sessions.require_reauth?(user.id, session.device_id, :any_action)

    session.device_id
    |> fetch_device()
    |> change(trusted_until: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    assert Sessions.require_reauth?(user.id, session.device_id, :any_action)
  end

  test "unremembered devices require immediate reauth" do
    user = ChatFixtures.user_fixture()

    {:ok, session} =
      Sessions.start_session(
        user,
        %{
          id: "trust-window-unremembered-#{System.unique_integer([:positive])}",
          user_agent: "TrustWindowTest",
          ip: "127.0.0.1"
        },
        remember_device?: false
      )

    assert Sessions.require_reauth?(user.id, session.device_id, :any_action)
  end

  defp fetch_device(device_id) do
    Repo.get_by!(UserDevice, device_id: device_id)
  end
end
