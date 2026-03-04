defmodule FamichatWeb.AdminLive.SetupLive do
  @moduledoc """
  LiveView for the first-run admin bootstrap flow.

  This is the primary entry point for setting up a fresh Famichat instance.
  No authentication is required — this IS the authentication bootstrap path.

  ## Steps

    1. `:check` (on mount): Checks whether any users exist. If count > 0,
       jumps to `:already_bootstrapped`. Otherwise proceeds to `:bootstrap`.

    2. `:bootstrap`: Form collecting `username` and optional `family_name`.
       On submit calls `Onboarding.bootstrap_admin/2`. On success, assigns
       the passkey_register_token and advances to `:register_passkey`.

    3. `:register_passkey`: Shows a button wired to the `PasskeyAdminSetup`
       JS hook. The hook drives the WebAuthn ceremony, then pushes
       `"register-success"` or `"register-error"` back here.

    4. `:issue_invite`: Shows a "Generate invite link" button. On click calls
       `Onboarding.issue_invite/3`. On success assigns the invite URL and
       advances to `:show_invite`.

    5. `:show_invite`: Displays the full invite URL and options to generate
       another or proceed to login.

    6. `:already_bootstrapped`: Shown when admin already exists.
  """

  use FamichatWeb, :live_view

  require Logger

  import Ecto.Query, only: [from: 2]

  @recoverable_codes ~w(cancelled aborted network passkey_registration_failed
                        challenge_failed invalid_challenge expired used)

  alias Famichat.Accounts.FirstRun
  alias Famichat.Accounts.User
  alias Famichat.Auth.Onboarding
  alias Famichat.Auth.Passkeys
  alias Famichat.Repo

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      mount_connected(socket)
    else
      {:ok,
       socket
       |> assign(:step, :check)
       |> assign(:username, "")
       |> assign(:family_name, "")
       |> assign(:error, nil)
       |> assign(:passkey_register_token, nil)
       |> assign(:admin_user_id, nil)
       |> assign(:family_id, nil)
       |> assign(:invite_url, nil)
       |> assign(:copied, false)
       |> assign_page_metadata(gettext("Set up your family space"))}
    end
  end

  defp mount_connected(socket) do
    count = Repo.one(from(u in User, select: count(u.id)))

    if count > 0 do
      {:ok,
       socket
       |> assign(:step, :already_bootstrapped)
       |> assign(:username, "")
       |> assign(:family_name, "")
       |> assign(:error, nil)
       |> assign(:passkey_register_token, nil)
       |> assign(:admin_user_id, nil)
       |> assign(:family_id, nil)
       |> assign(:invite_url, nil)
       |> assign(:copied, false)
       |> assign_page_metadata(gettext("Set up your family space"))
       |> push_navigate(to: locale_path(socket, "/"))}
    else
      {:ok,
       socket
       |> assign(:step, :bootstrap)
       |> assign(:username, "")
       |> assign(:family_name, "")
       |> assign(:error, nil)
       |> assign(:passkey_register_token, nil)
       |> assign(:admin_user_id, nil)
       |> assign(:family_id, nil)
       |> assign(:invite_url, nil)
       |> assign(:copied, false)
       |> assign_page_metadata(gettext("Set up your family space"))}
    end
  end

  @impl true
  def handle_event("submit-bootstrap", %{"username" => username, "family_name" => family_name}, socket) do
    username = String.trim(username)
    family_name = String.trim(family_name)
    family_name_or_default = if family_name == "", do: "My Family", else: family_name

    case Onboarding.bootstrap_admin(username, %{"family_name" => family_name_or_default}) do
      {:ok, %{user: user, family: family, passkey_register_token: token}} ->
        # Flip the first-run cache so the locale plug stops redirecting here.
        FirstRun.reset_cache()

        {:noreply,
         socket
         |> assign(:step, :register_passkey)
         |> assign(:passkey_register_token, token)
         |> assign(:admin_user_id, user.id)
         |> assign(:family_id, family.id)
         |> assign(:username, user.username)
         |> assign(:error, nil)}

      {:error, :admin_exists} ->
        {:noreply,
         socket
         |> assign(:step, :already_bootstrapped)
         |> assign(:error, nil)}

      {:error, :username_required} ->
        {:noreply, assign(socket, :error, :username_required)}

      {:error, :invalid_input} ->
        {:noreply, assign(socket, :error, :username_too_short)}

      {:error, reason} ->
        Logger.warning("[SetupLive] bootstrap_admin unexpected error: #{inspect(reason)}")
        {:noreply, assign(socket, :error, :unexpected)}
    end
  end

  @impl true
  def handle_event("register-success", _params, socket) do
    {:noreply, assign(socket, :step, :issue_invite)}
  end

  # Recoverable errors — re-issue the passkey token so the button works on the
  # next attempt. If re-issuance reveals the passkey already exists, advance
  # straight to :issue_invite. If re-issuance fails for any other reason, fall
  # through to a fatal display.
  @impl true
  def handle_event(
        "register-error",
        %{"code" => code, "message" => message},
        socket
      )
      when code in @recoverable_codes do
    Logger.info("[SetupLive] Recoverable passkey error (#{code}): #{message}")

    case Onboarding.reissue_passkey_token(socket.assigns.admin_user_id) do
      {:ok, new_token} ->
        {:noreply,
         socket
         |> assign(:passkey_register_token, new_token)
         |> assign(:error, {:retryable, message})}

      {:error, :already_registered} ->
        # The passkey actually enrolled even though the hook reported failure.
        {:noreply, assign(socket, :step, :issue_invite)}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, {:fatal, message})}
    end
  end

  # already_registered — check the database before deciding.
  def handle_event("register-error", %{"code" => "already_registered"}, socket) do
    if Passkeys.has_active_passkey?(socket.assigns.admin_user_id) do
      {:noreply, assign(socket, :step, :issue_invite)}
    else
      {:noreply,
       assign(
         socket,
         :error,
         {:fatal, gettext("A passkey setup conflict occurred. Please reload.")}
       )}
    end
  end

  # Fatal errors — unsupported browser or other non-retriable condition.
  def handle_event("register-error", %{"code" => _code, "message" => message}, socket) do
    Logger.warning("[SetupLive] Fatal passkey error: #{message}")
    {:noreply, assign(socket, :error, {:fatal, message})}
  end

  # Legacy / no-code fallback — treat as retryable.
  def handle_event("register-error", %{"message" => message}, socket) do
    Logger.warning("[SetupLive] Passkey registration error (no code): #{message}")
    {:noreply, assign(socket, :error, {:retryable, message})}
  end

  # Bare catch-all.
  def handle_event("register-error", _params, socket) do
    {:noreply, assign(socket, :error, {:retryable, gettext("Unknown error")})}
  end

  @impl true
  def handle_event("generate_invite", _params, socket) do
    admin_user_id = socket.assigns.admin_user_id
    family_id = socket.assigns.family_id

    if is_nil(admin_user_id) or is_nil(family_id) do
      {:noreply, assign(socket, :error, :not_logged_in)}
    else
      case Onboarding.issue_invite(admin_user_id, nil, %{household_id: family_id, role: "member"}) do
        {:ok, %{invite: invite_token}} ->
          invite_url = "#{base_url()}#{locale_path(socket, "/invites/#{invite_token}")}"

          {:noreply,
           socket
           |> assign(:step, :show_invite)
           |> assign(:invite_url, invite_url)
           |> assign(:error, nil)}

        {:error, reason} ->
          Logger.warning("[SetupLive] issue_invite error: #{inspect(reason)}")
          {:noreply, assign(socket, :error, :invite_failed)}
      end
    end
  end

  @impl true
  def handle_event("generate_another", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :issue_invite)
     |> assign(:invite_url, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("copied", _params, socket) do
    Process.send_after(self(), :reset_copied, 2000)
    {:noreply, assign(socket, :copied, true)}
  end

  @impl true
  def handle_info(:reset_copied, socket) do
    {:noreply, assign(socket, :copied, false)}
  end

  defp base_url do
    FamichatWeb.Endpoint.url()
  end

  defp error_message(:username_required), do: gettext("Please enter your name.")
  defp error_message(:username_too_short), do: gettext("Your name needs to be at least 3 characters.")
  defp error_message(:unexpected), do: gettext("Something went wrong \u2014 please try again.")
  defp error_message(:invite_failed), do: gettext("Could not generate an invite link. Please try again.")
  defp error_message(:not_logged_in), do: gettext("Complete setup first, then you can generate an invite.")
  defp error_message({:retryable, msg}) when is_binary(msg), do: msg
  defp error_message({:fatal, msg}) when is_binary(msg), do: msg
  defp error_message(_), do: gettext("Something went wrong.")
end
