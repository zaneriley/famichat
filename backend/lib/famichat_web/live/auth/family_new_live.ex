defmodule FamichatWeb.AuthLive.FamilyNewLive do
  @moduledoc """
  LiveView for self-service family creation from the front door.

  Reached via /:locale/families/new — no auth required. Handles only step 1:
  collecting a family name and creating the family + setup token. On success,
  redirects to /:locale/families/start/:token, which is `FamilySetupLive`.

  This redirect is the reconnect fix: FamilySetupLive receives the token via
  URL params, so it survives WebSocket disconnect/reconnect. Keeping the token
  only in LiveView assigns (the old approach) meant mobile users on cellular
  would lose their progress on any network interruption.
  """
  use FamichatWeb, :live_view

  require Logger

  alias Famichat.Auth.Onboarding

  @impl true
  def mount(_params, session, socket) do
    unless Application.get_env(:famichat, :registration_open, false) do
      {:ok, push_navigate(socket, to: locale_path(socket, "/login"))}
    else
      remote_ip = Map.get(session, "remote_ip", "unknown")

      {:ok,
       socket
       |> assign(:step, :family_name)
       |> assign(:family_name, "")
       |> assign(:error, nil)
       |> assign(:remote_ip, remote_ip)
       |> assign_page_metadata(gettext("Set up your family space"))}
    end
  end

  @impl true
  def handle_event(
        "submit-family-name",
        %{"family_name" => family_name},
        socket
      ) do
    case Onboarding.create_family_self_service(family_name, %{
           remote_ip: socket.assigns.remote_ip
         }) do
      {:ok, %{setup_token: raw_token}} ->
        # Redirect to the token-gated setup flow. FamilySetupLive handles
        # steps 2-4 (username, passkey, success) and survives reconnects
        # because the token is in the URL.
        {:noreply,
         push_navigate(socket,
           to: locale_path(socket, "/families/start/#{raw_token}")
         )}

      {:error, :family_name_required} ->
        {:noreply, assign(socket, :error, :family_name_required)}

      {:error, :family_name_too_long} ->
        {:noreply, assign(socket, :error, :family_name_too_long)}

      {:error, {:rate_limited, _retry_in}} ->
        {:noreply, assign(socket, :error, :rate_limited)}

      {:error, %Ecto.Changeset{} = changeset} ->
        if family_name_taken?(changeset) do
          {:noreply, assign(socket, :error, :family_name_taken)}
        else
          Logger.warning(
            "[FamilyNewLive] create_family_self_service changeset error: #{inspect(changeset)}"
          )

          {:noreply, assign(socket, :error, :unexpected)}
        end

      {:error, reason} ->
        Logger.warning(
          "[FamilyNewLive] create_family_self_service error: #{inspect(reason)}"
        )

        {:noreply, assign(socket, :error, :unexpected)}
    end
  end

  # -- Error messages --------------------------------------------------------

  defp error_message(:family_name_required),
    do: gettext("Please enter a family name.")

  defp error_message(:family_name_too_long),
    do: gettext("Family name must be 100 characters or fewer.")

  defp error_message(:family_name_taken),
    do: gettext("That family name is already taken. Try something else.")

  defp error_message(:rate_limited),
    do:
      gettext(
        "Too many family spaces created from this network. Try again in a few minutes."
      )

  defp error_message(:unexpected),
    do: gettext("Something went wrong. Please try again.")

  defp error_message(_), do: gettext("Something went wrong.")

  # -- Helpers ---------------------------------------------------------------

  defp family_name_taken?(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {_msg, opts} -> opts end)
    |> Map.get(:name, [])
    |> Enum.any?(&(Keyword.get(&1, :constraint) == :unique))
  end
end
