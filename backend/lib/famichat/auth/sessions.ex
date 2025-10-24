defmodule Famichat.Auth.Sessions do
  @moduledoc """
  Device session management (access/refresh tokens, trust windows, revocation).
  """

  use Boundary,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Auth.Identity,
      Famichat.Auth.Infra
    ]

  require Logger
  require Famichat.Auth.Infra.Instrumentation
  alias Famichat.Accounts.{RateLimiter, User, UserDevice}
  alias Famichat.Auth.Infra.Instrumentation
  alias Famichat.Auth.Tokens.Policy
  alias Famichat.Auth.Tokens
  alias Famichat.Auth.Sessions.DeviceStore
  alias Famichat.Auth.Sessions.RefreshRotation
  alias Famichat.Repo

  @access_kind :access
  @refresh_kind :device_refresh
  @refresh_ttl Policy.default_ttl(@refresh_kind)

  @spec start_session(User.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def start_session(%User{} = user, device_info, opts \\ []) do
    Instrumentation.span(
      [:famichat, :auth, :session, :start],
      %{user_id: user.id},
      do: do_start_session(user, device_info, opts)
    )
  end

  defp do_start_session(%User{} = user, device_info, opts)
       when is_map(device_info) do
    want_remember? = Keyword.get(opts, :remember, false)
    can_remember? = policy_allows_remembering?(user)
    should_remember? = want_remember? and can_remember?

    if want_remember? and not can_remember? do
      Logger.info(
        "[Sessions] Device remember requested but denied by user policy",
        user_id: user.id
      )
    end

    Repo.transaction(fn ->
      with {:ok, normalized} <- DeviceStore.normalize_info(device_info),
           {:ok, device} <-
             DeviceStore.upsert(
               user,
               normalized,
               should_remember?,
               @refresh_ttl
             ),
           {:ok, tokens, _user_id, updated_device} <-
             issue_session_tokens(user, device) do
        telemetry(:start, %{
          user_id: user.id,
          device_id: updated_device.device_id,
          remembered: should_remember?
        })

        tokens
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp do_start_session(user, device_info, opts) do
    do_start_session(user, Map.new(device_info), opts)
  end

  @spec refresh_session(String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def refresh_session(device_id, raw_refresh) do
    Instrumentation.span(
      [:famichat, :auth, :session, :refresh],
      %{device_id: device_id},
      do:
        with :ok <- rate_limit_refresh(device_id),
             {:ok, device} <- DeviceStore.fetch(device_id),
             :ok <- ensure_not_revoked(device),
             :ok <- ensure_trust_active(device, []),
             result <-
               RefreshRotation.verify_and_rotate(
                 device,
                 raw_refresh,
                 &issue_session_tokens/2
               ) do
          handle_rotation_result(device_id, result)
        else
          {:error, reason} = error ->
            emit_refresh_metric(:invalid, %{
              device_id: device_id,
              reason: reason
            })

            error
        end
    )
  end

  defp handle_rotation_result(device_id, {:ok, tokens, user_id, _new_device}) do
    telemetry(:refresh, %{user_id: user_id, device_id: device_id})
    emit_refresh_metric(:success, %{user_id: user_id, device_id: device_id})
    {:ok, tokens}
  end

  defp handle_rotation_result(device_id, {:reuse_detected, user_id}) do
    telemetry(:refresh_reuse_detected, %{user_id: user_id, device_id: device_id})

    emit_refresh_metric(:reuse_detected, %{
      user_id: user_id,
      device_id: device_id
    })

    {:error, :reuse_detected}
  end

  defp handle_rotation_result(device_id, {:error, reason}) do
    emit_refresh_metric(:invalid, %{device_id: device_id, reason: reason})
    {:error, reason}
  end

  @spec revoke_device(Ecto.UUID.t(), String.t()) ::
          {:ok, :revoked} | {:error, :not_found}
  def revoke_device(user_id, device_id) do
    case Repo.get_by(UserDevice, user_id: user_id, device_id: device_id) do
      %UserDevice{} = device ->
        {:ok, _} =
          device
          |> UserDevice.changeset(%{revoked_at: DateTime.utc_now()})
          |> Repo.update()

        telemetry(:revoke, %{user_id: user_id, device_id: device_id})
        {:ok, :revoked}

      nil ->
        {:error, :not_found}
    end
  end

  @spec verify_access_token(String.t()) ::
          {:ok, %{user_id: Ecto.UUID.t(), device_id: String.t()}}
          | {:error, term()}
  def verify_access_token(token) when is_binary(token) do
    with {:ok, payload} <- Tokens.verify(@access_kind, token),
         {:ok, device} <- DeviceStore.fetch(payload["device_id"]),
         :ok <- ensure_device_matches(device, payload["user_id"]),
         :ok <- ensure_trust_active(device, allow_nil: true) do
      {:ok, %{user_id: device.user_id, device_id: device.device_id}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec require_reauth?(Ecto.UUID.t(), String.t(), atom()) :: boolean()
  def require_reauth?(user_id, device_id, _action) do
    with {:ok, device} <- DeviceStore.fetch(device_id),
         true <- device.user_id == user_id,
         false <- is_nil(device.trusted_until) do
      DateTime.compare(device.trusted_until, DateTime.utc_now()) == :lt
    else
      _ -> true
    end
  end

  ## Helpers

  defp issue_session_tokens(%User{} = user, %UserDevice{} = device) do
    now = DateTime.utc_now()
    trusted_until = device.trusted_until

    {:ok, %Tokens.Issue{raw: refresh_raw, hash: refresh_hash}} =
      Tokens.issue(@refresh_kind, %{"device_id" => device.device_id})

    {:ok, device} =
      device
      |> UserDevice.changeset(%{
        refresh_token_hash: refresh_hash,
        previous_token_hash: device.refresh_token_hash,
        trusted_until: trusted_until,
        last_active_at: now
      })
      |> Repo.update()

    access_payload = %{"user_id" => user.id, "device_id" => device.device_id}

    {:ok, %Tokens.Issue{raw: access}} =
      Tokens.issue(@access_kind, access_payload)

    {:ok,
     %{
       user_id: user.id,
       access_token: access,
       refresh_token: refresh_raw,
       device_id: device.device_id,
       trusted_until: trusted_until
     }, user.id, device}
  end

  defp ensure_not_revoked(%UserDevice{revoked_at: nil}), do: :ok
  defp ensure_not_revoked(_), do: {:error, :revoked}

  defp ensure_trust_active(%UserDevice{trusted_until: nil}, opts) do
    if Keyword.get(opts, :allow_nil, false) do
      :ok
    else
      {:error, :trust_required}
    end
  end

  defp ensure_trust_active(%UserDevice{trusted_until: trusted_until}, _opts) do
    if DateTime.compare(trusted_until, DateTime.utc_now()) == :lt do
      {:error, :trust_expired}
    else
      :ok
    end
  end

  defp policy_allows_remembering?(%User{enrollment_required_since: nil}),
    do: true

  defp policy_allows_remembering?(%User{}), do: false

  defp ensure_device_matches(
         %UserDevice{user_id: user_id, revoked_at: nil},
         user_id
       ),
       do: :ok

  defp ensure_device_matches(_, _), do: {:error, :invalid}

  defp rate_limit_refresh(device_id) do
    case RateLimiter.throttle(:refresh_attempt, device_id, 6, 60 * 60) do
      :ok -> :ok
      {:error, {:rate_limited, retry}} -> {:error, {:rate_limited, retry}}
    end
  end

  defp telemetry(action, metadata) do
    :telemetry.execute(
      [:famichat, :auth, :session, action],
      %{count: 1},
      metadata
    )
  end

  defp emit_refresh_metric(action, metadata) do
    :telemetry.execute(
      [:auth_sessions, :refresh, action],
      %{count: 1},
      metadata
    )
  end
end
