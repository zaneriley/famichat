defmodule Famichat.Auth.Sessions.RotationPolicy do
  @moduledoc false

  alias Famichat.Accounts.UserDevice
  alias Famichat.Auth.Infra.Tokens
  alias Famichat.Auth.Sessions.Device
  alias Famichat.Repo

  @spec verify_and_rotate(
          UserDevice.t(),
          String.t(),
          (Famichat.Accounts.User.t(), UserDevice.t() ->
             {:ok, map(), Ecto.UUID.t(), UserDevice.t()})
        ) ::
          {:ok, map(), Ecto.UUID.t(), UserDevice.t()}
          | {:reuse_detected, Ecto.UUID.t()}
          | {:error, term()}
  def verify_and_rotate(%UserDevice{} = device, raw_refresh, issue_fun)
      when is_function(issue_fun, 2) do
    Repo.transaction(fn ->
      device_with_user = Repo.preload(device, :user)
      hash = Tokens.hash(raw_refresh)

      cond do
        secure_compare(device_with_user.refresh_token_hash, hash) ->
          issue_fun.(device_with_user.user, device_with_user)

        secure_compare(device_with_user.previous_token_hash, hash) ->
          {:ok, _} = Device.revoke(device_with_user)

          telemetry(:revoke, %{
            user_id: device_with_user.user_id,
            device_id: device_with_user.device_id
          })

          {:reuse_detected, device_with_user.user_id}

        true ->
          revoke_invalid(device_with_user)
      end
    end)
    |> handle_transaction_result()
  end

  defp revoke_invalid(%UserDevice{} = device) do
    case Device.revoke(device) do
      {:ok, _} ->
        telemetry(:revoke, %{
          user_id: device.user_id,
          device_id: device.device_id
        })

        {:revoked, device.user_id}

      {:error, changeset} ->
        {:revoke_failed, changeset}
    end
  end

  defp handle_transaction_result({:ok, {:ok, tokens, user_id, updated_device}}),
    do: {:ok, tokens, user_id, updated_device}

  defp handle_transaction_result({:ok, {:reuse_detected, user_id}}),
    do: {:reuse_detected, user_id}

  defp handle_transaction_result({:ok, {:revoked, _user_id}}),
    do: {:error, :revoked}

  defp handle_transaction_result({:ok, {:revoke_failed, changeset}}),
    do: {:error, {:revoke_failed, changeset}}

  defp handle_transaction_result({:error, reason}),
    do: {:error, reason}

  defp secure_compare(a, b) when is_binary(a) and is_binary(b),
    do: Plug.Crypto.secure_compare(a, b)

  defp secure_compare(_, _), do: false

  defp telemetry(action, metadata),
    do:
      :telemetry.execute(
        [:famichat, :auth, :session, action],
        %{count: 1},
        metadata
      )
end
