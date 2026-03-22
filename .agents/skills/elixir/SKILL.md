---
name: elixir
description: >
  Elixir/Phoenix coding standards, testing, and LiveView optimization.
  Use when writing, reviewing, or testing .ex/.exs files. Covers moduledoc
  placement, predicate naming, router specificity, LiveView change tracking
  and assign management, ExUnit patterns, Mox expectations, Credo conventions,
  and controller namespace resolution.
---

# Elixir/Phoenix Coding Standards

## Tech Stack

- Elixir, Phoenix, PostgreSQL, Docker, Tailwind CSS
- Tools: Credo, Sobelow, Ecto, ExUnit, Phoenix LiveView, Gettext, Jason, Swoosh, Finch, ExCoveralls

## Code Writing Guidelines

- Think through all considerations before writing code.
- Follow TDD: write tests first, then implement, then refactor.
- Pay close attention to compiler warnings — they often point directly to bugs.
- After code generation or modification, fix any compiler warnings (unused aliases, imports, variables). If a fix isn't obvious, flag the warning.

### @moduledoc Placement

`@moduledoc` must be INSIDE the module, not before it.

**Wrong:**
```elixir
@moduledoc """
A simple Plug for debugging.
"""
defmodule FamichatWeb.DebugPlug do
  # ...
end
```

**Right:**
```elixir
defmodule FamichatWeb.DebugPlug do
  @moduledoc """
  A simple Plug for debugging.
  """
  # ...
end
```

### Predicate Function Naming

Predicate functions never start with `is_` and must end with `?`.

```elixir
# Wrong
def is_empty(list), do: ...
def has_items(list), do: ...

# Right
def empty?(list), do: ...
def contains_item?(list, item), do: ...
```

## Phoenix Router

### Route Order and Specificity

Define specific routes before generic parameterized routes in the same scope:

```elixir
scope "/auth" do
  pipe_through :browser
  get "/logout", SessionController, :logout          # specific first
  get "/:provider", AuthController, :request          # generic after
  get "/:provider/callback", AuthController, :callback
end
```

### Controller Module Resolution

Prefer full module names in scopes to avoid double-namespace bugs:

```elixir
scope "/admin" do
  pipe_through :browser
  get "/users", FamichatWeb.Admin.UserController, :index
end
```

## LiveView

### Change Tracking — Never Spread Assigns

```elixir
# Wrong — defeats change tracking
<%= assigns[:greetings] %>
<%= assigns.greetings %>
<.hello_component {assigns} />
<%= hello_component(assigns) %>
<%= render WelcomeView, "hello.html", assigns %>

# Right — explicit assigns enable efficient diffing
<.hello_component greeting={@greeting} person={@person} />
```

### No Local Variables in HEEx Templates

```elixir
# Wrong
<% some_var = @x + @y %>
<%= some_var %>

# Wrong — local vars in render/1
def render(assigns) do
  sum = assigns.x + assigns.y
  title = assigns.title
  ~H"<h1><%= title %></h1><%= sum %>"
end

# Right — use assign/2
def render(assigns) do
  assigns = assign(assigns, sum: assigns.x + assigns.y)
  ~H"""
  <h1><%= @title %></h1>
  <%= @sum %>
  """
end
```

### Pass Only Required Assigns to Children

```elixir
# Wrong — spreads all assigns, breaks tracking
def card(assigns) do
  ~H"""
  <div class="card">
    <.card_header {assigns} />
    <.card_body {assigns} />
  </div>
  """
end

# Right — pass only what each child needs
def card(assigns) do
  ~H"""
  <div class="card">
    <.card_header title={@title} class={@title_class} />
    <.card_body><%= render_slot(@inner_block) %></.card_body>
  </div>
  """
end
```

### Function-Based Computations

```elixir
defp sum(x, y), do: x + y

# In template:
<%= sum(@x, @y) %>

# Or pre-compute in render:
def render(assigns) do
  assigns = assign(assigns, sum: sum(assigns.x, assigns.y))
  ~H"""<%= @sum %>"""
end
```

### Declare Component Attributes

```elixir
attr :x, :integer, required: true
attr :y, :integer, required: true
attr :title, :string, required: true

def sum_component(assigns) do
  assigns = assign(assigns, sum: sum(assigns.x, assigns.y))
  ~H"""
  <h1><%= @title %></h1>
  <%= @sum %>
  """
end
```

Use `assign/2`, `assign_new/3`, and `update/3` for efficient state management.

## Testing

### General Principles

- When asked to follow TDD, first outline what should be tested. Do not write code yet.
- Never test migration files.
- Do not create new non-test files unless specifically asked to get failed tests passing.

### LiveView Test Isolation

For LiveView tests, use a test-specific layout and router pipeline (e.g., `:test_isolated`)
to avoid rendering global UI like navigation.

### Session Keys — Always Use Strings

```elixir
# Right — string keys for on_mount hooks
conn = Plug.Test.init_test_session(conn, %{"user_id" => user_id})

# Wrong — atom keys won't be found by on_mount hooks
conn = Plug.Test.init_test_session(conn, %{user_id: user_id})
```

### Mox Expectation Counts for LiveView

Default to count of `2` for functions called in `on_mount` hooks (static render + connected mount):

```elixir
Mox.expect(MyMock, :my_func, 2, fn -> :ok end)
```

### App Config over stub_with

Prefer `config/test.exs` for mock dependencies:

```elixir
# config/test.exs
config :famichat, :dependency_key, MyMockModule

# test file
Mox.expect(MyMockModule, :call, fn -> :ok end)
```

### Pin Operator in Expectations

```elixir
expected_id = user.id
Mox.expect(MyMock, :find, fn ^expected_id -> {:ok, user} end)
```

### stub_with Return Value

Never pattern match on `Mox.stub_with/2`:

```elixir
# Right
Mox.stub_with(MyMock, MyRealModule)

# Wrong
:ok = Mox.stub_with(MyMock, MyRealModule)
```

### Per-Test Expectations over Shared Setup

Co-locate `Mox.expect` with individual tests, not in shared `setup` blocks.

### Atom vs String Keys in Maps

When accessing map fields in HEEx templates, match the key access method to the actual
key type. `Map.from_struct/1` creates atom keys (use `.` access).

## Credo Conventions

### TagTODO — Reference a ticket

```elixir
# Wrong
# TODO: Fix this later

# Right
# TODO: Refactor this logic — See GitHub Issue #45
```

### NegatedConditionsInIf — Use `unless` or flip

```elixir
# Wrong
if !is_nil(user), do: ...

# Right
unless is_nil(user), do: ...
# Or better:
if user, do: ...
```

### MapJoin — Single-pass

```elixir
# Wrong
users |> Enum.map(&(&1.name)) |> Enum.join(", ")

# Right
Enum.map_join(users, ", ", &(&1.name))
```

### WithClauses — Only `<-` in with head

```elixir
# Wrong — side effects in with head
with {:ok, user} <- Repo.get(User, id),
     Logger.info("Fetched user"),
     count = Enum.count(posts) do
  ...
end

# Right — side effects in do block
with {:ok, user} <- Repo.get(User, id),
     {:ok, posts} <- fetch_posts(user) do
  Logger.info("Fetched user #{user.id}")
  count = Enum.count(posts)
  {:ok, user, posts, count}
end
```

### UnsafeToAtom — Never on external input

```elixir
# Wrong
key = String.to_atom(user_input)

# Right
key = case user_input do
  "admin" -> :admin
  "user" -> :user
  _ -> :guest
end
```
