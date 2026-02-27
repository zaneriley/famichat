defmodule FamichatWeb.MessageTestController do
  @moduledoc """
  Secure CLI broadcast verification endpoint used in development and test.

  Canonical endpoint:
  - `POST /api/test/broadcast`

  Compatibility alias endpoint:
  - `POST /api/test/test_events` (adds deprecation headers)
  """
  use FamichatWeb, :controller

  alias Famichat.Chat
  alias Famichat.Chat.{Conversation, ConversationAccess, Message, Self}
  alias Famichat.Chat.ConversationSecurityStateStore
  alias FamichatWeb.MessagingDispatch
  alias Famichat.Repo

  @type_map %{
    "self" => :self,
    "direct" => :direct,
    "group" => :group,
    "family" => :family
  }
  @conversation_types Map.keys(@type_map)

  @default_key_id "KEY_TEST_v1"
  @default_version_tag "v1.0.0"
  @alias_sunset "Tue, 31 Mar 2026 00:00:00 GMT"

  @doc """
  Canonical secure test broadcast endpoint.
  """
  def broadcast(conn, params), do: handle_broadcast(conn, params)

  @doc """
  Test-only recovery endpoint for live QA matrix scenarios.
  """
  def recover_conversation_security_state(
        %{assigns: %{current_user_id: user_id}} = conn,
        params
      ) do
    with {:ok, request} <- normalize_conversation_target(params),
         {:ok, conversation} <- fetch_conversation(request, user_id),
         {:ok, recovery_ref, recovery_attrs} <-
           normalize_recovery_request(params),
         {:ok, result} <-
           Chat.recover_conversation_security_state(
             conversation.id,
             recovery_ref,
             recovery_attrs
           ) do
      json(conn, %{
        status: "success",
        action: "recover_conversation_security_state",
        conversation_id: conversation.id,
        recovery_ref: result.recovery_ref,
        recovery_id: result.recovery_id,
        recovered_epoch: result.recovered_epoch,
        idempotent: result.idempotent
      })
    else
      {:error, :validation, details} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          error: "invalid_request",
          details: details
        })

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{status: "error", error: "forbidden"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", error: "not_found"})

      {:error, :recovery_in_progress, details} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          status: "error",
          error: "recovery_in_progress",
          details: %{reason: mls_error_reason(details)}
        })

      {:error, :recovery_failed, details} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          status: "error",
          error: "recovery_failed",
          details: %{reason: mls_error_reason(details)}
        })

      {:error, code, details} when is_atom(code) and is_map(details) ->
        conn
        |> put_status(:conflict)
        |> json(%{
          status: "error",
          error: "recovery_failed",
          code: Atom.to_string(code),
          details: %{reason: mls_error_reason(details)}
        })
    end
  end

  def recover_conversation_security_state(conn, _params) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized"})
  end

  @doc """
  Test-only endpoint to clear conversation security state for recovery drills.
  """
  def reset_conversation_security_state(
        %{assigns: %{current_user_id: user_id}} = conn,
        params
      ) do
    with {:ok, request} <- normalize_conversation_target(params),
         {:ok, conversation} <- fetch_conversation(request, user_id),
         :ok <- ConversationSecurityStateStore.delete(conversation.id) do
      json(conn, %{
        status: "success",
        action: "reset_conversation_security_state",
        conversation_id: conversation.id
      })
    else
      {:error, :validation, details} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          error: "invalid_request",
          details: details
        })

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{status: "error", error: "forbidden"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "error", error: "not_found"})

      {:error, code, details} when is_atom(code) and is_map(details) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          error: "invalid_request",
          details: %{
            reason: mls_error_reason(details),
            code: Atom.to_string(code)
          }
        })
    end
  end

  def reset_conversation_security_state(conn, _params) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized"})
  end

  @doc """
  Temporary compatibility alias for one sprint.
  """
  def broadcast_alias(conn, params) do
    conn
    |> put_resp_header("deprecation", "true")
    |> put_resp_header("sunset", @alias_sunset)
    |> put_resp_header(
      "link",
      ~s(</api/test/broadcast>; rel="successor-version")
    )
    |> handle_broadcast(params)
  end

  defp handle_broadcast(
         %{assigns: %{current_user_id: user_id, current_device_id: device_id}} =
           conn,
         params
       ) do
    with {:ok, request} <- normalize_request(params),
         {:ok, conversation} <- fetch_conversation(request, user_id),
         {:ok, payload} <-
           send_message(
             request,
             user_id,
             device_id,
             conversation.id
           ) do
      topic = topic_for(request, user_id)
      FamichatWeb.Endpoint.broadcast!(topic, "new_msg", payload)

      json(conn, %{
        status: "success",
        topic: topic,
        event_name: "new_msg",
        payload: payload
      })
    else
      {:error, :validation, details} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          status: "error",
          error: "invalid_request",
          details: details
        })

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          status: "error",
          error: "forbidden"
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          status: "error",
          error: "not_found"
        })

      {:error, :recovery_required, details} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          status: "error",
          error: "recovery_required",
          action: "recover_conversation_security_state",
          details: %{
            reason: mls_error_reason(details)
          }
        })

      {:error, :conversation_security_blocked, code, details} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          status: "error",
          error: "conversation_security_blocked",
          code: to_string(code),
          action: security_block_action(code),
          details: %{
            reason: mls_error_reason(details)
          }
        })

      {:error, :message_too_large} ->
        conn
        |> put_status(413)
        |> json(%{
          status: "error",
          error: "message_too_large",
          max_bytes: Message.max_content_bytes()
        })

      {:error, :rate_limited, retry_in} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_in))
        |> put_status(:too_many_requests)
        |> json(%{
          status: "error",
          error: "rate_limited",
          retry_in: retry_in
        })
    end
  end

  defp handle_broadcast(conn, _params) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized"})
  end

  defp normalize_request(params) do
    params
    |> canonicalize_params()
    |> validate_params()
  end

  defp normalize_conversation_target(params) do
    canonical = canonicalize_params(params)

    details =
      %{}
      |> validate_conversation_type(canonical)
      |> validate_conversation_id(canonical)

    if details == %{} do
      {:ok,
       %{
         conversation_type:
           Map.fetch!(@type_map, Map.get(canonical, "conversation_type")),
         conversation_type_string: Map.get(canonical, "conversation_type"),
         conversation_id: Map.get(canonical, "conversation_id")
       }}
    else
      {:error, :validation, details}
    end
  end

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

  defp canonicalize_params(params) do
    cond do
      has_key?(params, "conversation_type") ->
        %{
          "conversation_type" => params["conversation_type"],
          "conversation_id" => Map.get(params, "conversation_id"),
          "body" => params["body"],
          "encryption_flag" => Map.get(params, "encryption_flag"),
          "key_id" => Map.get(params, "key_id"),
          "version_tag" => Map.get(params, "version_tag")
        }

      has_key?(params, "type") and has_key?(params, "id") ->
        %{
          "conversation_type" => params["type"],
          "conversation_id" => params["id"],
          "body" => params["body"],
          "encryption_flag" =>
            first_non_nil(params["encryption_flag"], params["encryption"]),
          "key_id" => Map.get(params, "key_id"),
          "version_tag" => Map.get(params, "version_tag")
        }

      has_key?(params, "topic") ->
        case parse_topic(params["topic"]) do
          {:ok, conversation_type, conversation_id} ->
            %{
              "conversation_type" => conversation_type,
              "conversation_id" => conversation_id,
              "body" => first_non_nil(params["body"], params["content"]),
              "encryption_flag" =>
                first_non_nil(params["encryption_flag"], params["encryption"]),
              "key_id" => Map.get(params, "key_id"),
              "version_tag" => Map.get(params, "version_tag")
            }

          {:error, :invalid_topic} ->
            %{
              "conversation_type" => nil,
              "conversation_id" => nil,
              "body" => first_non_nil(params["body"], params["content"]),
              "encryption_flag" =>
                first_non_nil(params["encryption_flag"], params["encryption"]),
              "key_id" => Map.get(params, "key_id"),
              "version_tag" => Map.get(params, "version_tag"),
              "__topic_error__" => "invalid topic format"
            }
        end

      true ->
        %{
          "conversation_type" => nil,
          "conversation_id" => nil,
          "body" => params["body"],
          "encryption_flag" => Map.get(params, "encryption_flag"),
          "key_id" => Map.get(params, "key_id"),
          "version_tag" => Map.get(params, "version_tag")
        }
    end
  end

  defp parse_topic("message:" <> rest) do
    case String.split(rest, ":", parts: 3) do
      ["self"] ->
        {:ok, "self", nil}

      ["self", _user_id] ->
        {:ok, "self", nil}

      [conversation_type, conversation_id]
      when conversation_type in ["direct", "group", "family"] ->
        {:ok, conversation_type, conversation_id}

      _ ->
        {:error, :invalid_topic}
    end
  end

  defp parse_topic(_), do: {:error, :invalid_topic}

  defp validate_params(%{"__topic_error__" => topic_error}) do
    {:error, :validation, %{"topic" => topic_error}}
  end

  defp validate_params(params) do
    details =
      %{}
      |> validate_conversation_type(params)
      |> validate_conversation_id(params)
      |> validate_body(params)
      |> validate_encryption_flag(params)
      |> maybe_validate_encryption_metadata(params)

    if details == %{} do
      {:ok, build_request(params)}
    else
      {:error, :validation, details}
    end
  end

  defp validate_conversation_type(details, params) do
    case Map.get(params, "conversation_type") do
      type when type in @conversation_types ->
        details

      _ ->
        Map.put(
          details,
          "conversation_type",
          "must be one of: self, direct, group, family"
        )
    end
  end

  defp validate_conversation_id(details, params) do
    case Map.get(params, "conversation_type") do
      "self" ->
        case Map.get(params, "conversation_id") do
          nil ->
            details

          id ->
            case Ecto.UUID.cast(id) do
              {:ok, _uuid} ->
                details

              :error ->
                Map.put(details, "conversation_id", "must be a valid UUID")
            end
        end

      _ ->
        case Ecto.UUID.cast(Map.get(params, "conversation_id")) do
          {:ok, _uuid} -> details
          :error -> Map.put(details, "conversation_id", "must be a valid UUID")
        end
    end
  end

  defp validate_body(details, params) do
    case Map.get(params, "body") do
      body when is_binary(body) ->
        if byte_size(String.trim(body)) > 0 do
          details
        else
          Map.put(details, "body", "must be a non-empty string")
        end

      _ ->
        Map.put(details, "body", "must be a non-empty string")
    end
  end

  defp validate_encryption_flag(details, params) do
    if is_boolean(encryption_flag(params)) do
      details
    else
      Map.put(details, "encryption_flag", "must be a boolean")
    end
  end

  defp maybe_validate_encryption_metadata(details, params) do
    if encryption_flag(params) == true do
      validate_encryption_metadata(details, params)
    else
      details
    end
  end

  defp validate_encryption_metadata(details, params) do
    key_id = default_if_nil(Map.get(params, "key_id"), @default_key_id)

    version_tag =
      default_if_nil(Map.get(params, "version_tag"), @default_version_tag)

    key_id_valid =
      is_binary(key_id) and Regex.match?(~r/^KEY_[A-Z]+_v[0-9]+$/, key_id)

    version_tag_valid =
      is_binary(version_tag) and
        Regex.match?(~r/^v[0-9]+\.[0-9]+\.[0-9]+$/, version_tag)

    details =
      if key_id_valid do
        details
      else
        Map.put(details, "key_id", "must match KEY_[A-Z]+_v[0-9]+")
      end

    if version_tag_valid do
      details
    else
      Map.put(details, "version_tag", "must match v[0-9]+.[0-9]+.[0-9]+")
    end
  end

  defp fetch_conversation(
         %{
           conversation_type: :self,
           conversation_id: requested_id
         },
         user_id
       ) do
    with {:ok, conversation} <- Self.get_or_create(user_id),
         :ok <- validate_self_owner_target(conversation.id, requested_id) do
      {:ok, conversation}
    else
      {:error, :forbidden} = error ->
        error

      {:error, _reason} ->
        {:error, :validation, %{"conversation_id" => "conversation not found"}}
    end
  end

  defp fetch_conversation(
         %{
           conversation_id: conversation_id,
           conversation_type: conversation_type
         },
         user_id
       ) do
    case Repo.get(Conversation, conversation_id) do
      %Conversation{} = conversation ->
        case ConversationAccess.authorize(
               conversation.id,
               user_id,
               :send_message
             ) do
          :ok ->
            if conversation.conversation_type == conversation_type do
              {:ok, conversation}
            else
              {:error, :validation,
               %{"conversation_type" => "does not match conversation"}}
            end

          {:error, _reason} ->
            {:error, :not_found}
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp validate_self_owner_target(_actual_id, nil), do: :ok
  defp validate_self_owner_target(actual_id, actual_id), do: :ok

  defp validate_self_owner_target(_actual_id, _requested_id),
    do: {:error, :forbidden}

  defp topic_for(
         %{
           conversation_type_string: "self"
         },
         user_id
       ) do
    "message:self:#{user_id}"
  end

  defp topic_for(
         %{
           conversation_type_string: conversation_type,
           conversation_id: conversation_id
         },
         _user_id
       ) do
    "message:#{conversation_type}:#{conversation_id}"
  end

  defp send_message(request, user_id, device_id, conversation_id) do
    request
    |> build_message_params(user_id, conversation_id)
    |> MessagingDispatch.send_message(device_id)
    |> map_send_error()
  end

  defp build_message_params(request, user_id, conversation_id) do
    params = %{
      sender_id: user_id,
      conversation_id: conversation_id,
      content: request.body
    }

    if request.encryption_flag do
      Map.put(params, :encryption_metadata, %{
        "encryption_flag" => true,
        "key_id" => request.key_id,
        "version_tag" => request.version_tag
      })
    else
      params
    end
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

  defp build_request(params) do
    %{
      conversation_type:
        Map.fetch!(@type_map, Map.get(params, "conversation_type")),
      conversation_type_string: Map.get(params, "conversation_type"),
      conversation_id: Map.get(params, "conversation_id"),
      body: String.trim(Map.get(params, "body")),
      encryption_flag: encryption_flag(params),
      key_id: default_if_nil(Map.get(params, "key_id"), @default_key_id),
      version_tag:
        default_if_nil(Map.get(params, "version_tag"), @default_version_tag)
    }
  end

  defp encryption_flag(params) do
    default_if_nil(Map.get(params, "encryption_flag"), false)
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

  defp has_key?(params, key) when is_map(params), do: Map.has_key?(params, key)

  defp first_non_nil(nil, second), do: second
  defp first_non_nil(first, _second), do: first

  defp default_if_nil(nil, default), do: default
  defp default_if_nil(value, _default), do: value

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
end
