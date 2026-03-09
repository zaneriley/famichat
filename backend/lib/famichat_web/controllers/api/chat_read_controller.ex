defmodule FamichatWeb.API.ChatReadController do
  use FamichatWeb, :controller
  import Ecto.Query

  alias Famichat.Repo

  alias Famichat.Chat.{
    Conversation,
    ConversationAccess,
    ConversationService,
    ConversationSummary,
    ConversationVisibilityService,
    MessageService,
    UserReadCursor
  }

  def index_me_conversations(
        %{assigns: %{current_user_id: user_id}} = conn,
        _params
      ) do
    conversations =
      ConversationVisibilityService.list_visible_conversations(user_id,
        preload: [:explicit_users]
      )

    conversation_ids = Enum.map(conversations, & &1.id)

    # Batch-load summaries and cursors in two queries rather than N+1.
    summaries = load_conversation_summaries(conversation_ids)
    cursors = load_user_cursors(user_id, conversation_ids)

    data =
      conversations
      |> Enum.sort_by(
        fn c ->
          summary = Map.get(summaries, c.id)
          last_message_at = if summary, do: summary.last_message_at, else: nil
          last_message_at || c.updated_at
        end,
        {:desc, DateTime}
      )
      |> Enum.map(fn conversation ->
        summary =
          Map.get(summaries, conversation.id, %{
            latest_message_seq: 0,
            last_message_at: nil
          })

        cursor = Map.get(cursors, conversation.id, %{last_acked_seq: 0})
        latest_seq = Map.get(summary, :latest_message_seq, 0)
        acked_seq = Map.get(cursor, :last_acked_seq, 0)
        unread_count = max(0, latest_seq - acked_seq)
        present_conversation(conversation, user_id, summary, unread_count)
      end)

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
            error: %{code: "invalid_pagination"},
            details: format_changeset_errors(changeset)
          })

        {:error, :conversation_not_found} ->
          not_found(conn)

        {:error, {:mls_decryption_failed, :recovery_required, _details}} ->
          conn
          |> put_status(:conflict)
          |> json(%{error: %{code: "recovery_required"}})

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
         summary,
         unread_count
       ) do
    usernames = participant_usernames(conversation)
    last_message_at = Map.get(summary, :last_message_at)
    latest_message_seq = Map.get(summary, :latest_message_seq, 0)

    %{
      "id" => conversation.id,
      "conversation_type" => Atom.to_string(conversation.conversation_type),
      "title" => conversation_title(conversation, usernames, current_user_id),
      "participant_usernames" => usernames,
      "updated_at" => DateTime.to_iso8601(conversation.updated_at),
      "last_message_at" =>
        if(last_message_at, do: DateTime.to_iso8601(last_message_at), else: nil),
      "unread_count" => unread_count,
      "latest_message_seq" => latest_message_seq
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

  defp present_message(message) do
    %{
      "id" => message.id,
      "sender_id" => message.sender_id,
      "content" => message.content,
      "message_seq" => message.message_seq,
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

  defp load_conversation_summaries([]), do: %{}

  defp load_conversation_summaries(conversation_ids) do
    from(cs in ConversationSummary,
      where: cs.conversation_id in ^conversation_ids,
      select: {cs.conversation_id, cs}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp load_user_cursors(_user_id, []), do: %{}

  defp load_user_cursors(user_id, conversation_ids) do
    from(urc in UserReadCursor,
      where:
        urc.user_id == ^user_id and urc.conversation_id in ^conversation_ids,
      select: {urc.conversation_id, urc}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found"}})
  end
end
