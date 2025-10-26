defmodule Famichat.Chat.MessageAuthorizationRedactionTest do
  use Famichat.DataCase, async: false

  alias Famichat.Chat.ConversationAccess
  alias Famichat.Chat.ConversationService
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.{RedactionHelpers, TelemetryHelpers}

  @event [:famichat, :conversation, :authorization_denied]

  test "authorization failures emit redacted telemetry" do
    family = ChatFixtures.family_fixture()
    user1 = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})
    user2 = ChatFixtures.user_fixture(%{family_id: family.id, role: :member})
    outsider = ChatFixtures.user_fixture()

    {:ok, conversation} =
      ConversationService.create_direct_conversation(user1.id, user2.id)

    events =
      TelemetryHelpers.capture([@event], fn ->
        assert {:error, :not_participant} =
                 ConversationAccess.authorize(
                   conversation,
                   outsider.id,
                   :send_message
                 )
      end)

    assert [%{metadata: metadata}] = events
    assert metadata[:reason] == :not_participant
    assert metadata[:user_id] == outsider.id
    RedactionHelpers.pii_free!(metadata)
  end
end
