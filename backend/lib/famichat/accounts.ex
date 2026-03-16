defmodule Famichat.Accounts do
  @moduledoc """
  Core accounts boundary.

  Owns the singleton community root and exposes `current_community!/0` for
  use by other contexts (`Famichat.Chat`) that need the default community ID
  without taking a dependency on `Famichat.Communities`.

  Legacy compatibility shims that forwarded calls to `Famichat.Auth.*` modules
  have been removed. Callers should reference `Famichat.Auth.*` directly.
  """

  use Boundary,
    top_level?: true,
    exports: :all,
    deps: [
      Famichat
    ]

  import Ecto.Query, warn: false

  alias Famichat.Accounts.{Community, CommunityScope}
  alias Famichat.Repo

  # Community scope ------------------------------------------------------------

  @doc """
  Returns the singleton operator-owned community, creating it with default
  values on first access.

  This function lives in `Famichat.Accounts` because it depends only on
  `Famichat.Accounts` schemas (`Community`, `CommunityScope`) and `Repo`.
  It is intentionally kept free of `Famichat.Communities` or `Famichat.Chat`
  dependencies to avoid circular boundary references.
  """
  @spec current_community!() :: Community.t()
  def current_community! do
    case Repo.one(
           from(c in Community,
             order_by: [asc: c.inserted_at, asc: c.id],
             limit: 1
           )
         ) do
      %Community{} = community ->
        community

      nil ->
        %Community{}
        |> Community.changeset(%{
          id: CommunityScope.default_id(),
          name: CommunityScope.default_name()
        })
        |> Repo.insert!()
    end
  end
end
