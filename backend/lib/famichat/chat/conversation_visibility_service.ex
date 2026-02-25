defmodule Famichat.Chat.ConversationVisibilityService do
  @moduledoc """
  Service module for managing conversation visibility.

  This module provides functions for hiding and unhiding conversations
  for specific users, implementing a soft-delete mechanism that preserves
  the conversation data while removing it from a user's view.
  """

  import Ecto.Query
  alias Famichat.Repo
  alias Famichat.Chat.{Conversation, ConversationQueries}

  @doc """
  Hides a conversation for a specific user.

  ## Parameters
    - conversation_id: The ID of the conversation to hide
    - user_id: The ID of the user hiding the conversation

  ## Returns
    - {:ok, %Conversation{}} - The updated conversation with the user added to hidden_by_users
    - {:error, :not_found} - If the conversation doesn't exist
    - {:error, %Ecto.Changeset{}} - If the update failed
  """
  def hide_conversation(conversation_id, user_id) do
    :telemetry.span(
      [:famichat, :conversation_visibility_service, :hide_conversation],
      %{conversation_id: conversation_id, user_id: user_id},
      fn ->
        start_time = System.monotonic_time()

        result = do_hide_conversation(conversation_id, user_id)

        end_time = System.monotonic_time()

        {result,
         %{
           duration: end_time - start_time,
           result: result_to_telemetry_value(result)
         }}
      end
    )
  end

  defp do_hide_conversation(conversation_id, user_id) do
    case Repo.get(Conversation, conversation_id) do
      nil ->
        {:error, :not_found}

      conversation ->
        # Only add the user_id if it's not already in the list
        if user_id in conversation.hidden_by_users do
          {:ok, conversation}
        else
          conversation
          |> Conversation.update_changeset(%{
            hidden_by_users: conversation.hidden_by_users ++ [user_id]
          })
          |> Repo.update()
        end
    end
  end

  @doc """
  Unhides a conversation for a specific user.

  ## Parameters
    - conversation_id: The ID of the conversation to unhide
    - user_id: The ID of the user unhiding the conversation

  ## Returns
    - {:ok, %Conversation{}} - The updated conversation with the user removed from hidden_by_users
    - {:error, :not_found} - If the conversation doesn't exist
    - {:error, %Ecto.Changeset{}} - If the update failed
  """
  def unhide_conversation(conversation_id, user_id) do
    :telemetry.span(
      [:famichat, :conversation_visibility_service, :unhide_conversation],
      %{conversation_id: conversation_id, user_id: user_id},
      fn ->
        start_time = System.monotonic_time()

        result = do_unhide_conversation(conversation_id, user_id)

        end_time = System.monotonic_time()

        {result,
         %{
           duration: end_time - start_time,
           result: result_to_telemetry_value(result)
         }}
      end
    )
  end

  defp do_unhide_conversation(conversation_id, user_id) do
    case Repo.get(Conversation, conversation_id) do
      nil ->
        {:error, :not_found}

      conversation ->
        # Only remove the user_id if it's in the list
        if user_id in conversation.hidden_by_users do
          conversation
          |> Conversation.update_changeset(%{
            hidden_by_users:
              Enum.reject(conversation.hidden_by_users, &(&1 == user_id))
          })
          |> Repo.update()
        else
          {:ok, conversation}
        end
    end
  end

  @doc """
  Lists all non-hidden conversations for a specific user.

  ## Parameters
    - user_id: The ID of the user
    - opts: Optional parameters
      - :preload - List of associations to preload

  ## Returns
    - List of conversations that aren't hidden by the user
  """
  def list_visible_conversations(user_id, opts \\ []) do
    # Ensure we have a UUID string that can be cast across all query paths.
    user_id = ensure_uuid_string(user_id)

    :telemetry.span(
      [
        :famichat,
        :conversation_visibility_service,
        :list_visible_conversations
      ],
      %{user_id: user_id},
      fn ->
        start_time = System.monotonic_time()

        result = do_list_visible_conversations(user_id, opts)

        end_time = System.monotonic_time()

        {result,
         %{
           duration: end_time - start_time,
           conversation_count: length(result)
         }}
      end
    )
  end

  defp do_list_visible_conversations(user_id, opts) do
    query =
      from c in ConversationQueries.for_user(user_id),
        where:
          fragment(
            "? != ALL(?)",
            type(^user_id, :binary_id),
            c.hidden_by_users
          ),
        select: c

    query
    |> maybe_preload(opts[:preload])
    |> Repo.all()
  end

  # Helper function to optionally preload associations
  defp maybe_preload(query, nil), do: query

  defp maybe_preload(query, preloads) do
    normalized_preloads =
      preloads
      |> List.wrap()
      |> Enum.map(&normalize_preload/1)

    from(q in query, preload: ^normalized_preloads)
  end

  defp normalize_preload(:participants), do: :explicit_participants
  defp normalize_preload(:users), do: :explicit_users
  defp normalize_preload(other), do: other

  # Helper function to convert result to telemetry-friendly value
  defp result_to_telemetry_value({:ok, _}), do: :success
  defp result_to_telemetry_value({:error, :not_found}), do: :not_found
  defp result_to_telemetry_value({:error, _}), do: :error

  # Ensures a UUID is in canonical string form for Ecto query casting.
  defp ensure_uuid_string(uuid) when is_binary(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, cast_uuid} -> cast_uuid
      :error -> raise ArgumentError, "Invalid UUID format: #{inspect(uuid)}"
    end
  end

  defp ensure_uuid_string(uuid), do: uuid
end
