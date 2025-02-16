defmodule Famichat.Chat.MessageService do
  @moduledoc """
  Message handling pipeline implementing:
  1. Validation -> 2. Authorization -> 3. Persistence -> 4. Notification
  """
  import Ecto.Query, warn: false
  alias Famichat.{Repo, Telemetry}
  alias Famichat.Chat.{Message, Conversation}

  @max_limit 100
  @default_preloads [:sender, :conversation]

  @doc """
  Pipeline-based message retrieval with structured error handling:

  {:ok, messages} = MessageService.get_conversation_messages(conversation_id,
    limit: 20,
    offset: 0,
    preload: [:sender]
  )
  """
  @spec get_conversation_messages(Ecto.UUID.t(), Keyword.t()) ::
          {:ok, [Message.t()]} | {:error, atom()}
  def get_conversation_messages(conversation_id, opts \\ []) do
    initial_state = %{
      conversation_id: conversation_id,
      opts: opts,
      validated?: false,
      query: nil
    }

    initial_state
    |> validate_conversation_id()
    |> validate_pagination_opts()
    |> check_conversation_exists()
    |> build_base_query()
    |> apply_pagination()
    |> execute_query()
    |> preload_associations()
    |> handle_result()
  end

  defp validate_conversation_id(%{conversation_id: nil} = state) do
    put_in(state.validated?, false)
    |> Map.put(:error, :invalid_conversation_id)
  end

  defp validate_conversation_id(state) do
    put_in(state.validated?, true)
  end

  defp check_conversation_exists(%{error: _} = state), do: state
  defp check_conversation_exists(state) do
    if Repo.exists?(
      from c in Conversation,
      where: c.id == ^state.conversation_id
    ) do
      state
    else
      Map.put(state, :error, :conversation_not_found)
    end
  end

  defp validate_pagination_opts(%{validated?: false} = state), do: state

  defp validate_pagination_opts(state) do
    with {:ok, limit} <- validate_limit(state.opts[:limit]),
         {:ok, offset} <- validate_offset(state.opts[:offset]) do
      state
      |> put_in([:opts, :limit], limit)
      |> put_in([:opts, :offset], offset)
    else
      error -> Map.put(state, :error, error)
    end
  end

  defp build_base_query(%{error: _} = state), do: state

  defp build_base_query(state) do
                query =
                  from m in Message,
        where: m.conversation_id == ^state.conversation_id,
                    order_by: [asc: m.inserted_at]

    Map.put(state, :query, query)
  end

  defp apply_pagination(%{error: _} = state), do: state

  defp apply_pagination(state) do
    state.query
    |> maybe_apply(:limit, state.opts[:limit])
    |> maybe_apply(:offset, state.opts[:offset])
    |> then(&Map.put(state, :query, &1))
  end

  defp execute_query(%{error: _} = state), do: state

  defp execute_query(state) do
    case Repo.all(state.query) do
      [] -> Map.put(state, :result, [])
      messages -> Map.put(state, :result, messages)
    end
  rescue
    _ -> Map.put(state, :error, :query_execution_failed)
  end

  defp preload_associations(%{error: _} = state), do: state

  defp preload_associations(state) do
    preloads = state.opts[:preload] || @default_preloads
    Map.update!(state, :result, &Repo.preload(&1, preloads))
  end

  defp handle_result(%{error: error}), do: {:error, error}
  defp handle_result(%{message: message}), do: {:ok, message}
  defp handle_result(%{result: result}), do: {:ok, result}

  @doc """
  Message creation pipeline:

  {:ok, message} = MessageService.send_message(%{
    sender_id: "uuid",
    conversation_id: "uuid",
    content: "Hello",
    type: :text
  })
  """
  @spec send_message(map()) :: {:ok, Message.t()} | {:error, any()}
  def send_message(params) do
    initial_state = %{
      params: params,
      changeset: nil,
      message: nil
    }

    initial_state
    |> validate_required_fields()
    |> validate_sender()
    |> validate_conversation()
    |> build_changeset()
    |> persist_message()
    |> notify_participants()
    |> handle_result()
  end

  # Private pipeline implementations
  defp validate_required_fields(state) do
    required = [:sender_id, :conversation_id, :content]
    missing = Enum.reject(required, &Map.has_key?(state.params, &1))

    case missing do
      [] -> state
      _ -> Map.put(state, :error, {:missing_fields, missing})
    end
  end

  defp validate_sender(%{error: _} = state), do: state

  defp validate_sender(state) do
    if Repo.exists?(from u in Famichat.Chat.User, where: u.id == ^state.params.sender_id) do
      state
    else
      Map.put(state, :error, :sender_not_found)
    end
  end

  defp validate_conversation(%{error: _} = state), do: state

  defp validate_conversation(state) do
    if Repo.exists?(from c in Conversation, where: c.id == ^state.params.conversation_id) do
      state
    else
      Map.put(state, :error, :conversation_not_found)
    end
  end

  defp build_changeset(%{error: _} = state), do: state

  defp build_changeset(state) do
    changeset =
      %Message{}
      |> Message.changeset(state.params)

    if changeset.valid? do
      Map.put(state, :changeset, changeset)
    else
      Map.put(state, :error, changeset)
    end
  end

  defp persist_message(%{error: _} = state), do: state

  defp persist_message(state) do
    case Repo.insert(state.changeset) do
      {:ok, message} -> Map.put(state, :message, message)
      {:error, reason} -> Map.put(state, :error, reason)
    end
  end

  defp notify_participants(%{error: _} = state), do: state

  defp notify_participants(state) do
    # Placeholder for real notification system
    :telemetry.execute([:famichat, :message, :sent], %{count: 1}, %{
      conversation_id: state.message.conversation_id,
      sender_id: state.message.sender_id
    })
    state
  end

  # Shared helpers
  defp validate_limit(nil), do: {:ok, nil}
  defp validate_limit(limit) when is_integer(limit) and limit > 0 and limit <= @max_limit,
    do: {:ok, limit}

  defp validate_limit(_), do: {:error, :invalid_limit}

  defp validate_offset(nil), do: {:ok, nil}
  defp validate_offset(offset) when is_integer(offset) and offset >= 0, do: {:ok, offset}
  defp validate_offset(_), do: {:error, :invalid_offset}

  defp maybe_apply(query, _clause, nil), do: query
  defp maybe_apply(query, :limit, value), do: from(q in query, limit: ^value)
  defp maybe_apply(query, :offset, value), do: from(q in query, offset: ^value)
end
