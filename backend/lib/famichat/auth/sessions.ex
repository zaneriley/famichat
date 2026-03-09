defmodule Famichat.Auth.Sessions do
  @moduledoc """
  Device session management (access/refresh tokens, trust windows, revocation).
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Accounts,
      Famichat.Chat,
      Famichat.Auth.Households,
      Famichat.Auth.Identity,
      Famichat.Auth.RateLimit,
      Famichat.Auth.Runtime,
      Famichat.Auth.Tokens
    ]

  import Ecto.Query
  require Logger
  require Famichat.Auth.Runtime.Instrumentation
  alias Famichat.Accounts.{HouseholdMembership, User, UserDevice}
  alias Famichat.Auth.Runtime.Instrumentation
  alias Famichat.Auth.Households
  alias Famichat.Auth.Tokens.Policy
  alias Famichat.Auth.Tokens
  alias Famichat.Auth.Tokens.IssuedToken
  alias Famichat.Auth.Sessions.DeviceStore
  alias Famichat.Auth.Sessions.RefreshRotation
  alias Famichat.Auth.RateLimit
  alias Famichat.Chat
  alias Famichat.Repo

  @access_kind :access
  @refresh_kind :session_refresh
  @channel_bootstrap_kind :channel_bootstrap
  @refresh_ttl Policy.default_ttl(@refresh_kind)
  @client_revocation_reason "auth_device_revoked"
  @user_revocation_reason "auth_user_revoked"

  @spec start_session(User.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def start_session(%User{} = user, device_info, opts \\ []) do
    Instrumentation.span(
      [:famichat, :auth, :sessions, :start],
      %{user_id: user.id},
      do: do_start_session(user, device_info, opts)
    )
  end

  defp do_start_session(%User{} = user, device_info, opts)
       when is_map(device_info) do
    with :ok <- assert_user_sessionable(user) do
      want_remember? =
        Keyword.get(
          opts,
          :remember_device?,
          Keyword.get(opts, :remember, false)
        )

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
  end

  defp do_start_session(user, device_info, opts) do
    do_start_session(user, Map.new(device_info), opts)
  end

  # Reject users that are not yet fully active. Pending users have no passkey
  # yet and must complete the registration ceremony before getting a session.
  # Locked and deleted users must not be able to start sessions.
  defp assert_user_sessionable(%User{status: status})
       when status in [:locked, :deleted, :pending] do
    {:error, :user_not_active}
  end

  defp assert_user_sessionable(%User{}), do: :ok

  @spec refresh_session(String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def refresh_session(device_id, raw_refresh) do
    Instrumentation.span(
      [:famichat, :auth, :sessions, :refresh],
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

        revocation_ref = revocation_ref(:client, "#{user_id}:#{device_id}")
        stage_client_revocation(user_id, device_id)
        trigger_mls_removal(user_id, device_id, revocation_ref)
        telemetry(:revoke, %{user_id: user_id, device_id: device_id})
        {:ok, :revoked}

      nil ->
        {:error, :not_found}
    end
  end

  @spec verify_access_token(String.t() | nil) ::
          {:ok, %{user_id: Ecto.UUID.t(), device_id: String.t()}}
          | {:error, term()}
  def verify_access_token(nil), do: {:error, :no_token}
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

  @doc """
  Issues a short-lived channel bootstrap token scoped to the given device
  and live socket ID. The token is for one-time use on WS connect only
  and is delivered over the already-authenticated LiveView WebSocket,
  never placed in the DOM.
  """
  @spec issue_channel_token(Ecto.UUID.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def issue_channel_token(user_id, device_id, socket_id)
      when is_binary(user_id) and is_binary(device_id) and is_binary(socket_id) do
    with :ok <- device_access_state(user_id, device_id) do
      payload = %{
        "user_id" => user_id,
        "device_id" => device_id,
        "socket_id" => socket_id
      }

      case Tokens.issue(@channel_bootstrap_kind, payload) do
        {:ok, %IssuedToken{raw: raw}} -> {:ok, raw}
        error -> error
      end
    end
  end

  @doc """
  Verifies a channel bootstrap token. Returns the user_id and device_id
  on success. The caller (UserSocket) is responsible for final device
  state checks after verification.
  """
  @spec verify_channel_token(String.t()) ::
          {:ok, %{user_id: Ecto.UUID.t(), device_id: String.t()}}
          | {:error, term()}
  def verify_channel_token(token) when is_binary(token) do
    with {:ok, payload} <- Tokens.verify(@channel_bootstrap_kind, token),
         {:ok, device} <- DeviceStore.fetch(payload["device_id"]),
         :ok <- ensure_device_matches(device, payload["user_id"]),
         :ok <- ensure_trust_active(device, allow_nil: true) do
      {:ok, %{user_id: device.user_id, device_id: device.device_id}}
    end
  end

  @spec device_access_state(Ecto.UUID.t(), String.t()) ::
          :ok
          | {:error,
             :invalid
             | :device_not_found
             | :revoked
             | :trust_required
             | :trust_expired}
  def device_access_state(user_id, device_id)
      when is_binary(user_id) and is_binary(device_id) do
    with {:ok, device} <- DeviceStore.fetch(device_id),
         :ok <- ensure_device_owner(device, user_id),
         :ok <- ensure_not_revoked(device),
         :ok <- ensure_trust_active(device, allow_nil: true) do
      :ok
    else
      {:error, :device_not_found} ->
        {:error, :device_not_found}

      {:error, :revoked} ->
        {:error, :revoked}

      {:error, :trust_required} ->
        {:error, :trust_required}

      {:error, :trust_expired} ->
        {:error, :trust_expired}

      {:error, _reason} ->
        {:error, :invalid}

      _ ->
        {:error, :invalid}
    end
  end

  def device_access_state(_user_id, _device_id), do: {:error, :invalid}

  @spec device_active?(Ecto.UUID.t(), String.t()) :: boolean()
  def device_active?(user_id, device_id)
      when is_binary(user_id) and is_binary(device_id) do
    device_access_state(user_id, device_id) == :ok
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

    {:ok, %IssuedToken{raw: refresh_raw, hash: refresh_hash}} =
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

    {:ok, %IssuedToken{raw: access}} =
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

  defp ensure_device_owner(%UserDevice{user_id: user_id}, user_id), do: :ok
  defp ensure_device_owner(_device, _user_id), do: {:error, :invalid}

  defp rate_limit_refresh(device_id) do
    case RateLimit.check(
           :"session.refresh",
           device_id,
           limit: 6,
           interval: 60 * 60
         ) do
      :ok -> :ok
      {:error, {:rate_limited, _}} = error -> error
    end
  end

  defp telemetry(action, metadata) do
    :telemetry.execute(
      [:famichat, :auth, :sessions, action],
      %{count: 1},
      metadata
    )
  end

  defp emit_refresh_metric(action, metadata) do
    :telemetry.execute(
      [:famichat, :auth, :sessions, :refresh],
      %{count: 1},
      Map.put(metadata, :result, action)
    )
  end

  defp trigger_mls_removal(user_id, device_id, revocation_ref) do
    # Best-effort: if this fails, the session is already revoked and the
    # device cannot re-authenticate. MLS group removal is logged for audit
    # and handled via the revocation journal.
    try do
      Chat.remove_device_from_mls_groups(user_id, device_id, revocation_ref)
    rescue
      e ->
        Logger.warning(
          "[Sessions] Failed to trigger MLS group removal for revoked device",
          user_id: user_id,
          device_id: device_id,
          error: Exception.message(e)
        )

        :ok
    end
  end

  defp stage_client_revocation(user_id, device_id) do
    revocation_ref = revocation_ref(:client, "#{user_id}:#{device_id}")

    case Chat.stage_client_revocation(device_id, revocation_ref, %{
           actor_id: user_id,
           revocation_reason: @client_revocation_reason
         }) do
      {:ok, _result} ->
        :ok

      {:error, code, details} ->
        Logger.warning(
          "[Sessions] Failed to stage client revocation",
          user_id: user_id,
          device_id: device_id,
          code: code,
          details: details
        )

        :ok
    end
  end

  defp stage_user_revocation(user_id) do
    revoked_device_fingerprint =
      from(d in UserDevice,
        where: d.user_id == ^user_id and not is_nil(d.revoked_at),
        select: d.device_id
      )
      |> Repo.all()
      |> Enum.sort()
      |> Enum.join(",")

    revocation_ref =
      revocation_ref(:user, "#{user_id}:#{revoked_device_fingerprint}")

    case Chat.stage_user_revocation(user_id, revocation_ref, %{
           actor_id: user_id,
           revocation_reason: @user_revocation_reason
         }) do
      {:ok, _result} ->
        :ok

      {:error, code, details} ->
        Logger.warning(
          "[Sessions] Failed to stage user revocation",
          user_id: user_id,
          code: code,
          details: details
        )

        :ok
    end
  end

  defp revocation_ref(scope, subject_material) do
    digest =
      :crypto.hash(:sha256, subject_material)
      |> Base.url_encode64(padding: false)

    "auth:#{scope}:#{digest}"
  end

  @spec revoke_all_for_user(Ecto.UUID.t()) :: :ok
  def revoke_all_for_user(user_id) do
    from(d in UserDevice,
      where: d.user_id == ^user_id and is_nil(d.revoked_at)
    )
    |> Repo.all()
    |> Enum.each(fn device ->
      case DeviceStore.revoke(device) do
        {:ok, _} ->
          telemetry(:revoke, %{user_id: user_id, device_id: device.device_id})

        {:error, _changeset} ->
          :ok
      end
    end)

    stage_user_revocation(user_id)
    :ok
  end

  @spec revoke_all_for_household(Ecto.UUID.t(), Ecto.UUID.t()) ::
          :ok | {:error, :forbidden | :not_in_household}
  def revoke_all_for_household(admin_id, household_id) do
    with {:ok, _membership} <-
           Households.ensure_admin_membership(admin_id, household_id) do
      member_ids =
        from(m in HouseholdMembership,
          where: m.family_id == ^household_id,
          select: m.user_id
        )
        |> Repo.all()

      Enum.each(member_ids, &revoke_all_for_user/1)
      :ok
    end
  end
end
