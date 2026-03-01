defmodule Famichat.Auth.Identity do
  @moduledoc """
  Identity context responsible for user lookup, credential issuance flows
  (magic links / OTP), and enrollment state bookkeeping.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Accounts,
      Famichat.Auth.RateLimit,
      Famichat.Auth.Tokens
    ]

  alias Ecto.Changeset
  import Ecto.Query
  alias Famichat.Accounts.{Passkey, User, UserToken}
  alias Famichat.Accounts.Username
  alias Famichat.Auth.RateLimit
  alias Famichat.Auth.Tokens
  alias Famichat.Auth.Tokens.IssuedToken
  alias Famichat.Repo

  @allowed_user_keys [
    :username,
    :email,
    :status,
    :password_hash,
    :confirmed_at,
    :last_login_at
  ]

  @allowed_user_key_map Map.new(@allowed_user_keys, fn key ->
                          {Atom.to_string(key), key}
                        end)

  @magic_link_bucket :"magic_link.issue"
  @otp_issue_bucket :"otp.issue"
  @otp_verify_bucket :"otp.verify"

  @doc "Normalizes email input (trim + lowercase)."
  @spec normalize_email(String.t()) :: String.t()
  def normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  @doc "Returns the SHA-256 hash of the normalized email."
  @spec email_hash(String.t()) :: binary()
  def email_hash(email) when is_binary(email) do
    :crypto.hash(:sha256, email)
  end

  @doc "Fetches a user by id."
  @spec fetch_user(Ecto.UUID.t()) :: {:ok, User.t()} | {:error, :user_not_found}
  def fetch_user(user_id) do
    case Repo.get(User, user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :user_not_found}
    end
  end

  @doc "Fetches a user by normalized email fingerprint."
  @spec fetch_user_by_email(String.t()) ::
          {:ok, User.t()} | {:error, :user_not_found}
  def fetch_user_by_email(email) when is_binary(email) do
    fingerprint =
      email
      |> normalize_email()
      |> email_hash()

    case Repo.get_by(User, email_fingerprint: fingerprint) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :user_not_found}
    end
  end

  @doc "Fetches a user by username."
  @spec fetch_user_by_username(String.t()) ::
          {:ok, User.t()} | {:error, :user_not_found}
  def fetch_user_by_username(username) when is_binary(username) do
    with fingerprint when is_binary(fingerprint) <-
           Username.fingerprint(username),
         %User{} = user <-
           Repo.get_by(User, username_fingerprint: fingerprint) do
      {:ok, user}
    else
      _ -> {:error, :user_not_found}
    end
  end

  @doc """
  Ensures a user exists for the provided attributes. Returns the existing user
  or inserts a new record using the permitted attribute set.
  """
  @spec ensure_user(map()) :: {:ok, User.t()} | {:error, term()}
  def ensure_user(attrs) when is_map(attrs) do
    permitted = permit_user_attrs(attrs)

    username =
      permitted
      |> Map.get(:username)
      |> normalize_username()

    if is_nil(username) or username == "" do
      {:error, :username_required}
    else
      case fetch_user_by_username(username) do
        {:ok, user} ->
          {:ok, user}

        {:error, :user_not_found} ->
          permitted
          |> Map.put(:username, username)
          |> insert_user()
      end
    end
  end

  @doc """
  Resolves a user based on a flexible identifier map (user_id, username, email)
  or raw username/email string.
  """
  @spec resolve_user(map() | String.t()) ::
          {:ok, User.t()} | {:error, :user_not_found}
  def resolve_user(%{"user_id" => user_id}) when is_binary(user_id),
    do: fetch_user(user_id)

  def resolve_user(%{"username" => username}) when is_binary(username),
    do: fetch_user_by_username(username)

  def resolve_user(%{"email" => email}) when is_binary(email),
    do: fetch_user_by_email(email)

  def resolve_user(identifier) when is_binary(identifier) do
    case fetch_user_by_username(identifier) do
      {:ok, user} -> {:ok, user}
      {:error, :user_not_found} -> fetch_user_by_email(identifier)
      other -> other
    end
  end

  def resolve_user(_), do: {:error, :user_not_found}

  defp insert_user(attrs) do
    defaults =
      attrs
      |> Map.put_new(:status, :active)
      |> Map.put_new(:confirmed_at, DateTime.utc_now())

    %User{}
    |> User.changeset(defaults)
    |> Repo.insert()
  end

  @doc """
  Whitelists user attributes for creation/update flows.
  """
  @spec permit_user_attrs(map()) :: map()
  def permit_user_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      case normalize_allowed_key(key) do
        {:ok, atom_key} -> Map.put(acc, atom_key, value)
        :error -> acc
      end
    end)
  end

  defp normalize_allowed_key(key) when is_atom(key) do
    if key in @allowed_user_keys, do: {:ok, key}, else: :error
  end

  defp normalize_allowed_key(key) when is_binary(key) do
    normalized =
      key
      |> String.trim()
      |> String.downcase()

    case Map.fetch(@allowed_user_key_map, normalized) do
      {:ok, atom_key} -> {:ok, atom_key}
      :error -> :error
    end
  end

  defp normalize_allowed_key(_), do: :error

  @doc """
  Returns `{id, username, username_fingerprint}` tuples sorted by insertion.
  Used for username collision audits.
  """
  @spec list_users_for_username_audit() ::
          list({Ecto.UUID.t(), String.t() | nil, binary() | nil})
  def list_users_for_username_audit do
    from(u in User,
      select: {u.id, u.username, u.username_fingerprint},
      order_by: [asc: u.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Applies the canonical username normalization pipeline.
  """
  @spec normalize_username(String.t()) :: String.t() | nil
  def normalize_username(username) when is_binary(username) do
    username
    |> String.trim()
    |> Username.normalize()
  end

  def normalize_username(_), do: nil

  @doc """
  Issues a magic link token for the provided email address.
  """
  @spec issue_magic_link(String.t()) ::
          {:ok, String.t(), UserToken.t()} | {:error, term()}
  def issue_magic_link(email) when is_binary(email) do
    normalized = normalize_email(email)

    case rate_limit(@magic_link_bucket, normalized, 5, 60) do
      :ok -> do_issue_magic_link(normalized)
      error -> error
    end
  end

  defp do_issue_magic_link(normalized_email) do
    with {:ok, user} <- fetch_user_by_email(normalized_email),
         payload <- %{"user_id" => user.id},
         {:ok, %IssuedToken{raw: token, record: record}} <-
           Tokens.issue(:magic_link, payload, user_id: user.id) do
      emit_identity_event(:magic_link_issued, %{user_id: user.id})
      {:ok, token, record}
    end
  end

  @doc """
  Redeems a magic link token, consuming it and returning the associated user.
  """
  @spec redeem_magic_link(String.t()) ::
          {:ok, User.t()} | {:error, term()}
  def redeem_magic_link(raw_token) when is_binary(raw_token) do
    Repo.transaction(fn ->
      with {:ok, token} <- Tokens.fetch(:magic_link, raw_token),
           {:ok, user} <- fetch_user(token.payload["user_id"]),
           {:ok, user} <- sync_enrollment_requirement(user),
           {:ok, _} <- Tokens.consume(token) do
        emit_identity_event(:magic_link_redeemed, %{user_id: user.id})
        user
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, %User{} = user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Issues an OTP for the provided email, returning the raw code and stored record.
  """
  @spec issue_otp(String.t()) ::
          {:ok, String.t(), UserToken.t()} | {:error, term()}
  def issue_otp(email) when is_binary(email) do
    normalized = normalize_email(email)

    case rate_limit(@otp_issue_bucket, normalized, 3, 60) do
      :ok -> do_issue_otp(normalized)
      error -> error
    end
  end

  defp secure_6digit_code do
    <<n::unsigned-32>> = :crypto.strong_rand_bytes(4)
    Integer.to_string(rem(n, 900_000) + 100_000)
  end

  defp do_issue_otp(normalized_email) do
    with {:ok, user} <- fetch_user_by_email(normalized_email) do
      code = secure_6digit_code()
      payload = %{"user_id" => user.id, "code" => code}
      hashed_email = email_hash(normalized_email)
      context = "otp:" <> Base.encode16(hashed_email, case: :lower)

      case Tokens.issue(:otp, payload,
             context: context,
             user_id: user.id,
             raw: code
           ) do
        {:ok, %IssuedToken{raw: raw_code, record: record}} ->
          emit_identity_event(:otp_issued, %{user_id: user.id})
          {:ok, raw_code, record}

        other ->
          other
      end
    end
  end

  @doc """
  Verifies an OTP code for the provided email address.
  """
  @spec verify_otp(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, term()}
  def verify_otp(email, code) when is_binary(email) and is_binary(code) do
    normalized = normalize_email(email)

    case rate_limit(@otp_verify_bucket, normalized, 5, 60) do
      :ok -> do_verify_otp(normalized, code)
      error -> error
    end
  end

  defp do_verify_otp(normalized_email, code) do
    hashed_email = email_hash(normalized_email)
    context = "otp:" <> Base.encode16(hashed_email, case: :lower)

    with {:ok, token} <- Tokens.fetch(:otp, code, context: context),
         true <- token.payload["code"] == code || {:error, :invalid},
         {:ok, user} <- fetch_user(token.payload["user_id"]),
         {:ok, _} <- Tokens.consume(token) do
      emit_identity_event(:otp_verified, %{user_id: user.id})
      {:ok, user}
    end
  end

  @doc """
  Re-synchronises the user's enrollment-required flag based on active passkeys.
  """
  @spec sync_enrollment_requirement(User.t()) ::
          {:ok, User.t()} | {:error, Changeset.t()}
  def sync_enrollment_requirement(%User{} = user) do
    active_count =
      from(p in Passkey,
        where: p.user_id == ^user.id and is_nil(p.disabled_at),
        select: count(p.id)
      )
      |> Repo.one()

    cond do
      active_count == 0 and is_nil(user.enrollment_required_since) ->
        user
        |> Changeset.change(enrollment_required_since: DateTime.utc_now())
        |> Repo.update()

      active_count == 0 ->
        {:ok, user}

      user.enrollment_required_since ->
        user
        |> Changeset.change(enrollment_required_since: nil)
        |> Repo.update()

      true ->
        {:ok, user}
    end
  end

  @doc """
  Marks the user as requiring enrollment.
  """
  @spec enter_enrollment_required_state(User.t()) ::
          {:ok, User.t()} | {:error, Changeset.t()}
  def enter_enrollment_required_state(%User{} = user) do
    user
    |> User.changeset(%{enrollment_required_since: DateTime.utc_now()})
    |> Repo.update()
  end

  ## Helpers -----------------------------------------------------------------

  defp rate_limit(bucket, key, limit, interval) do
    RateLimit.check(bucket, key, limit: limit, interval: interval)
  end

  defp emit_identity_event(action, metadata) do
    :telemetry.execute(
      [:famichat, :auth, :identity, action],
      %{count: 1},
      metadata
    )
  end
end
