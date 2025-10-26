defmodule Famichat.Auth.Identity.MagicLinkAdversarialTest do
  use Famichat.DataCase, async: false

  alias Famichat.Accounts.UserToken
  alias Famichat.Auth.Identity
  alias Famichat.ChatFixtures
  alias Famichat.Repo
  alias Famichat.TestSupport.{RedactionHelpers, TelemetryHelpers}

  describe "redeem_magic_link/1 adversarial paths" do
    test "expired magic link cannot be redeemed and telemetry stays redacted" do
      email = ChatFixtures.unique_user_email()
      _user = ChatFixtures.user_fixture(%{email: email})

      {:ok, token, record} = Identity.issue_magic_link(email)

      record
      |> UserToken.changeset(%{
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })
      |> Repo.update!()

      events =
        TelemetryHelpers.capture(
          [[:famichat, :auth, :identity, :magic_link_redeemed]],
          fn ->
            assert {:error, :expired} = Identity.redeem_magic_link(token)
          end
        )

      Enum.each(events, fn %{metadata: metadata} ->
        RedactionHelpers.pii_free!(metadata)
      end)
    end

    test "tampered magic link is rejected and telemetry stays redacted" do
      email = ChatFixtures.unique_user_email()
      _user = ChatFixtures.user_fixture(%{email: email})

      {:ok, token, _record} = Identity.issue_magic_link(email)
      tampered_token = tamper(token)

      events =
        TelemetryHelpers.capture(
          [[:famichat, :auth, :identity, :magic_link_redeemed]],
          fn ->
            assert {:error, :invalid} =
                     Identity.redeem_magic_link(tampered_token)
          end
        )

      Enum.each(events, fn %{metadata: metadata} ->
        RedactionHelpers.pii_free!(metadata)
      end)
    end
  end

  defp tamper(<<_::binary-size(1), rest::binary>>), do: "X" <> rest
  defp tamper(token), do: token
end
