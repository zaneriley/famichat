defmodule FamichatWeb.API.ChatWriteController do
  use FamichatWeb, :controller

  alias Famichat.Chat

  alias Famichat.Chat.{
    Conversation,
    ConversationAccess,
    Message
  }

  alias Famichat.Repo
  alias FamichatWeb.MessagingDispatch

  @doc """
  Canonical production message send endpoint.

  POST /api/v1/conversations/:id/messages
  """
  def create_message(
        %{assigns: %{current_user_id: user_id, current_device_id: device_id}} =
          conn,
        %{"id" => conversation_id} = params
      ) do
    with {:ok, body} <- normalize_body(params),
         {:ok, conversation} <- fetch_conversation(conversation_id, user_id),
         {:ok, payload} <-
           send_message(conversation.id, user_id, device_id, body) do
      topic = topic_for(conversation, user_id)
      FamichatWeb.Endpoint.broadcast!(topic, "new_msg", payload)

      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          topic: topic,
          event_name: "new_msg",
          payload: payload
        }
      })
    else
      {:error, :validation, details} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(error_payload("invalid_request", details: details))

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(error_payload("forbidden"))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(error_payload("not_found"))

      {:error, :recovery_required, details} ->
        conn
        |> put_status(:conflict)
        |> json(
          error_payload("recovery_required",
            action: "recover_conversation_security_state",
            details: %{reason: mls_error_reason(details)}
          )
        )

      {:error, :conversation_security_blocked, code, details} ->
        conn
        |> put_status(:conflict)
        |> json(
          error_payload("conversation_security_blocked",
            action: security_block_action(code),
            details: %{
              code: to_string(code),
              reason: mls_error_reason(details)
            }
          )
        )

      {:error, :message_too_large} ->
        conn
        |> put_status(413)
        |> json(
          error_payload("message_too_large",
            details: %{max_bytes: Message.max_content_bytes()}
          )
        )

      {:error, :rate_limited, retry_in} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_in))
        |> put_status(:too_many_requests)
        |> json(error_payload("rate_limited", details: %{retry_in: retry_in}))
    end
  end

  @doc """
  Canonical production recovery endpoint.

  POST /api/v1/conversations/:id/security/recover
  """
  def recover_security_state(
        %{assigns: %{current_user_id: user_id}} = conn,
        %{"id" => conversation_id} = params
      ) do
    with {:ok, _conversation} <- fetch_conversation(conversation_id, user_id),
         {:ok, recovery_ref, attrs} <- normalize_recovery_request(params),
         {:ok, result} <-
           Chat.recover_conversation_security_state(
             conversation_id,
             recovery_ref,
             attrs
           ) do
      json(conn, %{
        data: %{
          conversation_id: conversation_id,
          recovery_id: result.recovery_id,
          recovery_ref: result.recovery_ref,
          recovered_epoch: result.recovered_epoch,
          idempotent: result.idempotent
        }
      })
    else
      {:error, :validation, details} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(error_payload("invalid_request", details: details))

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(error_payload("forbidden"))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(error_payload("not_found"))

      {:error, :recovery_in_progress, details} ->
        conn
        |> put_status(:conflict)
        |> json(
          error_payload("recovery_in_progress",
            details: %{reason: mls_error_reason(details)}
          )
        )

      {:error, :recovery_failed, details} ->
        conn
        |> put_status(:conflict)
        |> json(
          error_payload("recovery_failed",
            details: %{reason: mls_error_reason(details)}
          )
        )

      {:error, code, details} when is_atom(code) and is_map(details) ->
        conn
        |> put_status(:conflict)
        |> json(
          error_payload("recovery_failed",
            details: %{
              code: Atom.to_string(code),
              reason: mls_error_reason(details)
            }
          )
        )
    end
  end

  defp normalize_body(params) do
    case Map.get(params, "body") do
      body when is_binary(body) ->
        trimmed = String.trim(body)

        if trimmed == "" do
          {:error, :validation, %{"body" => "must be a non-empty string"}}
        else
          {:ok, trimmed}
        end

      _ ->
        {:error, :validation, %{"body" => "must be a non-empty string"}}
    end
  end

  defp fetch_conversation(conversation_id, user_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(conversation_id),
         %Conversation{} = conversation <-
           Repo.get(Conversation, conversation_id),
         :ok <-
           ConversationAccess.authorize(conversation.id, user_id, :send_message) do
      {:ok, conversation}
    else
      :error -> {:error, :validation, %{"id" => "must be a valid UUID"}}
      nil -> {:error, :not_found}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  defp send_message(conversation_id, user_id, device_id, body) do
    %{sender_id: user_id, conversation_id: conversation_id, content: body}
    |> MessagingDispatch.send_message(device_id)
    |> map_send_error()
  end

  defp map_send_error({:ok, payload}), do: {:ok, payload}
  defp map_send_error({:error, :not_participant}), do: {:error, :not_found}
  defp map_send_error({:error, :wrong_family}), do: {:error, :not_found}

  defp map_send_error({:error, :conversation_not_found}),
    do: {:error, :not_found}

  defp map_send_error(
         {:error, {:mls_encryption_failed, :recovery_required, details}}
       ) do
    {:error, :recovery_required, details}
  end

  defp map_send_error({:error, {:mls_encryption_failed, code, details}})
       when is_atom(code) do
    {:error, :conversation_security_blocked, code, details}
  end

  defp map_send_error({:error, %Ecto.Changeset{} = changeset}) do
    if message_too_large_changeset?(changeset) do
      {:error, :message_too_large}
    else
      {:error, :validation, %{"body" => "must be a non-empty string"}}
    end
  end

  defp map_send_error({:error, {:rate_limited, retry_in}})
       when is_integer(retry_in) and retry_in > 0 do
    {:error, :rate_limited, retry_in}
  end

  defp map_send_error({:error, {:missing_fields, _missing}}),
    do: {:error, :validation, %{"body" => "must be a non-empty string"}}

  defp map_send_error({:error, _reason}),
    do: {:error, :validation, %{"request" => "unable to send message"}}

  defp topic_for(%Conversation{conversation_type: :self}, user_id),
    do: "message:self:#{user_id}"

  defp topic_for(%Conversation{} = conversation, _user_id),
    do: "message:#{conversation.conversation_type}:#{conversation.id}"

  defp normalize_recovery_request(params) when is_map(params) do
    recovery_ref = non_empty_param(params, "recovery_ref")
    rejoin_token = non_empty_param(params, "rejoin_token")
    welcome = non_empty_param(params, "welcome")
    recovery_reason = non_empty_param(params, "recovery_reason")

    details =
      %{}
      |> maybe_put_missing("recovery_ref", recovery_ref)
      |> maybe_put_missing_rejoin_material(rejoin_token, welcome)

    if details == %{} do
      attrs =
        %{}
        |> maybe_put_value("rejoin_token", rejoin_token)
        |> maybe_put_value("welcome", welcome)
        |> maybe_put_value("recovery_reason", recovery_reason)

      {:ok, recovery_ref, attrs}
    else
      {:error, :validation, details}
    end
  end

  defp non_empty_param(params, key) do
    value = Map.get(params, key) || Map.get(params, String.to_atom(key))

    case value do
      binary when is_binary(binary) ->
        trimmed = String.trim(binary)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end
  end

  defp maybe_put_missing(details, _key, value) when is_binary(value),
    do: details

  defp maybe_put_missing(details, key, _value) do
    Map.put(details, key, "must be a non-empty string")
  end

  defp maybe_put_missing_rejoin_material(details, rejoin_token, welcome)
       when is_binary(rejoin_token) or is_binary(welcome),
       do: details

  defp maybe_put_missing_rejoin_material(details, _rejoin_token, _welcome) do
    Map.put(details, "rejoin_token", "rejoin_token or welcome is required")
  end

  defp maybe_put_value(map, _key, nil), do: map
  defp maybe_put_value(map, key, value), do: Map.put(map, key, value)

  defp message_too_large_changeset?(changeset) do
    Enum.any?(changeset.errors, fn
      {:content, {_message, opts}} ->
        Keyword.get(opts, :validation) == :length and
          Keyword.get(opts, :kind) == :max

      _ ->
        false
    end)
  end

  defp mls_error_reason(details) when is_map(details) do
    case Map.get(details, :reason) || Map.get(details, "reason") do
      reason when is_atom(reason) -> Atom.to_string(reason)
      reason when is_binary(reason) -> reason
      _ -> "unspecified"
    end
  end

  defp mls_error_reason(_details), do: "unspecified"

  defp security_block_action(:pending_proposals), do: "wait_for_pending_commit"
  defp security_block_action(_code), do: "retry_later"

  defp error_payload(code, opts \\ []) do
    base = %{error: %{code: code}}

    base
    |> maybe_put_error("message", Keyword.get(opts, :message))
    |> maybe_put_error("action", Keyword.get(opts, :action))
    |> maybe_put_error("details", Keyword.get(opts, :details))
  end

  defp maybe_put_error(payload, _key, nil), do: payload

  defp maybe_put_error(%{error: error} = payload, key, value) do
    %{payload | error: Map.put(error, key, value)}
  end
end
