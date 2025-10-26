defmodule Famichat.Chat.ConversationDirectRaceTest do
  use Famichat.DataCase, async: false

  import Ecto.Query
  alias Famichat.Chat.Conversation
  alias Famichat.Chat.ConversationService
  alias Famichat.ChatFixtures
  alias Famichat.Repo

  test "concurrent direct conversation creation results in a single record" do
    family = ChatFixtures.family_fixture()
    user1 = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})
    user2 = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})

    task_fun = fn ->
      ConversationService.create_direct_conversation(user1.id, user2.id)
    end

    [res1, res2] =
      [Task.async(task_fun), Task.async(task_fun)]
      |> Enum.map(&Task.await(&1, 2000))

    assert Enum.all?([res1, res2], &match?({:ok, _}, &1))

    {:ok, conv1} = res1
    {:ok, conv2} = res2
    assert conv1.id == conv2.id

    direct_key = Conversation.compute_direct_key(user1.id, user2.id, family.id)

    count =
      Conversation
      |> where(
        [c],
        c.direct_key == ^direct_key and c.conversation_type == ^:direct
      )
      |> Repo.aggregate(:count, :id)

    assert count == 1
  end
end
