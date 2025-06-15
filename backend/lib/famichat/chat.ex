defmodule Famichat.Chat do
  @moduledoc """
  The Chat context.
  """

  use Ecto.Schema
  require Logger
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Famichat.Chat.Conversation
  alias Famichat.Chat.ConversationVisibilityService
  alias Famichat.Chat.{Family, User}
  alias Famichat.Repo

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
    try do
      %User{}
      |> User.changeset(attrs)
      |> Repo.insert()
    rescue
      _ -> {:error, :invalid_input}
    end
  end

  def create_user(_), do: {:error, :invalid_input}

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

  ## Conversation Visibility

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
  Checks if a user is authorized for a conversation.

  ## Parameters
    - socket: The Phoenix socket
    - user_id: The ID of the user
    - conversation_id: The ID of the conversation
    - conversation_type: The type of the conversation ("self", "direct", "group", "family")

  ## Returns
    - `true` if the user is authorized
    - `false` otherwise
  """
  def user_authorized_for_conversation?(
        socket,
        user_id,
        conversation_id,
        conversation_type
      ) do
    Logger.debug(
      "user_authorized_for_conversation? called with user_id: #{inspect(user_id)}, " <>
        "conversation_id: #{inspect(conversation_id)}, conversation_type: #{inspect(conversation_type)}"
    )

    # Placeholder authorization logic
    case conversation_type do
      "self" -> conversation_id == user_id
      # For "direct", "group", "family", return true for now
      _ -> true
    end
  end
end
