# Ash Primer (Evergreen)

This document explains what Ash is, why Famichat may use it, and how to use it safely.

## What Ash Is

Ash is an Elixir application framework for defining domain behavior as explicit resources and actions.

In practice, Ash gives you:
- Domain resources with typed attributes and relationships.
- Explicit action boundaries (`read`, `create`, `update`, `destroy`, custom actions).
- Policy/authorization rules close to domain logic.
- Generated interfaces that reduce repeated context/query boilerplate.

## What Ash Is Not

Ash is not a replacement for:
- Phoenix routing/controllers/channels.
- OTP supervision and runtime architecture.
- Postgres/Ecto as persistence engine.

Think of Ash as a domain/application layer, not a full stack replacement.

## Why Famichat Might Use Ash

Famichat has complex domain rules (auth flows, household governance, policy checks, staged rollouts).
Ash can help by:
- Making ownership boundaries explicit.
- Centralizing policy and action semantics.
- Reducing duplicated orchestration code in domain services.
- Improving consistency for net-new capability development.

## Why Famichat Should Not Force Ash Everywhere

Some parts of Famichat are high-risk and correctness-sensitive (sessions/tokens/passkeys/recovery/chat auth paths).
A broad migration there can create more risk than value.

Safer approach:
- Start with net-new bounded capabilities.
- Use strangler-style migration behind stable facades for existing flows.
- Prove parity and rollback before expanding scope.

## Installation Status and Source of Truth

Do not assume Ash is installed.
Source of truth is `backend/mix.exs`.

If `:ash`/`:ash_postgres` dependencies are absent, treat Ash guidance as an architectural option, not active runtime behavior.

## Adoption Principles (Always)

1. Keep external contracts stable while changing internals.
2. Preserve a single writer for each invariant.
3. Require fast rollback for every migration step.
4. Prefer small, reversible PRs with explicit boundaries.
5. Delete legacy paths only after soak + parity evidence.

## Use Ash When

- A bounded context has clear ownership.
- Behavior is action/policy heavy and currently repetitive.
- You can introduce it without changing public contracts.
- You can demonstrate rollback in minutes.

## Do Not Use Ash Yet When

- The change touches core auth/session/channel contracts and parity is not proven.
- Ownership would be split across old and new writers.
- Rollback is unclear or untested.
- The change bundles migration + feature + contract redesign in one PR.

## Working Definition for Reviewers

A good Ash change in Famichat is one that improves domain clarity and consistency without increasing contract risk.

If a proposed Ash change increases risk faster than it increases clarity, defer it.
