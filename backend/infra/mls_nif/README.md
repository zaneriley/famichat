# mls_nif

Rust-side contract scaffold for the Famichat MLS adapter.

This crate is intentionally minimal and currently provides:

1. Stable error-code taxonomy mirroring the Elixir boundary contract.
2. `nif_version` and `nif_health` scaffolding payloads.
3. Placeholder operations that fail closed with `unsupported_capability`.
4. Unit tests that keep the contract shape deterministic while OpenMLS wiring is pending.

## Validation loop

Run from `backend/`:

```bash
./run rust:doctor
./run rust:fmt
./run rust:clippy
./run rust:test
```

Fast path (single container exec for tighter iteration):

```bash
./run rust:check
```

Lint-only path (used by CI lint stage):

```bash
./run rust:lint
```

Optional unsafe-boundary validation (nightly + Miri):

```bash
./run rust:miri
```

First `rust:miri` run installs nightly components (`miri`, `rust-src`) and will be slower.

If you need a different crate/workspace, override manifest resolution:

```bash
RUST_MANIFEST_PATH=path/to/Cargo.toml ./run rust:check
```
