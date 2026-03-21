defmodule Famichat.Auth.Passkeys.RefactorGuardTest do
  @moduledoc """
  Regression-guard tests that lock down observable return-value behavior
  of `Famichat.Auth.Passkeys` public functions before refactoring.

  Every test:
  - calls a PUBLIC function
  - asserts on the RETURN VALUE (not internal state, telemetry, or DB rows —
    except where Group 2 must verify the side-effect of disable)
  - uses real DB (Ecto sandbox), real functions — NO mocks
  """

  use Famichat.DataCase, async: false

  import Famichat.ChatFixtures

  alias Famichat.Accounts.Passkey
  alias Famichat.Auth.Passkeys
  alias Famichat.Repo

  setup do
    Famichat.Accounts.FirstRun.force_bootstrapped!()

    on_exit(fn ->
      Famichat.Accounts.FirstRun.reset_cache()
    end)

    %{user: user_fixture()}
  end

  # -------------------------------------------------------------------------
  # Helper: insert a raw passkey row for a user (no WebAuthn ceremony needed)
  # -------------------------------------------------------------------------
  defp insert_passkey!(user, opts \\ []) do
    disabled_at = Keyword.get(opts, :disabled_at, nil)

    Repo.insert!(%Passkey{
      user_id: user.id,
      credential_id: :crypto.strong_rand_bytes(32),
      public_key: :crypto.strong_rand_bytes(32),
      sign_count: 0,
      disabled_at: disabled_at
    })
  end

  # =========================================================================
  # Group 1: issue_assertion_challenge/1 dispatch paths
  # =========================================================================
  describe "issue_assertion_challenge/1 dispatch paths" do
    test "1. empty map → discoverable challenge", _ctx do
      assert {:ok, result} = Passkeys.issue_assertion_challenge(%{})

      assert is_binary(result["challenge"])
      assert is_binary(result["challenge_handle"])
      assert %{"allowCredentials" => []} = result["public_key_options"]
    end

    test "2. map with only unknown keys → discoverable challenge", _ctx do
      assert {:ok, result} = Passkeys.issue_assertion_challenge(%{"foo" => "bar"})

      assert is_binary(result["challenge"])
      assert is_binary(result["challenge_handle"])
      assert %{"allowCredentials" => []} = result["public_key_options"]
    end

    test "3. user_id only (no username/email) → {:error, :invalid_identifier}", %{user: user} do
      assert {:error, :invalid_identifier} =
               Passkeys.issue_assertion_challenge(%{"user_id" => user.id})
    end

    test "4. user_id + username → succeeds (user_id silently dropped, username wins)", %{
      user: user
    } do
      result =
        Passkeys.issue_assertion_challenge(%{
          "user_id" => user.id,
          "username" => user.username
        })

      assert {:ok, payload} = result
      assert is_binary(payload["challenge"])
      assert is_binary(payload["challenge_handle"])
    end

    test "5. identifier key → normalized to username lookup", _ctx do
      # Create a user with a known username, then look up via "identifier"
      known_user = user_fixture(%{username: "identifiertest"})
      _pk = insert_passkey!(known_user)

      result = Passkeys.issue_assertion_challenge(%{"identifier" => "identifiertest"})
      assert {:ok, payload} = result
      assert is_binary(payload["challenge"])
      assert is_binary(payload["challenge_handle"])
    end

    test "6. username key → user-bound challenge with allowCredentials", %{user: user} do
      _pk = insert_passkey!(user)

      assert {:ok, payload} =
               Passkeys.issue_assertion_challenge(%{"username" => user.username})

      opts = payload["public_key_options"]
      assert is_list(opts["allowCredentials"])
      assert length(opts["allowCredentials"]) > 0
    end

    test "7. binary string → user-bound challenge", _ctx do
      str_user = user_fixture(%{username: "stringlookupuser"})
      _pk = insert_passkey!(str_user)

      assert {:ok, payload} = Passkeys.issue_assertion_challenge("stringlookupuser")
      assert is_binary(payload["challenge"])
      assert is_binary(payload["challenge_handle"])
    end
  end

  # =========================================================================
  # Group 2: disable_all_for_user/1
  # =========================================================================
  describe "disable_all_for_user/1" do
    test "1. user with 2 active passkeys → :ok, both disabled", %{user: user} do
      pk1 = insert_passkey!(user)
      pk2 = insert_passkey!(user)

      assert :ok = Passkeys.disable_all_for_user(user.id)

      reloaded1 = Repo.get!(Passkey, pk1.id)
      reloaded2 = Repo.get!(Passkey, pk2.id)
      refute is_nil(reloaded1.disabled_at)
      refute is_nil(reloaded2.disabled_at)
    end

    test "2. user with 0 passkeys → :ok (no-op)", %{user: user} do
      assert :ok = Passkeys.disable_all_for_user(user.id)
    end

    test "3. after disable, has_active_passkey? returns false", %{user: user} do
      _pk = insert_passkey!(user)
      assert Passkeys.has_active_passkey?(user.id) == true

      :ok = Passkeys.disable_all_for_user(user.id)
      assert Passkeys.has_active_passkey?(user.id) == false
    end
  end

  # =========================================================================
  # Group 3: has_active_passkey?/1
  # =========================================================================
  describe "has_active_passkey?/1" do
    test "1. user with active passkey → true", %{user: user} do
      _pk = insert_passkey!(user)
      assert Passkeys.has_active_passkey?(user.id) == true
    end

    test "2. user with no passkeys → false", %{user: user} do
      assert Passkeys.has_active_passkey?(user.id) == false
    end

    test "3. user with only disabled passkeys → false", %{user: user} do
      _pk = insert_passkey!(user, disabled_at: DateTime.utc_now())
      assert Passkeys.has_active_passkey?(user.id) == false
    end
  end

  # =========================================================================
  # Group 4: consume_challenge replay guard
  # =========================================================================
  describe "consume_challenge/1 replay guard" do
    test "1. second consume returns {:error, :already_used}", %{user: user} do
      {:ok, payload} = Passkeys.issue_registration_challenge(user)
      handle = payload["challenge_handle"]
      {:ok, challenge} = Passkeys.fetch_registration_challenge(handle)

      assert {:ok, _consumed} = Passkeys.consume_challenge(challenge)
      assert {:error, :already_used} = Passkeys.consume_challenge(challenge)
    end
  end

  # =========================================================================
  # Group 5: exchange_registration_token/1 error paths
  # =========================================================================
  describe "exchange_registration_token/1 error paths" do
    test "1. garbage token → error tuple", _ctx do
      result = Passkeys.exchange_registration_token("totally-invalid-garbage-token")
      assert {:error, _reason} = result
    end

    test "2. empty string → error tuple", _ctx do
      result = Passkeys.exchange_registration_token("")
      assert {:error, _reason} = result
    end
  end
end
