defmodule FamichatWeb.AuthLive.FamilySetupLive do
  @moduledoc """
  LiveView for the community-admin family setup link flow.

  Reached via /:locale/families/start/:token, which is issued by a community
  admin from the admin panel. The token is a one-time :family_setup token
  that carries the pre-created family_id and family_name.

  ## Steps
    1. :check — SSR-only spinner
    2. :invalid — expired/used/missing token
    3. :register — username form; calls complete_family_setup/2
    4. :passkey — WebAuthn ceremony (PasskeyRegister hook)
    5. :success — 1.5s then push_navigate to /login (passkey ceremony
       does not auto-create a session at MLP; user must sign in)
  """
  use FamichatWeb, :live_view

  require Logger

  alias Famichat.Auth.Onboarding
  alias Famichat.Auth.Passkeys

  @recoverable_codes ~w(cancelled aborted network passkey_registration_failed
                        challenge_failed invalid_challenge expired used)

  @impl true
  def mount(%{"token" => raw_token}, _session, socket) do
    if connected?(socket) do
      mount_connected(raw_token, socket)
    else
      {:ok,
       socket
       |> assign(:step, :check)
       |> assign(:token, raw_token)
       |> assign(:family_name, nil)
       |> assign(:error, nil)
       |> assign(:username, "")
       |> assign(:passkey_register_token, nil)
       |> assign(:user_id, nil)}
    end
  end

  defp mount_connected(raw_token, socket) do
    case Onboarding.validate_family_setup_token(raw_token) do
      {:ok, %{"family_name" => family_name} = payload} ->
        {:ok, assign_register_step(socket, raw_token, payload)}

      {:error, :used} ->
        # Reconnect after the token was consumed by complete_family_setup/2.
        # Recover state without re-consuming, mirroring InviteLive's peek pattern.
        case Onboarding.peek_family_setup(raw_token) do
          {:ok, %{user: user, passkey_register_token: passkey_token} = result} ->
            # User was created — resume at passkey step
            {:ok,
             socket
             |> assign(:step, :passkey)
             |> assign(:token, raw_token)
             |> assign(:family_name, result.payload["family_name"])
             |> assign(:error, nil)
             |> assign(:username, user.username || "")
             |> assign(:passkey_register_token, passkey_token)
             |> assign(:user_id, user.id)
             |> assign_page_metadata(gettext("Complete your setup"))}

          {:ok, %{payload: payload}} ->
            # Token consumed but no user yet — show register step
            {:ok, assign_register_step(socket, raw_token, payload)}

          {:error, :already_completed} ->
            {:ok, assign_invalid_step(socket, :already_completed)}

          {:error, reason} ->
            {:ok, assign_invalid_step(socket, reason)}
        end

      {:error, reason} when reason in [:expired, :invalid] ->
        {:ok, assign_invalid_step(socket, reason)}
    end
  end

  defp assign_register_step(socket, raw_token, payload) do
    socket
    |> assign(:step, :register)
    |> assign(:token, raw_token)
    |> assign(:family_name, payload["family_name"])
    |> assign(:error, nil)
    |> assign(:username, "")
    |> assign(:passkey_register_token, nil)
    |> assign(:user_id, nil)
    |> assign_page_metadata(gettext("Complete your setup"))
  end

  defp assign_invalid_step(socket, reason) do
    socket
    |> assign(:step, :invalid)
    |> assign(:error, reason)
    |> assign(:token, nil)
    |> assign(:family_name, nil)
    |> assign(:username, "")
    |> assign(:passkey_register_token, nil)
    |> assign(:user_id, nil)
    |> assign_page_metadata(gettext("Setup link not available"))
  end

  @impl true
  def handle_event("submit-username", %{"username" => username}, socket) do
    username = String.trim(username)

    cond do
      username == "" ->
        {:noreply, assign(socket, :error, :username_required)}

      String.length(username) < 2 ->
        {:noreply,
         socket
         |> assign(:error, :username_too_short)
         |> assign(:username, username)}

      String.length(username) > 50 ->
        {:noreply,
         socket
         |> assign(:error, :username_too_long)
         |> assign(:username, username)}

      true ->
        case Onboarding.complete_family_setup(socket.assigns.token, %{
               "username" => username
             }) do
          {:ok, %{user: user, passkey_register_token: token}} ->
            {:noreply,
             socket
             |> assign(:step, :passkey)
             |> assign(:username, username)
             |> assign(:user_id, user.id)
             |> assign(:passkey_register_token, token)
             |> assign(:error, nil)}

          {:error, :used_setup_token} ->
            {:noreply, assign(socket, step: :invalid, error: :used)}

          {:error, :expired_setup_token} ->
            {:noreply, assign(socket, step: :invalid, error: :expired)}

          {:error, :username_taken} ->
            {:noreply,
             socket
             |> assign(:error, :username_taken)
             |> assign(:username, username)}

          {:error, reason} ->
            Logger.warning(
              "[FamilySetupLive] complete_family_setup error: #{inspect(reason)}"
            )

            {:noreply, assign(socket, :error, :unexpected)}
        end
    end
  end

  @impl true
  def handle_event("register-success", _params, socket) do
    Process.send_after(self(), :redirect_home, 1500)
    {:noreply, assign(socket, :step, :success)}
  end

  @impl true
  def handle_event("register-error", %{"code" => code, "message" => msg}, socket)
      when code in @recoverable_codes do
    Logger.info("[FamilySetupLive] Recoverable passkey error (#{code}): #{msg}")

    case Onboarding.reissue_passkey_token(socket.assigns.user_id) do
      {:ok, new_token} ->
        {:noreply,
         socket
         |> assign(:passkey_register_token, new_token)
         |> assign(:error, {:recoverable, msg})}

      {:error, :already_registered} ->
        Process.send_after(self(), :redirect_home, 1500)
        {:noreply, assign(socket, :step, :success)}

      {:error, _} ->
        {:noreply, assign(socket, :error, {:fatal, msg})}
    end
  end

  def handle_event("register-error", %{"code" => "already_registered"}, socket) do
    if Passkeys.has_active_passkey?(socket.assigns.user_id) do
      Process.send_after(self(), :redirect_home, 1500)
      {:noreply, assign(socket, :step, :success)}
    else
      {:noreply,
       assign(socket, :error, {:fatal, gettext("A passkey conflict occurred. Please reload.")})}
    end
  end

  def handle_event("register-error", %{"code" => _code, "message" => msg}, socket) do
    {:noreply, assign(socket, :error, {:fatal, msg})}
  end

  def handle_event("register-error", %{"message" => msg}, socket) do
    {:noreply, assign(socket, :error, {:recoverable, msg})}
  end

  def handle_event("register-error", _params, socket) do
    {:noreply, assign(socket, :error, {:recoverable, gettext("Unknown error")})}
  end

  @impl true
  def handle_info(:redirect_home, socket) do
    {:noreply, push_navigate(socket, to: locale_path(socket, "/login"))}
  end

  defp error_message(:expired),
    do: gettext("This setup link has expired. Ask the person who sent it to generate a new one.")

  defp error_message(:used),
    do: gettext("This setup link has already been used.")

  defp error_message(:already_completed),
    do: gettext("This family has already been set up. You can sign in.")

  defp error_message(:invalid),
    do: gettext("This setup link is not valid.")

  defp error_message(:username_required),
    do: gettext("Please enter a name.")

  defp error_message(:username_too_short),
    do: gettext("Name must be at least 2 characters.")

  defp error_message(:username_too_long),
    do: gettext("Name must be 50 characters or fewer.")

  defp error_message(:username_taken),
    do: gettext("That name is already taken. Please choose a different one.")

  defp error_message(:unexpected),
    do: gettext("Something went wrong. Please try again.")

  defp error_message({:recoverable, msg}) when is_binary(msg), do: msg
  defp error_message({:fatal, msg}) when is_binary(msg), do: msg
  defp error_message(_), do: gettext("Something went wrong.")
end
