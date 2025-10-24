defmodule Famichat.Auth.Authenticators do
  @moduledoc """
  WebAuthn challenge orchestration: issuance, verification, and
  consumption of passkey registration/assertion challenges.

  Responses include WebAuthn `publicKey` options alongside an opaque challenge
  handle that clients must echo during attestation/assertion.
  """

  use Boundary, exports: :all, deps: [Famichat, Famichat.Auth.Infra]

  import Ecto.Query

  alias Famichat.Accounts.Passkey
  alias Famichat.Accounts.User
  alias Famichat.Auth.Authenticators.Challenge
  alias Famichat.Auth.Infra.Instrumentation
  alias Famichat.Auth.Infra.Tokens, as: InfraTokens
  alias Famichat.Auth.TokenPolicy
  alias Famichat.Repo

  require Famichat.Auth.Infra.Instrumentation
  require Logger

  @challenge_size 32
  @registration_type :registration
  @assertion_type :assertion
  @challenge_salt "webauthn_challenge_v1"

  @doc """
  Issues a registration challenge for the provided user.
  """
  @spec issue_registration_challenge(User.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def issue_registration_challenge(%User{} = user, opts \\ []) do
    do_issue(@registration_type, user, opts)
  end

  @doc """
  Issues an assertion (authentication) challenge for the provided user.
  """
  @spec issue_assertion_challenge(User.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def issue_assertion_challenge(%User{} = user, opts \\ []) do
    do_issue(@assertion_type, user, opts)
  end

  @doc """
  Fetches (without consuming) a previously issued registration challenge
  using the opaque handle returned to the client.
  """
  @spec fetch_registration_challenge(String.t()) ::
          {:ok, Challenge.t()} | {:error, term()}
  def fetch_registration_challenge(handle) when is_binary(handle) do
    fetch_by_handle(@registration_type, handle)
  end

  @doc """
  Fetches (without consuming) a previously issued assertion challenge.
  """
  @spec fetch_assertion_challenge(String.t()) ::
          {:ok, Challenge.t()} | {:error, term()}
  def fetch_assertion_challenge(handle) when is_binary(handle) do
    fetch_by_handle(@assertion_type, handle)
  end

  @doc """
  Marks a challenge as consumed. Returns `{:error, :already_used}` if the
  handle has already been redeemed.
  """
  @spec consume_challenge(Challenge.t()) ::
          {:ok, Challenge.t()} | {:error, term()}
  def consume_challenge(%Challenge{id: id} = challenge) do
    now = DateTime.utc_now()

    {count, _} =
      from(c in Challenge,
        where: c.id == ^id and is_nil(c.consumed_at)
      )
      |> Repo.update_all(set: [consumed_at: now])

    if count == 1 do
      emit_challenge_event(:consumed, %{
        challenge_id: challenge.id,
        user_id: challenge.user_id
      })

      {:ok, %{challenge | consumed_at: now}}
    else
      {:error, :already_used}
    end
  end

  ## Implementation ---------------------------------------------------------

  defp do_issue(type, %User{} = user, opts)
       when type in [@registration_type, @assertion_type] do
    ttl = ttl_for(type)

    Instrumentation.span(
      [:famichat, :auth, :authenticators, :issue],
      %{user_id: user.id, type: type},
      do:
        case Repo.transaction(fn ->
               persist_challenge(user, type, ttl, opts)
             end) do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, reason}
        end
    )
  end

  defp ttl_for(@registration_type), do: TokenPolicy.default_ttl(:passkey_reg)
  defp ttl_for(@assertion_type), do: TokenPolicy.default_ttl(:passkey_assert)

  defp persist_challenge(user, type, ttl, opts) do
    challenge_bytes = :crypto.strong_rand_bytes(@challenge_size)
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)

    attrs = %{
      user_id: user.id,
      type: type,
      challenge: challenge_bytes,
      expires_at: expires_at
    }

    case Repo.insert(Challenge.changeset(%Challenge{}, attrs)) do
      {:ok, record} ->
        handle = sign_handle(record, ttl)

        response =
          base_response(
            user,
            type,
            handle,
            challenge_bytes,
            expires_at,
            opts
          )

        emit_challenge_event(:issued, %{
          type: type,
          user_id: user.id,
          challenge_id: record.id
        })

        response

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp base_response(
         user,
         type,
         handle,
         challenge_bytes,
         expires_at,
         opts
       ) do
    challenge_b64 = Base.url_encode64(challenge_bytes, padding: false)

    public_key_options =
      case type do
        @registration_type -> registration_options(user, challenge_b64, opts)
        @assertion_type -> assertion_options(user, challenge_b64, opts)
      end

    %{
      "challenge" => challenge_b64,
      "challenge_handle" => handle,
      "expires_at" => expires_at,
      "publicKey" => public_key_options
    }
  end

  defp registration_options(user, challenge_b64, _opts) do
    loaded_user = Repo.preload(user, :passkeys)

    exclude =
      Enum.map(loaded_user.passkeys, fn %Passkey{credential_id: cred} ->
        %{
          "type" => "public-key",
          "id" => Base.encode64(cred, padding: false)
        }
      end)

    %{
      "attestation" => "none",
      "authenticatorSelection" => %{
        "residentKey" => "preferred",
        "userVerification" => "preferred"
      },
      "challenge" => challenge_b64,
      "excludeCredentials" => exclude,
      "pubKeyCredParams" => pubkey_cred_params(),
      "rp" => %{"id" => rp_id(), "name" => rp_name()},
      "timeout" => 120_000,
      "user" => %{
        "id" => encode_user_handle(user.id),
        "name" => user.username || "famichat-user",
        "displayName" => user.username || "Famichat User"
      }
    }
  end

  defp assertion_options(user, challenge_b64, _opts) do
    loaded_user = Repo.preload(user, :passkeys)

    allow_credentials =
      Enum.map(loaded_user.passkeys, fn %Passkey{credential_id: cred} ->
        %{
          "id" => Base.encode64(cred, padding: false),
          "type" => "public-key",
          "transports" => default_transports()
        }
      end)

    %{
      "challenge" => challenge_b64,
      "rpId" => rp_id(),
      "timeout" => 60_000,
      "allowCredentials" => allow_credentials,
      "userVerification" => "preferred"
    }
  end

  defp pubkey_cred_params do
    [
      %{"type" => "public-key", "alg" => -7},
      %{"type" => "public-key", "alg" => -257}
    ]
  end

  defp default_transports, do: ["platform", "internal", "hybrid"]

  defp encode_user_handle(uuid) when is_binary(uuid) do
    case Ecto.UUID.dump(uuid) do
      {:ok, binary} ->
        Base.encode64(binary, padding: false)

      :error ->
        Logger.warning(
          "[Authenticators] Invalid user UUID for handle: #{inspect(uuid)}"
        )

        raise ArgumentError, "user.id must be a valid UUID"
    end
  end

  defp rp_config do
    Application.get_env(:famichat, :webauthn, [])
  end

  defp rp_id do
    rp_config() |> Keyword.get(:rp_id, "localhost")
  end

  defp rp_name do
    rp_config() |> Keyword.get(:rp_name, "Famichat")
  end

  defp sign_handle(%Challenge{id: id, type: type}, ttl) do
    payload = %{"challenge_id" => id, "type" => Atom.to_string(type)}
    InfraTokens.sign(payload, @challenge_salt, ttl: ttl)
  end

  defp fetch_by_handle(type, handle) do
    ttl = ttl_for(type)

    Instrumentation.span(
      [:famichat, :auth, :authenticators, :fetch],
      %{type: type},
      do: do_fetch_by_handle(type, handle, ttl)
    )
  end

  defp do_fetch_by_handle(type, handle, ttl) do
    result =
      with {:ok, %{"challenge_id" => id, "type" => token_type}} <-
             InfraTokens.verify(handle, @challenge_salt, max_age: ttl),
           true <-
             token_type == Atom.to_string(type) || {:error, :type_mismatch},
           %Challenge{} = challenge <- Repo.get(Challenge, id),
           :ok <- ensure_type(challenge, type),
           :ok <- ensure_fresh(challenge) do
        {:ok, challenge}
      else
        {:error, reason}
        when reason in [:expired, :invalid, :invalid_challenge, :type_mismatch] ->
          emit_challenge_event(:invalid, %{type: type, reason: reason})
          adapt_fetch_error(reason)

        nil ->
          emit_challenge_event(:invalid, %{type: type, reason: :not_found})
          {:error, :invalid_challenge}

        false ->
          emit_challenge_event(:invalid, %{type: type, reason: :type_mismatch})
          {:error, :invalid_challenge}
      end

    result
  end

  defp adapt_fetch_error(:expired), do: {:error, :expired}
  defp adapt_fetch_error(:invalid), do: {:error, :invalid_challenge}
  defp adapt_fetch_error(:invalid_challenge), do: {:error, :invalid_challenge}
  defp adapt_fetch_error(:type_mismatch), do: {:error, :invalid_challenge}

  defp emit_challenge_event(kind, metadata) do
    event =
      case kind do
        :issued -> [:famichat, :auth, :authenticators, :challenge_issued]
        :consumed -> [:famichat, :auth, :authenticators, :challenge_consumed]
        :invalid -> [:famichat, :auth, :authenticators, :challenge_invalid]
      end

    :telemetry.execute(event, %{count: 1}, metadata)
  end

  defp ensure_type(%Challenge{type: type}, type), do: :ok
  defp ensure_type(_challenge, _type), do: {:error, :invalid_challenge}

  defp ensure_fresh(%Challenge{expires_at: expires_at, consumed_at: nil}) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
      :ok
    else
      {:error, :expired}
    end
  end

  defp ensure_fresh(%Challenge{consumed_at: %DateTime{}}),
    do: {:error, :already_used}
end
