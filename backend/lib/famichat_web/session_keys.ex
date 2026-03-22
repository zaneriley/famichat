defmodule FamichatWeb.SessionKeys do
  @moduledoc """
  Canonical Plug session keys used across the web layer.
  """

  @spec access_token() :: :access_token
  def access_token, do: :access_token

  @spec refresh_token() :: :refresh_token
  def refresh_token, do: :refresh_token

  @spec device_id() :: :device_id
  def device_id, do: :device_id

  @spec user_locale() :: :user_locale
  def user_locale, do: :user_locale

  @spec active_family_id() :: :active_family_id
  def active_family_id, do: :active_family_id

  @spec redirect_count() :: :redirect_count
  def redirect_count, do: :redirect_count

  @spec invite_token() :: :invite_token
  def invite_token, do: :invite_token

  @spec all_keys() :: [
          :access_token
          | :refresh_token
          | :device_id
          | :user_locale
          | :active_family_id
          | :redirect_count
          | :invite_token
        ]
  def all_keys do
    [
      access_token(),
      refresh_token(),
      device_id(),
      user_locale(),
      active_family_id(),
      redirect_count(),
      invite_token()
    ]
  end
end
