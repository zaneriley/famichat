defmodule Famichat.Accounts.FacadeConformanceTest do
  use Famichat.DataCase, async: false

  alias Famichat.Accounts
  alias Famichat.ChatFixtures
  alias Famichat.Repo
  alias Famichat.Auth.Sessions, as: SessionsContext

  import Ecto.Changeset, only: [change: 2]

  setup do
    family = ChatFixtures.family_fixture()
    user = ChatFixtures.user_fixture(%{family_id: family.id})

    device_info = %{
      id: Ecto.UUID.generate(),
      user_agent: "facade-test",
      ip: "127.0.0.1"
    }

    {:ok, %{user: user, device_info: device_info}}
  end

  describe "session façade parity" do
    test "start_session", %{user: user, device_info: device_info} do
      assert compare_flow(fn mod ->
               mod.start_session(user, device_info, remember_device?: true)
             end)
    end

    test "refresh_session", %{user: user, device_info: device_info} do
      assert compare_flow(fn mod ->
               {:ok, session} =
                 mod.start_session(user, device_info, remember_device?: true)

               mod.refresh_session(session.device_id, session.refresh_token)
             end)
    end

    test "revoke_device", %{user: user, device_info: device_info} do
      assert compare_flow(fn mod ->
               {:ok, session} =
                 mod.start_session(user, device_info, remember_device?: false)

               mod.revoke_device(user.id, session.device_id)
             end)
    end

    test "verify_access_token", %{user: user, device_info: device_info} do
      assert compare_flow(fn mod ->
               {:ok, session} =
                 mod.start_session(user, device_info, remember_device?: true)

               mod.verify_access_token(session.access_token)
             end)
    end

    test "require_reauth?", %{user: user, device_info: device_info} do
      assert compare_flow(fn mod ->
               {:ok, session} =
                 mod.start_session(user, device_info, remember_device?: true)

               mod.require_reauth?(user.id, session.device_id, :test)
             end)

      assert compare_flow(fn mod ->
               {:ok, session} =
                 mod.start_session(user, device_info, remember_device?: true)

               Repo.get_by!(Famichat.Accounts.UserDevice,
                 device_id: session.device_id
               )
               |> change(
                 trusted_until: DateTime.add(DateTime.utc_now(), -1, :second)
               )
               |> Repo.update!()

               mod.require_reauth?(user.id, session.device_id, :test)
             end)
    end
  end

  defp compare_flow(flow_fun) do
    baseline = run_flow(SessionsContext, flow_fun)
    facade = run_flow(Accounts, flow_fun)
    normalize(facade) == normalize(baseline)
  end

  defp run_flow(mod, flow_fun) do
    Famichat.Cache.clear()

    Repo.transaction(fn ->
      result = flow_fun.(mod)
      Repo.rollback({:result, result})
    end)
    |> unwrap_transaction()
  end

  defp normalize({:ok, map}) when is_map(map) do
    {:ok,
     map
     |> Map.drop([:access_token, :refresh_token])
     |> update_trusted_until()}
  end

  defp normalize(other), do: other

  defp update_trusted_until(map) do
    case Map.fetch(map, :trusted_until) do
      {:ok, %DateTime{}} -> Map.put(map, :trusted_until, :normalized)
      _ -> map
    end
  end

  defp unwrap_transaction({:error, {:result, result}}), do: result
  defp unwrap_transaction({:ok, {:result, result}}), do: result
  defp unwrap_transaction(result), do: result
end
