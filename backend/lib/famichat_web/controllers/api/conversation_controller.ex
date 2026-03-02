defmodule FamichatWeb.API.ConversationController do
  use FamichatWeb, :controller

  alias Famichat.Auth.Identity
  alias Famichat.Chat

  require Logger

  def create(conn, %{"participant_id" => participant_id}) do
    current_user_id = conn.assigns[:current_user_id]

    cond do
      Ecto.UUID.cast(participant_id) == :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "invalid_participant_id"}})

      participant_id == current_user_id ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: %{code: "cannot_create_with_self"}})

      true ->
        case Identity.fetch_user(participant_id) do
          {:error, :user_not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: %{code: "participant_not_found"}})

          {:ok, _participant} ->
            case Chat.create_direct_conversation(current_user_id, participant_id) do
              {:ok, conversation} ->
                conn
                |> put_status(:created)
                |> json(%{
                  conversation_id: conversation.id,
                  conversation_type: Atom.to_string(conversation.conversation_type)
                })

              {:error, reason} ->
                Logger.warning(
                  "[ConversationController] create failed: #{inspect(reason)}"
                )

                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: %{code: "create_failed"}})
            end
        end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end
end
