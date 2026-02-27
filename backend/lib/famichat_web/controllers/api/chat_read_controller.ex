defmodule FamichatWeb.API.ChatReadController do
  use FamichatWeb, :controller

  import Ecto.Query

  alias Famichat.Chat.{
    Conversation,
    ConversationAccess,
    ConversationService,
    ConversationVisibilityService,
    Message,
    MessageService
  }

  alias Famichat.Repo

  @max_preview_length 120

  def index_me_conversations(
        %{assigns: %{current_user_id: user_id}} = conn,
        _params
      ) do
    conversations =
      ConversationVisibilityService.list_visible_conversations(user_id,
        preload: [:explicit_users]
      )

    preview_map = latest_previews(conversations)

    data =
      conversations
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
      |> Enum.map(&present_conversation(&1, user_id, preview_map))

    json(conn, %{data: data})
  end

  def index_messages(%{assigns: %{current_user_id: user_id}} = conn, params) do
    conversation_id = params["id"]

    with {:ok, _uuid} <- Ecto.UUID.cast(conversation_id),
         :ok <- authorize_message_read(conversation_id, user_id) do
      case MessageService.get_conversation_messages_page(conversation_id,
             limit: params["limit"],
             offset: params["offset"],
             after: params["after"],
             preload: []
           ) do
        {:ok,
         %{messages: messages, has_more: has_more, next_cursor: next_cursor}} ->
          data = Enum.map(messages, &present_message/1)

          json(conn, %{
            data: data,
            meta: %{has_more: has_more, next_cursor: next_cursor}
          })

        {:error, {:invalid_pagination, changeset}} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error: "invalid_pagination",
            details: format_changeset_errors(changeset)
          })

        {:error, :conversation_not_found} ->
          not_found(conn)

        {:error, _reason} ->
          not_found(conn)
      end
    else
      :error ->
        not_found(conn)

      {:error, :not_found} ->
        not_found(conn)
    end
  end

  defp authorize_message_read(conversation_id, user_id) do
    case ConversationAccess.authorize(conversation_id, user_id, :send_message) do
      :ok -> :ok
      {:error, _reason} -> {:error, :not_found}
    end
  end

  defp present_conversation(
         %Conversation{} = conversation,
         current_user_id,
         preview_map
       ) do
    usernames = participant_usernames(conversation)

    %{
      "id" => conversation.id,
      "conversation_type" => Atom.to_string(conversation.conversation_type),
      "title" => conversation_title(conversation, usernames, current_user_id),
      "participant_usernames" => usernames,
      "updated_at" => DateTime.to_iso8601(conversation.updated_at),
      "last_message_preview" => Map.get(preview_map, conversation.id)
    }
  end

  defp participant_usernames(%Conversation{explicit_users: users})
       when is_list(users) and users != [] do
    users
    |> Enum.map(& &1.username)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp participant_usernames(conversation) do
    conversation
    |> ConversationService.list_members()
    |> Enum.map(& &1.username)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp conversation_title(
         %Conversation{conversation_type: :direct} = conversation,
         usernames,
         current_user_id
       ) do
    conversation
    |> direct_other_username(current_user_id)
    |> case do
      nil -> fallback_title(conversation, usernames)
      other_username -> other_username
    end
  end

  defp conversation_title(conversation, usernames, _current_user_id) do
    fallback_title(conversation, usernames)
  end

  defp fallback_title(
         %Conversation{conversation_type: :group, metadata: metadata},
         usernames
       ) do
    Map.get(metadata || %{}, "name") || Enum.join(usernames, ", ")
  end

  defp fallback_title(%Conversation{conversation_type: :family}, _usernames),
    do: "Family"

  defp fallback_title(%Conversation{conversation_type: :self}, _usernames),
    do: "My Notes"

  defp fallback_title(conversation, usernames) do
    case List.first(usernames) do
      nil -> String.capitalize(Atom.to_string(conversation.conversation_type))
      first -> first
    end
  end

  defp direct_other_username(conversation, current_user_id) do
    conversation.explicit_users
    |> List.wrap()
    |> Enum.find(fn user -> user.id != current_user_id end)
    |> case do
      nil -> nil
      other -> other.username
    end
  end

  defp latest_previews([]), do: %{}

  defp latest_previews(conversations) do
    ids = Enum.map(conversations, & &1.id)

    query =
      from m in Message,
        where: m.conversation_id in ^ids,
        order_by: [desc: m.inserted_at, desc: m.id],
        distinct: m.conversation_id,
        select: {m.conversation_id, m.content}

    query
    |> Repo.all()
    |> Map.new(fn {conversation_id, content} ->
      {conversation_id, truncate_preview(content)}
    end)
  end

  defp truncate_preview(nil), do: nil

  defp truncate_preview(content) do
    content
    |> String.trim()
    |> case do
      "" ->
        nil

      trimmed ->
        if String.length(trimmed) > @max_preview_length do
          String.slice(trimmed, 0, @max_preview_length)
        else
          trimmed
        end
    end
  end

  defp present_message(message) do
    %{
      "id" => message.id,
      "sender_id" => message.sender_id,
      "content" => message.content,
      "inserted_at" => DateTime.to_iso8601(message.inserted_at)
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end
end
