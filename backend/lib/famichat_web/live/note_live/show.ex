# lib/famichat_web/live/note_live/show.ex
defmodule FamichatWeb.NoteLive.Show do
  use FamichatWeb, :live_view
  alias FamichatWeb.Router.Helpers, as: Routes
  alias Famichat.Content
  require Logger
  import FamichatWeb.Components.Typography

  @impl true
  def mount(%{"locale" => user_locale}, _session, socket) do
    Gettext.put_locale(FamichatWeb.Gettext, user_locale)
    {:ok, assign(socket, user_locale: user_locale)}
  end

  @dialyzer {:nowarn_function, handle_params: 3}
  @dialyzer {:nowarn_function, set_page_metadata: 2}
  @impl true
  def handle_params(%{"url" => url}, _, socket) do
    case Content.get_with_translations("note", url, socket.assigns.user_locale) do
      {:ok, note, translations, compiled_content} ->
        {page_title, introduction} = set_page_metadata(note, translations)
        Logger.debug("Note translations: #{inspect(translations)}")

        {:noreply,
         assign(socket,
           note: note,
           translations: translations,
           compiled_content: compiled_content,
           page_title: page_title,
           page_description: introduction
         )}

      {:error, :not_found} ->
        raise FamichatWeb.LiveError
    end
  end

  defp set_page_metadata(note, translations) do
    title = translations["title"] || note.title
    introduction = translations["introduction"] || note.introduction

    page_title =
      "#{title} - " <>
        gettext("Note") <>
        " | " <>
        gettext("Zane Riley | Product Design Famichat")

    Logger.debug("Set page title: #{page_title}")
    Logger.debug("Set introduction: #{introduction}")

    {page_title, introduction}
  end
end
