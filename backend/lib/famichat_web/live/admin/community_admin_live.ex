defmodule FamichatWeb.AdminLive.CommunityAdminLive do
  @moduledoc """
  LiveView for the community admin panel.

  Allows authenticated community admins to list families, create new families,
  and issue/re-issue family setup links. Requires authentication via the
  `:require_authenticated` on_mount callback.

  ## Steps
    1. :loading — SSR spinner
    2. :dashboard — Family list + "Add a family" button
    3. :create_family — Family name form
    4. :show_setup_link — Displays the setup URL; offers copy
    5. :unauthorized — Caller is not an admin of any household
  """
  use FamichatWeb, :live_view

  require Logger

  alias Famichat.Accounts.User
  alias Famichat.Auth.Onboarding
  alias Famichat.Chat.Family
  alias Famichat.Repo

  import Ecto.Query, only: [from: 2]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      mount_connected(socket)
    else
      {:ok,
       socket
       |> assign(:step, :loading)
       |> assign(:families, [])
       |> assign(:error, nil)
       |> assign(:setup_url, nil)
       |> assign(:created_family, nil)
       |> assign(:family_name, "")}
    end
  end

  defp mount_connected(socket) do
    current_user_id = socket.assigns[:current_user_id]

    if is_nil(current_user_id) do
      {:ok,
       socket
       |> assign(:step, :unauthorized)
       |> assign(:error, :not_authenticated)}
    else
      case check_admin_status(current_user_id) do
        true ->
          families = list_families()

          {:ok,
           socket
           |> assign(:step, :dashboard)
           |> assign(:families, families)
           |> assign(:error, nil)
           |> assign(:setup_url, nil)
           |> assign(:created_family, nil)
           |> assign(:family_name, "")
           |> assign_page_metadata(gettext("Your families"))}

        false ->
          {:ok,
           socket
           |> assign(:step, :unauthorized)
           |> assign(:error, :not_community_admin)
           |> assign_page_metadata(gettext("Not authorized"))}
      end
    end
  end

  @impl true
  def handle_event("show_create_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :create_family)
     |> assign(:family_name, "")
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("cancel_create", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :dashboard)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("generate_setup_link", %{"family_name" => name}, socket) do
    case Onboarding.create_family_with_setup_link(
           socket.assigns.current_user_id,
           name
         ) do
      {:ok, %{family: family, setup_url_token: token}} ->
        setup_url =
          "#{base_url()}#{locale_path(socket, "/families/start/#{token}")}"

        families = list_families()

        {:noreply,
         socket
         |> assign(:step, :show_setup_link)
         |> assign(:setup_url, setup_url)
         |> assign(:created_family, family)
         |> assign(:families, families)
         |> assign(:error, nil)}

      {:error, :family_name_required} ->
        {:noreply, assign(socket, :error, :family_name_required)}

      {:error, :family_name_too_long} ->
        {:noreply, assign(socket, :error, :family_name_too_long)}

      {:error, :not_community_admin} ->
        {:noreply,
         assign(socket, step: :unauthorized, error: :not_community_admin)}

      {:error, reason} ->
        Logger.warning(
          "[CommunityAdminLive] create_family error: #{inspect(reason)}"
        )

        {:noreply, assign(socket, :error, :unexpected)}
    end
  end

  @impl true
  def handle_event("reissue_setup_link", %{"family_id" => family_id}, socket) do
    case Onboarding.issue_family_setup_link_for_existing_family(
           socket.assigns.current_user_id,
           family_id
         ) do
      {:ok, %{setup_url_token: token}} ->
        setup_url =
          "#{base_url()}#{locale_path(socket, "/families/start/#{token}")}"

        family = Repo.get(Family, family_id)

        {:noreply,
         socket
         |> assign(:step, :show_setup_link)
         |> assign(:setup_url, setup_url)
         |> assign(:created_family, family)
         |> assign(:error, nil)}

      {:error, reason} ->
        Logger.warning(
          "[CommunityAdminLive] reissue_setup_link error: #{inspect(reason)}"
        )

        {:noreply, assign(socket, :error, :unexpected)}
    end
  end

  @impl true
  def handle_event("back_to_dashboard", _params, socket) do
    families = list_families()

    {:noreply,
     socket
     |> assign(:step, :dashboard)
     |> assign(:families, families)
     |> assign(:error, nil)
     |> assign(:setup_url, nil)
     |> assign(:created_family, nil)}
  end

  defp check_admin_status(user_id) do
    Repo.exists?(
      from(u in User,
        where: u.id == ^user_id and u.community_admin == true and u.status == :active
      )
    )
  end

  defp list_families do
    from(f in Family,
      left_join: m in assoc(f, :memberships),
      group_by: f.id,
      select: %{
        id: f.id,
        name: f.name,
        member_count: count(m.id),
        inserted_at: f.inserted_at
      },
      order_by: [asc: f.inserted_at]
    )
    |> Repo.all()
  end

  defp base_url do
    FamichatWeb.Endpoint.url()
  end

  defp error_message(:family_name_required),
    do: gettext("Please enter a family name.")

  defp error_message(:family_name_too_long),
    do: gettext("Family name must be 100 characters or fewer.")

  defp error_message(:not_community_admin),
    do: gettext("This page is only accessible to the bootstrap admin.")

  defp error_message(:not_authenticated),
    do: gettext("Please sign in to access this page.")

  defp error_message(:unexpected),
    do: gettext("Something went wrong. Please try again.")

  defp error_message(_), do: gettext("Something went wrong.")
end
