# mls_nif

Rust-side contract scaffold for the Famichat MLS adapter.

This crate is intentionally minimal and currently provides:

1. Stable error-code taxonomy mirroring the Elixir boundary contract.
2. Rustler NIF exports for the Elixir MLS bridge (`Famichat.Crypto.MLS.NifBridge`).
3. Deterministic contract-safe operation implementations for lifecycle/message flows.
4. Unit tests that validate invariants and result-shape stability while OpenMLS wiring is pending.

## Validation loop

Run from `backend/`:

```bash
./run rust:doctor
./run rust:verify
```

Fast path for lint + unit tests only:

```bash
./run rust:check
```

Lint-only path:

```bash
./run rust:lint
```

Dependency policy path:

```bash
./run rust:deny
```

Tooling verification path (fixture-driven checks for fmt, clippy, test, and deny):

```bash
./run ci:tooling-test
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

If you need a different `cargo-deny` policy file, override the deny config path:

```bash
RUST_DENY_CONFIG_PATH=path/to/deny.toml ./run rust:deny
```
