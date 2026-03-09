defmodule FamichatWeb.AuthController do
  use FamichatWeb, :controller
  require Logger

  alias Famichat.Auth.RateLimit

  alias Famichat.Accounts.FamilyContext

  alias Famichat.Auth.{
    Identity,
    Onboarding,
    Passkeys,
    Recovery,
    Sessions,
    Tokens
  }

  alias FamichatWeb.ConnHelpers
  alias FamichatWeb.Plugs.EnsureTrusted

  plug EnsureTrusted
       when action in [
              :issue_invite,
              :reissue_pairing,
              :issue_recovery,
              :revoke_device
            ]

  def issue_invite(conn, params) do
    inviter_id = conn.assigns[:current_user_id]

    case Onboarding.issue_invite_validated(inviter_id, params) do
      {:ok, tokens} ->
        body = %{
          invite_token: tokens.invite,
          qr_token: tokens.qr,
          admin_code: tokens.admin_code
        }

        conn
        |> maybe_put_test_token(tokens)
        |> put_status(:accepted)
        |> json(body)

      error ->
        handle_issue_invite_error(conn, error)
    end
  end

  def reissue_pairing(conn, %{"invite_token" => invite_token}) do
    requester_id = conn.assigns[:current_user_id]

    case Onboarding.reissue_pairing(requester_id, invite_token) do
      {:ok, %{qr: qr, admin_code: admin_code}} ->
        conn
        |> maybe_put_test_token(%{qr_token: qr, admin_code: admin_code})
        |> json(%{qr_token: qr, admin_code: admin_code})

      {:error, :invalid} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{code: "invalid_invite"}})

      {:error, reason} ->
        unexpected_error(
          conn,
          "reissue_pairing",
          reason,
          "pairing_reissue_failed"
        )
    end
  end

  def reissue_pairing(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end

  def accept_invite(conn, params) do
    token = params["token"] || params["invite_token"]

    if is_nil(token) do
      conn
      |> put_status(:bad_request)
      |> json(%{error: %{code: "invalid_parameters"}})
    else
      rate_limit_token!(conn, :invite_accept, token)

      case Onboarding.accept_invite(token) do
        {:ok, %{payload: payload, registration_token: registration_token}} ->
          conn
          |> maybe_put_test_token(%{registration_token: registration_token})
          |> json(%{payload: payload, registration_token: registration_token})

        {:error, {:rate_limited, retry_in}} ->
          conn
          |> put_status(:too_many_requests)
          |> json(%{error: %{code: "rate_limited", retry_in: retry_in}})

        {:error, :expired} ->
          conn |> put_status(:gone) |> json(%{error: %{code: "expired"}})

        {:error, :used} ->
          conn |> put_status(:gone) |> json(%{error: %{code: "used"}})

        {:error, :invalid} ->
          conn |> put_status(:not_found) |> json(%{error: %{code: "invalid"}})
      end
    end
  end

  def redeem_pairing(conn, %{"token" => token}) do
    rate_limit_token!(conn, :pairing, token)

    case Onboarding.redeem_pairing(token) do
      {:ok, %{invite_token: invite_token, payload: payload}} ->
        json(conn, %{invite_token: invite_token, payload: payload})

      {:error, :invalid_pair} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{code: "invalid_pairing"}})

      {:error, :invalid} ->
        conn |> put_status(:not_found) |> json(%{error: %{code: "invalid"}})

      {:error, :expired} ->
        conn |> put_status(:gone) |> json(%{error: %{code: "expired"}})

      {:error, :used} ->
        conn |> put_status(:gone) |> json(%{error: %{code: "used"}})

      {:error, {:rate_limited, retry_in}} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "rate_limited", retry_in: retry_in}})
    end
  end

  def redeem_pairing(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end

  def complete_invite(conn, params) do
    # Token is the auth credential — validate it by fetching the ledgered record
    # first, before checking other params like username. Fetching (not verifying)
    # enforces single-use: a consumed token returns {:error, :used} here.
    with {:ok, registration_token} <- registration_token_from(conn, params),
         {:ok, _reg_record} <-
           Tokens.fetch(:invite_registration, registration_token) do
      rate_limit_token!(conn, :invite_register, registration_token)

      with {:ok, username} <- invite_username_from(params),
           {:ok, %{user: user, passkey_register_token: register_token}} <-
             Onboarding.complete_registration(registration_token, %{
               username: username,
               email: Map.get(params, "email")
             }) do
        conn
        |> put_status(:created)
        |> json(%{
          user_id: user.id,
          username: user.username,
          passkey_register_token: register_token
        })
      else
        {:error, :invalid_parameters} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: %{code: "invalid_parameters"}})

        error ->
          handle_complete_invite_error(conn, error)
      end
    else
      {:error, :missing_registration_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{code: "missing_registration_token"}})

      {:error, reason} ->
        handle_complete_invite_fetch_error(conn, reason)
    end
  end

  defp registration_token_from(conn, params) do
    header_token =
      conn
      |> get_req_header("authorization")
      |> Enum.find_value(fn
        "Bearer " <> token -> token
        "bearer " <> token -> token
        _ -> nil
      end)

    token =
      header_token ||
        Map.get(params, "registration_token") ||
        Map.get(params, :registration_token)

    if is_binary(token) and byte_size(String.trim(token)) > 0 do
      {:ok, String.trim(token)}
    else
      {:error, :missing_registration_token}
    end
  end

  defp invite_username_from(params) do
    case Map.get(params, "username") || Map.get(params, :username) do
      nil -> {:error, :invalid_parameters}
      username -> {:ok, username}
    end
  end

  def passkey_register_challenge(conn, %{"register_token" => register_token}) do
    case Passkeys.exchange_registration_token(register_token) do
      {:ok, user} ->
        respond_with_passkey_challenge(conn, user.id)

      {:error, {:rate_limited, retry}} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "rate_limited", retry_in: retry}})

      {:error, :invalid} ->
        # Token was never valid (garbage/malformed/nonexistent) — auth failure,
        # not a gone resource. 410 Gone is reserved for tokens that existed and
        # were consumed/expired, not tokens that never existed.
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{code: "invalid_token"}})

      {:error, :expired} ->
        conn |> put_status(:gone) |> json(%{error: %{code: "token_expired"}})

      {:error, :used} ->
        conn |> put_status(:gone) |> json(%{error: %{code: "used"}})

      {:error, reason} ->
        unexpected_error(
          conn,
          "passkey_register_challenge",
          reason,
          "passkey_challenge_failed"
        )
    end
  end

  def passkey_register_challenge(conn, _params) do
    case conn.assigns[:current_user_id] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{code: "invalid_token"}})

      user_id ->
        respond_with_passkey_challenge(conn, user_id)
    end
  end

  def passkey_register(conn, params) do
    device_info = %{
      id: Map.get(params, "device_id", Ecto.UUID.generate()),
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      ip: maybe_ip(conn)
    }

    with {:ok, passkey} <- Passkeys.register_passkey(params),
         {:ok, user} <- Identity.fetch_user(passkey.user_id),
         {:ok, session} <-
           Sessions.start_session(user, device_info, remember_device?: false) do
      conn
      |> put_status(:created)
      |> ConnHelpers.put_session_from_issued(session)
      |> json(%{
        passkey_id: passkey.id,
        user_id: passkey.user_id,
        access_token: session.access_token,
        refresh_token: session.refresh_token,
        device_id: session.device_id
      })
    else
      {:error, :invalid_challenge} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{code: "invalid_challenge"}})

      {:error, :user_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{code: "user_not_found"}})

      {:error, reason} ->
        unexpected_error(
          conn,
          "passkey_register",
          reason,
          "passkey_registration_failed"
        )
    end
  end

  def passkey_assert_challenge(conn, params) do
    case Passkeys.issue_assertion_challenge(params) do
      {:ok, data} ->
        json(conn, data)

      {:error, {:rate_limited, retry}} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "rate_limited", retry_in: retry}})

      {:error, :invalid_identifier} ->
        # `user_id` UUID lookup is not accepted on this unauthenticated endpoint.
        # Return 400 rather than 404 to avoid leaking whether the UUID exists.
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "invalid_parameters"}})

      {:error, :user_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{code: "user_not_found"}})

      {:error, reason} ->
        unexpected_error(
          conn,
          "passkey_assert_challenge",
          reason,
          "passkey_assert_challenge_failed"
        )
    end
  end

  def passkey_assert(conn, params) do
    remember? = Map.get(params, "trust_device", true)

    device_info = %{
      id: Map.get(params, "device_id", Ecto.UUID.generate()),
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      ip: maybe_ip(conn)
    }

    with {:ok, %{user: user}} <- Passkeys.assert_passkey(params),
         {:ok, session} <-
           Sessions.start_session(
             user,
             device_info,
             remember_device?: remember?
           ) do
      conn =
        conn
        |> put_status(:created)
        |> ConnHelpers.put_session_from_issued(session)

      # Resolve and store the active family in the session for HomeLive.
      conn =
        case FamilyContext.resolve(user.id) do
          {:ok, family, _source} ->
            put_session(conn, "active_family_id", family.id)

          {:error, :no_family} ->
            conn
        end

      json(conn, session)
    else
      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{code: "invalid_credentials"}})

      {:error, :invalid_challenge} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{code: "invalid_challenge"}})

      {:error, {:rate_limited, retry_in}} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "rate_limited", retry_in: retry_in}})

      {:error, reason} ->
        unexpected_error(
          conn,
          "passkey_assert",
          reason,
          "passkey_assert_failed"
        )
    end
  end

  def refresh_session(conn, %{
        "device_id" => device_id,
        "refresh_token" => refresh_token
      }) do
    case Sessions.refresh_session(device_id, refresh_token) do
      {:ok, tokens} ->
        json(conn, tokens)

      {:error, {:rate_limited, retry_in}} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "rate_limited", retry_in: retry_in}})

      {:error, :trust_required} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: %{
            code: "reauth_required",
            reauth_required: true,
            methods: ["passkey", "magic"]
          }
        })

      {:error, :trust_expired} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: %{
            code: "reauth_required",
            reauth_required: true,
            methods: ["passkey", "magic"]
          }
        })

      {:error, :revoked} ->
        conn |> put_status(:unauthorized) |> json(%{error: %{code: "revoked"}})

      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: %{code: "invalid_refresh"}})
    end
  end

  def refresh_session(conn, _),
    do:
      conn
      |> put_status(:bad_request)
      |> json(%{error: %{code: "invalid_parameters"}})

  def revoke_device(conn, %{"device_id" => device_id}) do
    user_id = conn.assigns[:current_user_id]

    case Sessions.revoke_device(user_id, device_id) do
      {:ok, :revoked} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: %{code: "not_found"}})
    end
  end

  def revoke_device(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end

  def issue_magic_link(conn, %{"email" => email}) do
    case Identity.issue_magic_link(email) do
      {:ok, token, _} ->
        conn
        |> maybe_put_test_token(token)
        |> put_status(:accepted)
        |> json(%{status: "accepted"})

      {:error, {:rate_limited, retry}} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "rate_limited", retry_in: retry}})

      {:error, :user_not_found} ->
        conn
        |> put_status(:accepted)
        |> json(%{status: "accepted"})

      {:error, reason} ->
        unexpected_error(
          conn,
          "issue_magic_link",
          reason,
          "magic_link_issue_failed"
        )
    end
  end

  def issue_magic_link(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end

  def redeem_magic_link(conn, %{"token" => token}) do
    rate_limit_token!(conn, :magic_link, token)

    case Identity.redeem_magic_link(token) do
      {:ok, user} ->
        rate_limit_user!(conn, :magic_link, user.id)
        json(conn, %{user_id: user.id, username: user.username})

      {:error, :invalid} ->
        conn |> put_status(:not_found) |> json(%{error: %{code: "invalid"}})

      {:error, :expired} ->
        conn |> put_status(:gone) |> json(%{error: %{code: "expired"}})

      {:error, :used} ->
        conn |> put_status(:gone) |> json(%{error: %{code: "used"}})
    end
  end

  def redeem_magic_link(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end

  def issue_otp(conn, %{"email" => email}) do
    case Identity.issue_otp(email) do
      {:ok, code, _} ->
        conn
        |> maybe_put_test_token(code)
        |> put_status(:accepted)
        |> json(%{status: "accepted"})

      {:error, {:rate_limited, retry}} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "rate_limited", retry_in: retry}})

      {:error, :user_not_found} ->
        conn
        |> put_status(:accepted)
        |> json(%{status: "accepted"})

      {:error, reason} ->
        unexpected_error(conn, "issue_otp", reason, "otp_issue_failed")
    end
  end

  def issue_otp(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end

  def verify_otp(conn, %{"email" => email, "code" => code} = params) do
    rate_limit_token!(conn, :otp_verify, code)

    device_info = %{
      id: Map.get(params, "device_id", Ecto.UUID.generate()),
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      ip: maybe_ip(conn)
    }

    case Identity.verify_otp(email, code) do
      {:ok, user} ->
        rate_limit_user!(conn, :otp_verify, user.id)

        case Sessions.start_session(user, device_info, remember_device?: true) do
          {:ok, session} ->
            conn
            |> put_status(:created)
            |> ConnHelpers.put_session_from_issued(session)
            |> json(%{
              user_id: user.id,
              username: user.username,
              access_token: session.access_token,
              refresh_token: session.refresh_token,
              device_id: session.device_id
            })

          {:error, reason} ->
            unexpected_error(conn, "verify_otp", reason, "session_start_failed")
        end

      {:error, :invalid} ->
        conn |> put_status(:unauthorized) |> json(%{error: %{code: "invalid"}})

      {:error, :expired} ->
        conn |> put_status(:gone) |> json(%{error: %{code: "expired"}})

      {:error, :used} ->
        conn |> put_status(:gone) |> json(%{error: %{code: "used"}})

      {:error, {:rate_limited, _retry_in}} ->
        # Map rate-limited to the same 401/invalid response as a wrong code.
        # Returning 429 or a distinct error body would reveal that the email
        # address exists and is being actively tried, enabling enumeration.
        conn |> put_status(:unauthorized) |> json(%{error: %{code: "invalid"}})
    end
  end

  def verify_otp(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end

  def issue_recovery(conn, %{"user_id" => user_id}) do
    admin_id = conn.assigns[:current_user_id]

    case Recovery.issue_recovery(admin_id, user_id) do
      {:ok, token, _} ->
        conn
        |> maybe_put_test_token(token)
        |> put_status(:accepted)
        |> json(%{status: "accepted"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: %{code: "forbidden"}})

      {:error, reason} ->
        unexpected_error(
          conn,
          "issue_recovery",
          reason,
          "recovery_issue_failed"
        )
    end
  end

  def issue_recovery(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end

  def redeem_recovery(conn, %{"token" => token}) do
    rate_limit_token!(conn, :recovery, token)

    case Recovery.redeem_recovery(token) do
      {:ok, user} ->
        rate_limit_user!(conn, :recovery, user.id)
        json(conn, %{user_id: user.id, username: user.username})

      {:error, :invalid} ->
        conn |> put_status(:not_found) |> json(%{error: %{code: "invalid"}})

      {:error, :expired} ->
        conn |> put_status(:gone) |> json(%{error: %{code: "expired"}})
    end
  end

  def redeem_recovery(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end

  def bootstrap_admin(conn, %{"username" => username} = params) do
    opts = %{
      "family_name" => Map.get(params, "family_name")
    }

    case Onboarding.bootstrap_admin(username, opts) do
      {:ok,
       %{user: user, family: family, passkey_register_token: register_token}} ->
        Famichat.Accounts.FirstRun.reset_cache()

        conn
        |> put_status(:created)
        |> json(%{
          data: %{
            user_id: user.id,
            username: user.username,
            family_id: family.id,
            family_name: family.name,
            passkey_register_token: register_token
          }
        })

      {:error, :admin_exists} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: %{code: "admin_exists", message: "Bootstrap already completed"}
        })

      {:error, :username_required} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "username_required"}})

      {:error, :invalid_input} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: %{code: "invalid_input"}})

      {:error, %Ecto.Changeset{} = changeset} ->
        unexpected_error(conn, "bootstrap_admin", changeset, "bootstrap_failed")
    end
  end

  def bootstrap_admin(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end

  defp maybe_ip(conn) do
    conn.remote_ip
    |> case do
      nil -> "127.0.0.1"
      ip -> :inet.ntoa(ip) |> to_string()
    end
  end

  defp respond_with_passkey_challenge(conn, user_id) do
    with {:ok, user} <- Identity.fetch_user(user_id),
         {:ok, data} <- Passkeys.issue_registration_challenge(user) do
      json(conn, data)
    else
      {:error, :user_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{code: "user_not_found"}})

      {:error, {:rate_limited, retry}} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "rate_limited", retry_in: retry}})

      {:error, reason} ->
        unexpected_error(
          conn,
          "respond_with_passkey_challenge",
          reason,
          "passkey_challenge_failed"
        )
    end
  end

  defp unexpected_error(conn, context, reason, code) do
    Logger.warning(
      "[AuthController] #{context} unexpected error: #{inspect(reason)}"
    )

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: code}})
  end

  defp throttle!(conn, bucket, key, limit, interval) do
    case RateLimit.check(bucket, key,
           limit: limit,
           interval: interval
         ) do
      :ok ->
        :ok

      {:error, {:rate_limited, retry}} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: %{code: "rate_limited", retry_in: retry}})
        |> halt()
    end
  end

  defp rate_limit_token!(conn, bucket, token) do
    throttle!(conn, rate_limit_bucket(bucket, :token), token, 10, 60)
    throttle!(conn, rate_limit_bucket(bucket, :ip), maybe_ip(conn), 10, 60)
  end

  defp rate_limit_user!(conn, bucket, user_id) when is_binary(user_id) do
    throttle!(conn, rate_limit_bucket(bucket, :user), user_id, 10, 60)
  end

  defp rate_limit_user!(_conn, _bucket, _user_id), do: :ok

  defp maybe_put_test_token(conn, token) do
    if test_env?() && token do
      put_resp_header(conn, "x-test-token", encode_token(token))
    else
      conn
    end
  end

  defp encode_token(token) when is_binary(token), do: token

  defp encode_token(token) when is_map(token) or is_list(token),
    do: Jason.encode!(token)

  defp encode_token(token), do: Jason.encode!(token)

  defp handle_issue_invite_error(conn, {:error, {:rate_limited, retry_in}}) do
    conn
    |> put_status(:too_many_requests)
    |> json(%{error: %{code: "rate_limited", retry_in: retry_in}})
  end

  defp handle_issue_invite_error(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: %{code: "forbidden"}})
  end

  defp handle_issue_invite_error(conn, {:error, :missing_household_id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "missing_household_id"}})
  end

  defp handle_issue_invite_error(conn, {:error, :invalid_household_id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_household_id"}})
  end

  defp handle_issue_invite_error(conn, {:error, :invalid_role}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_role"}})
  end

  defp handle_issue_invite_error(conn, {:error, :invalid_parameters}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_parameters"}})
  end

  defp handle_issue_invite_error(conn, {:error, reason}) do
    unexpected_error(conn, "issue_invite", reason, "invite_issue_failed")
  end

  defp handle_complete_invite_error(conn, {:error, %Ecto.Changeset{}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "registration_failed"}})
  end

  defp handle_complete_invite_error(conn, {:error, :invalid_registration_token}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "invalid_registration_token"}})
  end

  defp handle_complete_invite_error(conn, {:error, :expired_registration_token}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "expired_registration_token"}})
  end

  defp handle_complete_invite_error(conn, {:error, :used_registration_token}) do
    conn
    |> put_status(:gone)
    |> json(%{error: %{code: "used_registration_token"}})
  end

  defp handle_complete_invite_error(conn, {:error, reason})
       when reason in [:user_not_found, :family_not_found] do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "invalid_invite"}})
  end

  defp handle_complete_invite_error(conn, {:error, :email_required}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "email_required"}})
  end

  defp handle_complete_invite_error(conn, {:error, :email_mismatch}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "email_mismatch"}})
  end

  defp handle_complete_invite_error(conn, {:error, :username_taken}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: %{code: "username_taken"}})
  end

  defp handle_complete_invite_error(conn, {:error, {:rate_limited, retry_in}}) do
    conn
    |> put_status(:too_many_requests)
    |> json(%{error: %{code: "rate_limited", retry_in: retry_in}})
  end

  defp handle_complete_invite_error(conn, {:error, reason}) do
    unexpected_error(
      conn,
      "complete_invite",
      reason,
      "invite_completion_failed"
    )
  end

  defp handle_complete_invite_fetch_error(conn, :expired) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "expired_registration_token"}})
  end

  defp handle_complete_invite_fetch_error(conn, :used) do
    conn
    |> put_status(:gone)
    |> json(%{error: %{code: "used_registration_token"}})
  end

  defp handle_complete_invite_fetch_error(conn, _reason) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "invalid_registration_token"}})
  end

  defp test_env? do
    Application.get_env(:famichat, :environment) == :test
  end

  defp rate_limit_bucket(:invite, :token), do: :auth_invite_token
  defp rate_limit_bucket(:invite, :ip), do: :auth_invite_ip
  defp rate_limit_bucket(:invite, :user), do: :auth_invite_user
  defp rate_limit_bucket(:invite_accept, :token), do: :auth_invite_accept_token
  defp rate_limit_bucket(:invite_accept, :ip), do: :auth_invite_accept_ip

  defp rate_limit_bucket(:invite_register, :token),
    do: :auth_invite_register_token

  defp rate_limit_bucket(:invite_register, :ip), do: :auth_invite_register_ip

  defp rate_limit_bucket(:invite_register, :user),
    do: :auth_invite_register_user

  defp rate_limit_bucket(:pairing, :token), do: :auth_pairing_token
  defp rate_limit_bucket(:pairing, :ip), do: :auth_pairing_ip
  defp rate_limit_bucket(:magic_link, :token), do: :auth_magic_link_token
  defp rate_limit_bucket(:magic_link, :ip), do: :auth_magic_link_ip
  defp rate_limit_bucket(:magic_link, :user), do: :auth_magic_link_user

  defp rate_limit_bucket(:magic_link_request, :token),
    do: :auth_magic_link_issue_token

  defp rate_limit_bucket(:magic_link_request, :ip),
    do: :auth_magic_link_issue_ip

  defp rate_limit_bucket(:otp_verify, :token), do: :auth_otp_verify_token
  defp rate_limit_bucket(:otp_verify, :ip), do: :auth_otp_verify_ip
  defp rate_limit_bucket(:otp_verify, :user), do: :auth_otp_verify_user
  defp rate_limit_bucket(:otp_request, :token), do: :auth_otp_issue_token
  defp rate_limit_bucket(:otp_request, :ip), do: :auth_otp_issue_ip
  defp rate_limit_bucket(:recovery, :token), do: :auth_recovery_token
  defp rate_limit_bucket(:recovery, :ip), do: :auth_recovery_ip
  defp rate_limit_bucket(:recovery, :user), do: :auth_recovery_user
  defp rate_limit_bucket(_, _), do: :auth_generic
end
