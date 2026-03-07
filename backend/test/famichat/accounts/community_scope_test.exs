defmodule Famichat.Accounts.CommunityScopeTest do
  use Famichat.DataCase, async: true

  alias Famichat.Accounts.{Community, CommunityScope}
  alias Famichat.Repo

  test "migration seeds the hidden default community row" do
    communities = Repo.all(Community)

    assert [%Community{} = community] = communities
    assert community.id == CommunityScope.default_id()
    assert community.name == CommunityScope.default_name()
  end
end
