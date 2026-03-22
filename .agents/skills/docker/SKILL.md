---
name: docker
description: >
  Docker-based development environment rules. Use when running backend commands,
  building assets, or troubleshooting container issues. All commands must go
  through the ./run script — never run mix, yarn, or npm directly on the host.
---

# Docker Environment Rules

## Core Rule

All operations must go through the project's `./run` script. Direct `mix`, `yarn`,
or `npm` commands on the host will fail or have unexpected effects.

## Command Mapping

| Wrong (direct) | Right (./run wrapper) |
|---|---|
| `mix deps.get` | `./run mix:install` |
| `mix format` | `./run elixir:format` |
| `mix assets.deploy` | `./run mix assets.deploy` |
| `npm install` | Use ./run equivalent |
| `yarn build` | `./run yarn:build:css` or `./run yarn:build:js` |

## Troubleshooting Assets

### CSS/Tailwind Issues

When utilities are missing:
- Never edit Tailwind config directly — use `./run yarn:build:css`
- Full CSS rebuild: `./run mix assets.deploy`
- Font issues: `./run assets:font-metrics`

### Container Paths

- Container paths start with `/app/`, not local relative paths
- Static files must be in `/app/priv/static/` to be served

## Error Response Protocol

1. When encountering build/asset errors:
   - Check the `run` script for appropriate commands first
   - Use `./run clean` followed by `./run mix assets.deploy`
   - For Docker issues: `docker compose down && docker compose up -d`

2. Before modifying files:
   - Understand where they're located in the Docker container
   - Determine the correct `./run` command to rebuild them
