# Famichat — Agent Rules

Rules every agent must follow when writing or modifying frontend code.

---

## Design System

### Typography
- **All text must go through `<.typography>`** — defined in `backend/lib/famichat_web/components/typography.ex`
- No raw `<p>`, `<h1>`–`<h6>`, `<span>` with text styling, or Tailwind typography classes (`text-sm`, `font-bold`, `leading-*`, etc.)
- `backend/lib/famichat_web/components/core_components.ex` may be used as a fallback in a pinch

### Spacing
- **No margins.** Use `gap` and space elements only.
- **No hardcoded pixel values** — no `px-[14px]`, no inline `style="margin: 8px"`, nothing
- **No raw Tailwind spacing classes** — no `p-4`, `mt-2`, `mb-6`, etc.
- Maximum **4 spacing units** per layout — if you need more, the layout needs rethinking

### General
- No hardcoded Tailwind classes for color, sizing, or layout beyond what the component system provides
- No inline styles
- **All user-visible strings must use `gettext/1`** — no bare string literals in templates. "Famichat" as a brand name is the only exception.

---

## QA Rules — Never commit without verifying

These rules exist because agents repeatedly committed broken code that was never tested.

### Before committing any backend or routing change
- `curl -sv http://localhost:9000/AFFECTED_ROUTE` — check the HTTP status and response body
- If you deleted a function, `grep -r "function_name" lib/` before committing — check for other callers
- If you modified a Plug or router, curl every route that pipeline touches

### Before committing any JS change
- Read the actual API response shape with `curl -s ENDPOINT | python3 -m json.tool`
- Verify field names match what the JS accesses — don't assume
- Check the equivalent working hook for comparison (e.g. login hook vs register hook)

### Before committing any template change
- `mix compile` must be clean (zero errors, no new warnings)
- If you removed a helper function, search all templates for calls to it: `grep -r "function_name" lib/famichat_web/`

### The rule
**If you have not curled the endpoint or seen the actual output, you have not tested it. Do not commit.**

---

## URL / Routing Rules

- **Never hardcode locale in paths.** Use `locale_path(socket, "/path")` or `locale_path(assigns, "/path")` — defined in `FamichatWeb.LiveHelpers`, available in all LiveViews automatically.
- No `/en/...` or `/ja/...` string literals in LiveView `.ex` or `.heex` files
- The `LocaleRedirection` plug handles locale prefixing at the HTTP layer; `locale_path/2` handles it in LiveView navigations

---

## Architecture Rules

- Read `docs/NOW.md` before starting any task — it contains the current known bugs and what's been built
- Read `docs/SPEC.md` for product intent — don't build features marked as deferred or L3+
- Throwaway LiveViews (auth, onboarding) must stay tightly coupled — no abstractions, no shared components beyond what already exists

---

## The `./run` Script (Dockerized Taskfile)

**Location:** `backend/run` — all commands run from `backend/` directory.

The app runs in Docker. **Never run `mix`, `cargo`, `psql`, or `yarn` directly on the host.** Everything goes through `./run`, which dispatches to `docker compose exec web <command>`.

### How it works

```
./run <function_name> [args...]
```

The script is a bash Taskfile. Each top-level `function` is a subcommand. `./run help` lists them all. The core plumbing:

- `./run cmd <anything>` — runs any command inside the `web` container (e.g., `./run cmd mix ecto.migrate`)
- `_dc` (internal) — wraps `docker compose exec` with TTY detection
- `_build_run_down` (internal) — `docker compose build` → `run` → `down` (for one-shot tasks)

### Commands agents use most

| Task | Command |
|------|---------|
| **Run mix command** | `./run cmd mix <task>` or `./run mix <task>` |
| **Reset database** | `./run db:reset` (stops web, drops DBs, runs ecto.setup, restarts) |
| **Run all tests** | `./run elixir:test` |
| **Run one test file** | `./run elixir:test:file <path>` |
| **Credo (strict)** | `./run cmd mix credo --strict` |
| **Format Elixir** | `./run elixir:format` |
| **IEx console** | `./run iex` |
| **Rust fmt** | `./run rust:fmt` |
| **Rust clippy** | `./run rust:clippy` |
| **Rust tests** | `./run rust:test` |
| **JS lint** | `./run js:lint` |
| **JS tests** | `./run js:test` |
| **Shell into container** | `./run shell` |
| **psql** | `./run psql` (connects to Postgres container) |
| **Lint everything** | `./run lint:all` |
| **Test everything** | `./run test:all` |
| **Boundary check** | `./run docs:boundary-check` |

### What NOT to do (real mistakes from agent sessions)

| Wrong command | Why it fails | Correct command |
|---|---|---|
| `cd backend && ../run cmd mix compile` | `../run` doesn't exist — the script is at `backend/run` | `cd backend && ./run cmd mix compile` |
| `cd backend && mix compile` | Bare `mix` runs on the host — wrong Elixir/OTP, no env vars, no DB access | `cd backend && ./run cmd mix compile` |
| `cd backend && ./run cmd mix ecto.reset` | `ecto.reset` runs inside the container but `db:reset` handles the full lifecycle (stop web, drop DBs, setup, restart) | `cd backend && ./run db:reset` |
| `mix test` | Host mix, wrong environment | `cd backend && ./run elixir:test` |
| `cd backend && ./run cmd mix compile --warnings-as-errors` | Don't compile manually — hot reload handles it | Don't. Just save the file. |
| `cargo test` | Host cargo, wrong toolchain | `cd backend && ./run rust:test` |
| `cargo fmt --manifest-path infra/mls_nif/Cargo.toml --all` | Host cargo | `cd backend && ./run rust:fmt` |

### Critical rules for agents

1. **Always run from `backend/`:** `cd backend && ./run <cmd>`, not `cd backend && ../run`
2. **Never run bare `mix` on the host** — it won't have the right Elixir/OTP version or env vars
3. **`db:reset` is destructive** — it drops both `famichat` and `famichat_test` databases, re-runs migrations, and restarts containers. Don't run without user confirmation.
4. **Hot reload is active** — Elixir file changes are picked up automatically. Don't restart the server or recompile manually after editing `.ex`/`.heex` files.
5. **Rust changes require `./run rust:fmt && ./run rust:clippy && ./run rust:test`** — the Rust NIF is not hot-reloaded
