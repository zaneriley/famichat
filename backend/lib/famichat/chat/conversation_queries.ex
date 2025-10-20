defmodule Famichat.Chat.ConversationQueries do
  @moduledoc false

  import Ecto.Query

  alias Famichat.Accounts.{FamilyMembership, User}
  alias Famichat.Chat.{Conversation, ConversationParticipant}

  @type membership_query :: Ecto.Query.t()
  @type conversations_query :: Ecto.Query.t()

  @doc """
  Returns a composable query for the members of `conversation`.

  * For `:family` conversations, membership is derived from `FamilyMembership`.
  * For all other types, membership comes from `ConversationParticipant`.
  """
  @spec members(Conversation.t()) :: membership_query()
  def members(%Conversation{conversation_type: :family, family_id: family_id}) do
    from u in User,
      join: m in FamilyMembership,
      on: m.user_id == u.id,
      where: m.family_id == ^family_id
  end

  def members(%Conversation{id: conversation_id}) do
    from u in User,
      join: p in ConversationParticipant,
      on: p.user_id == u.id,
      where: p.conversation_id == ^conversation_id
  end

  @doc """
  Returns a composable query of conversations the given user participates in,
  combining explicit and implicit (family) memberships.
  """
  @spec for_user(Ecto.UUID.t()) :: conversations_query()
  def for_user(user_id) do
    explicit_ids =
      from p in ConversationParticipant,
        where: p.user_id == ^user_id,
        select: p.conversation_id

    implicit_ids =
      from c in Conversation,
        join: m in FamilyMembership,
        on: m.family_id == c.family_id,
        where: c.conversation_type == :family and m.user_id == ^user_id,
        select: c.id

    from c in Conversation,
      distinct: true,
      where:
        c.id in subquery(explicit_ids) or
          c.id in subquery(implicit_ids)
  end
end
