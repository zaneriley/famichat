defmodule FamichatWeb.SpikeStartLive do
  use FamichatWeb, :live_view

  @default_locale "en"

  @impl true
  def mount(params, _session, socket) do
    locale = params |> Map.get("locale", @default_locale) |> normalize_locale()
    actors = actor_links(locale)

    {:ok, assign(socket, locale: locale, actors: actors)}
  end

  defp actor_links(locale) do
    [
      actor(
        "You (primary)",
        "zane",
        "main",
        locale,
        revoke_target: stable_device_id("zane", "device-2")
      ),
      actor(
        "You (device 2)",
        "zane",
        "device-2",
        locale
      ),
      actor(
        "Wife (primary)",
        "wife",
        "main",
        locale
      ),
      actor(
        "Wife (device 2)",
        "wife",
        "device-2",
        locale
      )
    ]
  end

  defp actor(label, user, device, locale, opts \\ []) do
    revoke_target = Keyword.get(opts, :revoke_target)

    params =
      [{"user", user}, {"device", device}] ++
        if is_binary(revoke_target), do: [{"revoke_target", revoke_target}], else: []

    %{
      label: label,
      user: user,
      device: device,
      device_id: stable_device_id(user, device),
      path: "/#{locale}?#{URI.encode_query(params)}"
    }
  end

  defp stable_device_id(user, device) do
    "spike-#{user}-#{device}"
  end

  defp normalize_locale(locale) when locale in ["en", "ja"], do: locale
  defp normalize_locale(_), do: @default_locale
end
