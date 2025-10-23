defmodule Famichat.Auth.Sessions.Device do
  @moduledoc false

  alias Famichat.Accounts.{User, UserDevice}
  alias Famichat.Repo

  @spec normalize_info(map()) ::
          {:ok,
           %{id: String.t(), user_agent: String.t() | nil, ip: String.t() | nil}}
          | {:error, :invalid_device_info}
  def normalize_info(device_info) when is_map(device_info) do
    id = device_attr(device_info, :id)

    if is_binary(id) do
      {:ok,
       %{
         id: id,
         user_agent: device_attr(device_info, :user_agent),
         ip: device_attr(device_info, :ip)
       }}
    else
      {:error, :invalid_device_info}
    end
  end

  def normalize_info(_), do: {:error, :invalid_device_info}

  @spec upsert(User.t(), map(), boolean(), pos_integer()) ::
          {:ok, UserDevice.t()} | {:error, term()}
  def upsert(%User{id: user_id}, %{id: id} = info, remember?, refresh_ttl) do
    attrs = %{
      user_id: user_id,
      device_id: id,
      user_agent: Map.get(info, :user_agent),
      ip: Map.get(info, :ip),
      trusted_until: trusted_until(remember?, refresh_ttl),
      last_active_at: DateTime.utc_now()
    }

    case Repo.get_by(UserDevice, device_id: id) do
      nil ->
        %UserDevice{}
        |> UserDevice.changeset(Map.put(attrs, :refresh_token_hash, nil))
        |> Repo.insert()

      %UserDevice{} = device ->
        device
        |> UserDevice.changeset(attrs)
        |> Repo.update()
    end
  end

  @spec fetch(String.t()) :: {:ok, UserDevice.t()} | {:error, :device_not_found}
  def fetch(device_id) do
    case Repo.get_by(UserDevice, device_id: device_id) do
      %UserDevice{} = device -> {:ok, device}
      nil -> {:error, :device_not_found}
    end
  end

  @spec revoke(UserDevice.t(), map()) ::
          {:ok, UserDevice.t()} | {:error, Ecto.Changeset.t()}
  def revoke(%UserDevice{} = device, attrs \\ %{}) do
    device
    |> UserDevice.changeset(
      Map.merge(
        %{
          revoked_at: DateTime.utc_now(),
          refresh_token_hash: nil,
          previous_token_hash: nil
        },
        attrs
      )
    )
    |> Repo.update()
  end

  defp trusted_until(true, refresh_ttl),
    do: DateTime.add(DateTime.utc_now(), refresh_ttl, :second)

  defp trusted_until(_remember?, _refresh_ttl), do: nil

  defp device_attr(map, key),
    do: Map.get(map, key) || Map.get(map, to_string(key))
end
