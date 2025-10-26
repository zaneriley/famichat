defmodule Famichat.Auth.Sessions.ContractTest do
  use Famichat.DataCase, async: true

  alias Famichat.Auth.Sessions
  alias Famichat.Accounts.UserDevice
  alias Famichat.ChatFixtures
  alias Famichat.Repo

  test "access verification respects revocation and trust windows" do
    family = ChatFixtures.family_fixture()
    user = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    session =
      Sessions.start_session(
        user,
        %{
          id: "contract-device-#{System.unique_integer([:positive])}",
          user_agent: "SessionsContractTest",
          ip: "127.0.0.1"
        },
        remember_device?: true
      )
      |> assert_ok()

    device_id = session.device_id
    access_token = session.access_token

    assert {:ok, %{user_id: returned_user_id, device_id: ^device_id}} =
             Sessions.verify_access_token(access_token)

    assert returned_user_id == user.id

    refute Sessions.require_reauth?(user.id, device_id, :test)

    device =
      Repo.get_by!(UserDevice,
        user_id: user.id,
        device_id: device_id
      )

    device
    |> change(trusted_until: DateTime.add(DateTime.utc_now(), -60, :second))
    |> Repo.update!()

    assert Sessions.require_reauth?(user.id, device_id, :test)

    assert {:ok, :revoked} = Sessions.revoke_device(user.id, device_id)

    assert {:error, :invalid} = Sessions.verify_access_token(access_token)
  end

  defp assert_ok({:ok, value}), do: value
end
