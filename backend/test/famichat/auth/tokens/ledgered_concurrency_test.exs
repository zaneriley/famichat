defmodule Famichat.Auth.Tokens.LedgeredConcurrencyTest do
  use Famichat.DataCase, async: false

  alias Famichat.Accounts.UserToken
  alias Famichat.Auth.Tokens
  alias Famichat.Auth.Tokens.Storage
  alias Famichat.ChatFixtures
  alias Famichat.Repo

  test "only one consumer succeeds for a ledgered token under concurrency" do
    user = ChatFixtures.user_fixture()

    {:ok, issued_token} =
      Tokens.issue(:magic_link, %{"user_id" => user.id}, user_id: user.id)

    raw = issued_token.raw
    token_id = issued_token.record.id

    consume_fun = fn ->
      Repo.transaction(fn ->
        case Tokens.fetch(:magic_link, raw) do
          {:ok, token} -> Tokens.consume(token)
          error -> error
        end
      end)
    end

    [res1, res2] =
      [Task.async(consume_fun), Task.async(consume_fun)]
      |> Enum.map(&Task.await(&1, 2000))

    success_count = Enum.count([res1, res2], &match?({:ok, {:ok, _}}, &1))
    error_count = Enum.count([res1, res2], &match?({:ok, {:error, _}}, &1))

    assert success_count == 1
    assert error_count == 1

    stored = Repo.get!(UserToken, token_id)
    assert %DateTime{} = stored.used_at

    # Hash remains stable after consumption
    assert Storage.hash(raw) == stored.token_hash
  end
end
