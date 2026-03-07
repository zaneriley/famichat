defmodule Famichat.Chat do
  @moduledoc """
  The Chat context.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat,
      Famichat.Accounts,
      Famichat.Communities,
      Famichat.Auth.Households,
      Famichat.Auth.Identity
    ]

  import Ecto.Query, warn: false
  alias Famichat.Repo
  alias Famichat.Communities
  alias Famichat.Chat.Family
  alias Famichat.Accounts.User
  alias Famichat.Auth.Households
  alias Famichat.Auth.Identity

  @doc """
  Returns the list of families.

  ## Examples

      iex> list_families()
      [%Family{}, ...]

  """
  def list_families do
    Repo.all(Family)
  end

  @doc """
  Gets a single family.

  Raises `Ecto.NoResultsError` if the Family does not exist.

  ## Examples

      iex> get_family!(123)
      %Family{}

      iex> get_family!(456)
      ** (Ecto.NoResultsError)

  """
  def get_family!(id), do: Repo.get!(Family, id)

  @doc """
  Creates a family.

  ## Examples

      iex> create_family(%{field: value})
      {:ok, %Family{}}

      iex> create_family(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_family(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> maybe_put_family_community_id()

    %Family{}
    |> Family.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Creates a user.

  ## Parameters
    * `attrs` - Map of attributes for the user

  ## Returns
    * `{:ok, user}` - The created user
    * `{:error, changeset}` - If the user is invalid
    * `{:error, :invalid_input}` - If the input is invalid

  ## Examples

      iex> create_user(%{field: value})
      {:ok, %User{}}

      iex> create_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_user(map()) ::
          {:ok, User.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :invalid_input}
  def create_user(attrs) when is_map(attrs) do
    family_id = Map.get(attrs, :family_id) || Map.get(attrs, "family_id")
    role = Map.get(attrs, :role) || Map.get(attrs, "role")
    community_id = resolve_user_community_id(attrs, family_id)

    user_attrs =
      attrs
      |> Map.drop([:family_id, :role, "family_id", "role"])
      |> Identity.permit_user_attrs()
      |> Map.put(:community_id, community_id)

    normalized_role = normalize_role(role)

    Repo.transaction(fn ->
      with {:ok, user} <- Identity.ensure_user(user_attrs),
           {:ok, _} <- ensure_membership(user.id, family_id, normalized_role) do
        user
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          Repo.rollback(changeset)

        {:error, :username_required} ->
          Repo.rollback(User.changeset(%User{}, user_attrs))

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_user(_), do: {:error, :invalid_input}

  defp resolve_user_community_id(attrs, family_id) do
    explicit =
      Map.get(attrs, :community_id) ||
        Map.get(attrs, "community_id")

    cond do
      is_binary(family_id) ->
        case Repo.get(Family, family_id) do
          %Family{community_id: community_id} when is_binary(community_id) ->
            community_id

          _ ->
            explicit || Communities.current_community!().id
        end

      is_binary(explicit) ->
        explicit

      true ->
        Communities.current_community!().id
    end
  end

  defp maybe_put_family_community_id(attrs) do
    if Map.has_key?(attrs, :community_id) or Map.has_key?(attrs, "community_id") do
      attrs
    else
      Map.put(attrs, :community_id, Communities.current_community!().id)
    end
  end

  defp ensure_membership(_user_id, nil, _role), do: {:ok, :skipped}

  defp ensure_membership(user_id, family_id, role) do
    Households.upsert_membership(user_id, family_id, role)
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  defp normalize_role(:admin), do: :admin
  defp normalize_role(:member), do: :member
  defp normalize_role("admin"), do: :admin
  defp normalize_role("member"), do: :member
  defp normalize_role(_), do: :member

  ## Conversation Visibility

  alias Famichat.Chat.ConversationService

  @doc """
  Creates a direct conversation between two users.

  Delegates to `Famichat.Chat.ConversationService.create_direct_conversation/2`.
  """
  defdelegate create_direct_conversation(user1_id, user2_id),
    to: ConversationService

  alias Famichat.Chat.Conversation
  alias Famichat.Chat.ConversationSecurityKeyPackagePolicy
  alias Famichat.Chat.ConversationSecurityRecoveryLifecycle
  alias Famichat.Chat.ConversationSecurityRevocationLifecycle
  alias Famichat.Chat.ConversationVisibilityService
  alias Famichat.Chat.DeviceMlsRemoval

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
  @spec hide_conversation(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Conversation.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def hide_conversation(conversation_id, user_id) do
    ConversationVisibilityService.hide_conversation(conversation_id, user_id)
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
  @spec unhide_conversation(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Conversation.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def unhide_conversation(conversation_id, user_id) do
    ConversationVisibilityService.unhide_conversation(conversation_id, user_id)
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
  @spec list_visible_conversations(Ecto.UUID.t(), keyword()) :: [
          Conversation.t()
        ]
  def list_visible_conversations(user_id, opts \\ []) do
    ConversationVisibilityService.list_visible_conversations(user_id, opts)
  end

  @doc """
  Ensures durable key-package inventory exists for the client identity and replenishes if below threshold.
  """
  @spec ensure_conversation_security_key_packages(String.t(), keyword()) ::
          {:ok, map()} | {:error, atom(), map()}
  def ensure_conversation_security_key_packages(client_id, opts \\ []) do
    ConversationSecurityKeyPackagePolicy.ensure_inventory(client_id, opts)
  end

  @doc """
  Consumes one key package for the client identity and enforces replenish policy.
  """
  @spec consume_conversation_security_key_package(String.t(), keyword()) ::
          {:ok, map()} | {:error, atom(), map()}
  def consume_conversation_security_key_package(client_id, opts \\ []) do
    ConversationSecurityKeyPackagePolicy.consume_key_package(client_id, opts)
  end

  @doc """
  Rotates stale key packages for one client identity.
  """
  @spec rotate_stale_conversation_security_key_package_inventory(
          String.t(),
          keyword()
        ) :: {:ok, map()} | {:error, atom(), map()}
  def rotate_stale_conversation_security_key_package_inventory(
        client_id,
        opts \\ []
      ) do
    ConversationSecurityKeyPackagePolicy.rotate_stale_inventory(client_id, opts)
  end

  @doc """
  Rotates stale key packages across client identities using policy defaults.
  """
  @spec rotate_stale_conversation_security_key_package_inventories(keyword()) ::
          {:ok, map()} | {:error, atom(), map()}
  def rotate_stale_conversation_security_key_package_inventories(opts \\ []) do
    ConversationSecurityKeyPackagePolicy.rotate_stale_inventories(opts)
  end

  @doc """
  Recovers durable conversation security state using rejoin material.

  Recovery is idempotent per `{conversation_id, recovery_ref}`.
  """
  @spec recover_conversation_security_state(
          Ecto.UUID.t(),
          String.t(),
          map()
        ) :: {:ok, map()} | {:error, atom(), map()}
  def recover_conversation_security_state(
        conversation_id,
        recovery_ref,
        attrs \\ %{}
      ) do
    ConversationSecurityRecoveryLifecycle.recover_conversation_security_state(
      conversation_id,
      recovery_ref,
      attrs
    )
  end

  @doc """
  Stages conversation-security revocation intents for all conversations that include the client.

  The operation is idempotent per `{conversation_id, revocation_ref}` and writes
  revocation journal rows in `:pending_commit` state.

  `revocation_ref` is an idempotency key and must be stable across retries
  (for example, do not include timestamps).
  """
  @spec stage_client_revocation(String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def stage_client_revocation(client_id, revocation_ref, attrs \\ %{}) do
    ConversationSecurityRevocationLifecycle.stage_client_revocation(
      client_id,
      revocation_ref,
      attrs
    )
  end

  @doc """
  Stages conversation-security revocation intents for all conversations that include the user.

  The operation is idempotent per `{conversation_id, revocation_ref}` and writes
  revocation journal rows in `:pending_commit` state.

  `revocation_ref` is an idempotency key and must be stable across retries
  (for example, do not include timestamps).
  """
  @spec stage_user_revocation(Ecto.UUID.t(), String.t(), map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def stage_user_revocation(user_id, revocation_ref, attrs \\ %{}) do
    ConversationSecurityRevocationLifecycle.stage_user_revocation(
      user_id,
      revocation_ref,
      attrs
    )
  end

  @doc """
  Seals a staged revocation for a conversation once commit/epoch outcome is known.

  Requires a non-negative `committed_epoch` when transitioning from
  `:in_progress`/`:pending_commit` to `:completed`.
  """
  @spec complete_conversation_revocation(Ecto.UUID.t(), String.t(), map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def complete_conversation_revocation(
        conversation_id,
        revocation_ref,
        attrs \\ %{}
      ) do
    ConversationSecurityRevocationLifecycle.complete_conversation_revocation(
      conversation_id,
      revocation_ref,
      attrs
    )
  end

  @doc """
  Marks a staged revocation as failed with an explicit error code.

  Required attrs for state transition: `error_code`.
  """
  @spec fail_conversation_revocation(Ecto.UUID.t(), String.t(), map()) ::
          {:ok, map()} | {:error, atom(), map()}
  def fail_conversation_revocation(
        conversation_id,
        revocation_ref,
        attrs \\ %{}
      ) do
    ConversationSecurityRevocationLifecycle.fail_conversation_revocation(
      conversation_id,
      revocation_ref,
      attrs
    )
  end

  @doc """
  Fires off an async task to remove the revoked device from every MLS group
  (conversation) the user belongs to.

  Session revocation is the hard guarantee and must already have happened
  before calling this function. MLS removal is best-effort: failures are
  logged and written to the revocation journal, but they do not propagate
  to the caller and do not affect the return value.

  The `revocation_ref` is the same idempotency key used for session-level
  revocation staging so the two journal rows can be correlated.

  Returns `:ok` immediately; all MLS work happens in a spawned task.
  """
  @spec remove_device_from_mls_groups(
          Ecto.UUID.t(),
          String.t(),
          String.t()
        ) :: :ok
  def remove_device_from_mls_groups(user_id, device_id, revocation_ref) do
    DeviceMlsRemoval.remove_async(user_id, device_id, revocation_ref)
  end
end
