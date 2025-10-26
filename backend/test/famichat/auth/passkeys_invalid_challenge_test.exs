defmodule Famichat.Auth.Passkeys.InvalidChallengeTest do
  use Famichat.DataCase, async: true

  alias Famichat.Auth.Passkeys
  alias Famichat.ChatFixtures
  alias Famichat.TestSupport.{RedactionHelpers, TelemetryHelpers}

  @invalid_event [:famichat, :auth, :passkeys, :challenge_invalid]

  test "issuing challenge for unknown identifier is rejected" do
    events =
      TelemetryHelpers.capture([@invalid_event], fn ->
        assert {:error, :user_not_found} =
                 Passkeys.issue_assertion_challenge("missing-user")
      end)

    Enum.each(events, fn %{metadata: metadata} ->
      RedactionHelpers.pii_free!(metadata)
    end)
  end

  test "tampered challenge handle is invalid" do
    user = ChatFixtures.user_fixture()
    {:ok, challenge} = Passkeys.issue_assertion_challenge(user)

    handle = Map.fetch!(challenge, "challenge_handle")
    tampered_handle = tamper(handle)

    events =
      TelemetryHelpers.capture([@invalid_event], fn ->
        assert {:error, :invalid_challenge} =
                 Passkeys.fetch_assertion_challenge(tampered_handle)
      end)

    assert [%{metadata: metadata}] = events

    assert metadata[:reason] in [
             :invalid_challenge,
             :not_found,
             :type_mismatch,
             :invalid
           ]

    RedactionHelpers.pii_free!(metadata)
  end

  defp tamper(<<_::binary-size(1), rest::binary>>), do: "x" <> rest
  defp tamper(handle), do: handle
end
