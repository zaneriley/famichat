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
./run rust:fmt
./run rust:clippy
./run rust:test
```

Or run all three:

```bash
./run rust:check
```

Optional unsafe-boundary validation (nightly + Miri):

```bash
./run rust:miri
```
