# Phase 3 Implementation Plan — Structure, Documentation, Performance, and Polish

**Crate**: `backend/infra/mls_nif/`
**Prerequisite**: Phase 1 (correctness) and Phase 2 (type safety) complete and green on CI.
**Goal**: Long-term maintainability — module split, lint enforcement, dead code removal, allocation
reduction, documentation, and integration test scaffolding.

---

## Table of Contents

1. [Module Split (Finding #9)](#1-module-split-finding-9)
2. [Clippy Lint Configuration (Findings #10, #31)](#2-clippy-lint-configuration-findings-10-31)
3. [Dead Code Removal (Finding #30)](#3-dead-code-removal-finding-30)
4. [Visibility Narrowing (Finding #18)](#4-visibility-narrowing-finding-18)
5. [Payload Allocation: with_capacity (Finding #13)](#5-payload-allocation-with_capacity-finding-13)
6. [serialize_snapshot_raw_data Hot-Path Allocation (Finding #14)](#6-serialize_snapshot_raw_data-hot-path-allocation-finding-14)
7. [Low-Severity Ownership Fixes (Findings #24–#28)](#7-low-severity-ownership-fixes-findings-24-28)
8. [Cargo.toml: release profile (Finding #29)](#8-cargotoml-release-profile-finding-29)
9. [Public API Documentation (Finding #21)](#9-public-api-documentation-finding-21)
10. [Integration Test Directory (Finding #22)](#10-integration-test-directory-finding-22)
11. [Low-Severity API Polish (Findings #32–#35)](#11-low-severity-api-polish-findings-32-35)
12. [Execution Order and Dependency Graph](#12-execution-order-and-dependency-graph)
13. [Risk Register](#13-risk-register)

---

## 1. Module Split (Finding #9)

**Audit reference**: #9 — 1947-line single-file crate, five separate domains crammed into one
module. Rule: `proj-mod-by-feature`.

### 1.1 Target file layout

```
src/
  lib.rs          ← crate root: only #![...] attributes, use declarations, pub use re-exports,
                    rustler::init!(), and the NIF shim functions (*_nif fns).
  error.rs        ← ErrorCode, MlsError, MlsResult, error_atom(), encode_result()
  types.rs        ← Payload type alias, GroupSession, MemberSession, CachedMessage,
                    SnapshotRawData, CreateGroupParams, TryFrom impl for CreateGroupParams
  session.rs      ← GROUP_SESSIONS static, KEY_PACKAGE_COUNTER static, all GroupSession
                    creation / restore / snapshot logic
  ops.rs          ← All 17 public NIF business-logic functions (nif_version through
                    list_member_credentials) and their private helpers
                    (lifecycle_ok, with_required_group, determine_remove_target,
                    map_create_message_error)
  codec.rs        ← encode_hex, decode_hex, hex_nibble, serialize_snapshot_raw_data,
                    deserialize_storage_map, serialize_message_cache_ordered,
                    deserialize_message_cache_ordered, cache_decrypted_message,
                    build_group_session_snapshot (thin wrapper)
  params.rs       ← required_non_empty, non_empty, has_non_empty (new), has_complete_session_snapshot,
                    parse_bool, next_epoch, next_key_package_ref, validate_openmls_runtime,
                    parse_ciphersuite
tests/
  api_integration.rs   ← (see Section 10)
```

### 1.2 What moves where

#### `src/error.rs`

Move verbatim from lib.rs:

- `enum ErrorCode` (lines 18–48) including `as_str`
- `struct MlsError` (lines 51–55) including `impl MlsError`
- `type MlsResult` (line 57)
- `fn error_atom()` (lines 1930–1942) — currently `fn`, stays `fn` (called only from `encode_result`)
- `fn encode_result()` (lines 1923–1928)
- `mod atoms { ... }` (lines 1907–1921) — private to the crate, so stays `pub(crate)` visibility
  inside this module

No `pub use` re-export needed at crate root; `MlsResult`, `MlsError`, `ErrorCode` are referenced by
`ops.rs` and `session.rs` via `crate::error::*` or an explicit `use crate::error::{...}` in each
module.

#### `src/types.rs`

Move verbatim:

- `pub type Payload` (line 16)
- `struct CreateGroupParams` (lines 59–63) — keep `pub(crate)` scope
- `struct GroupSession` (lines 65–71)
- `struct MemberSession` (lines 73–77)
- `#[derive(Clone)] struct CachedMessage` (lines 79–83)
- `struct SnapshotRawData` (lines 1306–1317)
- `impl TryFrom<&Payload> for CreateGroupParams` (lines 1886–1905)

Constants that are intrinsic to snapshot types stay here:

- `SNAPSHOT_SENDER_STORAGE_KEY` through `SNAPSHOT_CACHE_KEY` (lines 86–90)
- `MAX_DECRYPT_CACHE_ENTRIES` (line 91)
- `DEFAULT_CIPHERSUITE` (line 85)

`MAX_HEX_DECODE_BYTES` (line 1852) moves to `codec.rs` since it guards the codec boundary.

`pub use` at crate root:

```rust
pub use types::Payload;
```

`MlsResult` is not re-exported from `types.rs` since it lives in `error.rs`.

#### `src/session.rs`

Move:

- `static GROUP_SESSIONS` (lines 93–94)
- `static KEY_PACKAGE_COUNTER` (line 95)
- `fn create_group_session()` (lines 1108–1249)
- `fn create_credential_with_signer_bytes()` (lines 1251–1279)
- `fn restore_group_session_from_snapshot()` (lines 1464–1611)
- `fn extract_snapshot_raw_data()` (lines 1324–1398)

All of these are internal. `GROUP_SESSIONS` and `KEY_PACKAGE_COUNTER` become `pub(crate)` so
`ops.rs` can reference them. All functions become `pub(crate)`.

No `pub use` re-export needed at crate root; these are never called from Elixir directly.

#### `src/codec.rs`

Move:

- `fn encode_hex()` (lines 1838–1848)
- `const MAX_HEX_DECODE_BYTES` (line 1852)
- `fn decode_hex()` (lines 1854–1875)
- `fn hex_nibble()` (lines 1877–1884)
- `fn serialize_snapshot_raw_data()` (lines 1404–1447)
- `fn deserialize_storage_map()` (lines 1613–1651)
- `fn serialize_message_cache_ordered()` (lines 1713–1726)
- `fn deserialize_message_cache_ordered()` (lines 1742–1813)
- `fn cache_decrypted_message()` (lines 1815–1836)
- `fn build_group_session_snapshot()` (lines 1456–1462) — thin wrapper, stays here

`serialize_message_cache` (lines 1690–1705) is addressed in Section 3 (dead code removal).
`deserialize_message_cache` (lines 1728–1734) is a thin wrapper around `_ordered`; if kept for
tests, move to `#[cfg(test)]` block within `codec.rs`.

All functions become `pub(crate)`. None are part of the public NIF surface.

#### `src/params.rs`

Move:

- `fn required_non_empty()` (lines 1034–1046)
- `fn non_empty()` (lines 1048–1053)
- `fn has_complete_session_snapshot()` (lines 1055–1060)
- `fn parse_bool()` (lines 1062–1068)
- `fn next_key_package_ref()` (lines 1070–1073)
- `fn next_epoch()` (lines 1075–1082)
- `fn validate_openmls_runtime()` (lines 1084–1091)
- `fn parse_ciphersuite()` (lines 1093–1106)

New function added here (see Section 7): `fn has_non_empty(params: &Payload, key: &str) -> bool`

All `pub(crate)`.

#### `src/ops.rs`

Move the 17 NIF business-logic functions plus private helpers:

- `pub fn nif_version()` through `pub fn list_member_credentials()` (all 17)
- `fn lifecycle_ok()` (lines 984–997)
- `fn with_required_group()` (lines 999–1032)
- `fn determine_remove_target()` (lines 648–669)
- `fn map_create_message_error()` (lines 1281–1299)

All `pub` functions that are called only by NIF shims become `pub(crate)`. The NIF shim functions
in `lib.rs` call them via `ops::create_group(...)` etc.

#### `src/lib.rs` after split

The new `lib.rs` contains only:

```rust
#![forbid(unsafe_code)]
#![warn(missing_docs)]
// Lint configuration (see Section 2)

//! Crate-level doc comment (see Section 9)

mod atoms;      // stays inline — rustler::atoms! macro output is not movable
mod error;
mod types;
mod session;
mod ops;
mod codec;
mod params;

pub use error::{ErrorCode, MlsError, MlsResult};
pub use types::Payload;

// NIF shim functions — these are the ONLY pub items crossing the Elixir boundary.
// Each is a thin wrapper: convert HashMap → Payload, call ops::*, encode_result.

use rustler::{Encoder, Env, Term};
use std::collections::HashMap;

fn payload_from_nif(params: HashMap<String, String>) -> Payload {
    params.into_iter().collect()
}

// ... all *_nif functions ...

rustler::init!("Elixir.Famichat.Crypto.MLS.NifBridge");
```

The `#[cfg(test)] mod tests { ... }` block moves to `src/ops.rs` with a companion
`tests/api_integration.rs` for cross-module tests (Section 10).

### 1.3 pub use re-exports required to avoid breaking NIF wiring

The Elixir NIF bridge calls functions by their Rustler-registered string names (e.g.
`"create_group"`), not by Rust paths. The NIF registration contract is the `rustler::init!` macro
in `lib.rs` and the `#[rustler::nif(...)]` attributes on the shim functions. As long as all
`*_nif` functions remain in `lib.rs` and call `ops::*` internally, the Elixir-facing contract does
not change.

The only public Rust items that could matter to downstream consumers of the `rlib` are
`Payload`, `MlsError`, `ErrorCode`, and `MlsResult`. These are re-exported at crate root via
`pub use` (shown above).

### 1.4 What to verify

- `cargo check` produces zero errors immediately after the split.
- `cargo test` passes with the same test count as before.
- `cargo clippy --all-targets` produces no new warnings from moved items.
- No `pub use` re-export left pointing at a `pub(crate)` item (that would be a compile error).

### 1.5 Dependencies

None. The split is a pure mechanical refactor with no logic changes. It is the first Phase 3 task
because every subsequent fix targets a specific file in the new layout.

### 1.6 Risk

Low. The only risk is a missed `use` import in one of the new files. The compiler will point
to every missing import precisely. The test suite gives immediate confirmation.

The `atoms` module cannot be moved to a separate file because `rustler::atoms!` expands inline
items that need to be in the same module as `encode_result`. Keep it inline in `lib.rs`.

---

## 2. Clippy Lint Configuration (Findings #10, #31)

**Audit references**: #10 — no `[lints]` section at all; #31 — missing deny(correctness) etc.

### 2.1 What changes

Add a `[lints]` table to `Cargo.toml`:

```toml
[lints.rust]
# Catch accidental dead code and missing documentation in public items.
dead_code = "warn"
missing_docs = "warn"

[lints.clippy]
# Deny: these are almost always bugs.
correctness = { level = "deny", priority = -1 }
# Warn: code quality categories.
suspicious  = { level = "warn", priority = -1 }
style       = { level = "warn", priority = -1 }
complexity  = { level = "warn", priority = -1 }
perf        = { level = "warn", priority = -1 }
# Nursery and restriction lints that apply to this crate.
# Enable selectively rather than the full group to avoid churn.
unwrap_used              = "warn"
expect_used              = "warn"
missing_errors_doc       = "warn"
missing_panics_doc       = "warn"
module_name_repetitions  = "allow"   # common in NIF crates; "MlsError" pattern is intentional
```

Add corresponding crate-level attributes to the top of the new `lib.rs` (after `#![forbid(unsafe_code)]`):

```rust
#![warn(missing_docs)]
```

The `missing_docs` attribute in `Cargo.toml` `[lints.rust]` and the `#![warn(missing_docs)]`
crate attribute are redundant; use only the `Cargo.toml` form so it applies uniformly to all
`--all-targets` invocations without needing attribute edits per file.

### 2.2 What to verify

After adding the lint table, run:

```
cargo clippy --all-targets -- -D warnings
```

This should produce zero `deny`-level errors before any other Phase 3 fixes land. Warnings from
`missing_docs`, `unwrap_used`, and `perf` lints are expected and will be resolved by later tasks in
this plan. Track them via `cargo clippy 2>&1 | grep -c "warning:"` to confirm the count is
shrinking.

### 2.3 Dependencies

The module split (Section 1) should land first so that Clippy runs against the final file layout.
If the split is delayed, add the lint table to the existing `lib.rs` temporarily and expect ~30
warnings; that is acceptable.

### 2.4 Risk

Low. Clippy lint configuration cannot break the build unless a `deny`-level lint fires on existing
code. The only `deny`-level group is `correctness`, which covers only definite bugs. If a
`correctness` lint fires on existing code after Phase 1 and Phase 2 are complete, that is a
genuine bug that must be fixed before proceeding.

---

## 3. Dead Code Removal (Finding #30)

**Audit reference**: #30 — `serialize_message_cache` and `deserialize_message_cache` are dead code,
superseded by the `_ordered` variants. Both appear only in `#[cfg(test)]` usage after Phase 3.

### 3.1 What changes

**File**: `src/codec.rs` (after split) or `src/lib.rs` (before split).

The function `serialize_message_cache` (lines 1690–1705 in lib.rs) has no non-test callers.
`deserialize_message_cache` (lines 1728–1734) is a thin wrapper around
`deserialize_message_cache_ordered` and also has no non-test callers.

Action:

1. Move both functions inside `#[cfg(test)]` inside `codec.rs`. Do not delete them immediately
   because the inline test `session_cache_roundtrip` may reference `serialize_message_cache`.
   Confirm by searching for callers after the split.
2. If no non-test caller exists after the module split, the `#[allow(dead_code)]` suppressor
   is unnecessary; the `#[cfg(test)]` gate makes the dead-code warning disappear automatically.
3. If the inline test `session_cache_roundtrip` is moved to `tests/api_integration.rs`, and
   that test no longer needs `serialize_message_cache`, delete the function entirely.

### 3.2 What to verify

```
cargo build 2>&1 | grep -i "dead_code"
```

No `dead_code` warnings for these two functions after the change. Also confirm `cargo test` still
passes — specifically any test whose name contains "cache".

### 3.3 Dependencies

Module split (Section 1) must complete first so the function lives in `codec.rs` before this edit.

### 3.4 Risk

Low. These functions are only referenced in tests. If any test breaks, the test needs to be
rewritten to use `serialize_message_cache_ordered` instead, which is a one-line change.

---

## 4. Visibility Narrowing (Finding #18)

**Audit reference**: #18 — Internal functions are `pub` instead of `pub(crate)`. This is a cdylib
+ rlib crate, so `pub` items are visible to all downstream consumers of the rlib.

### 4.1 What changes

After the module split, audit every `pub fn` outside `lib.rs` (i.e., in `ops.rs`, `session.rs`,
`codec.rs`, `params.rs`, `error.rs`, `types.rs`) and change to `pub(crate)` unless the function
is re-exported at crate root for downstream rlib consumers.

Concrete list based on current lib.rs:

**Keep `pub` (crate-root re-export only)**:
- `ErrorCode`, `MlsError`, `MlsResult` — exported in `pub use error::*`
- `type Payload` — exported in `pub use types::Payload`

**Change to `pub(crate)`** (called only from NIF shims or other internal modules):
- All 17 business-logic functions in `ops.rs`: `nif_version`, `nif_health`, `create_key_package`,
  `create_group`, `join_from_welcome`, `process_incoming`, `commit_to_pending`, `mls_commit`,
  `mls_update`, `mls_add`, `mls_remove`, `merge_staged_commit`, `clear_pending_commit`,
  `create_application_message`, `export_group_info`, `export_ratchet_tree`,
  `list_member_credentials`
- `MlsError::invalid_input`, `MlsError::with_code` — called from within the crate only
- `ErrorCode::as_str` — could be `pub` if downstream code reads error strings, but only the
  Elixir bridge uses it; make `pub(crate)` unless there is a documented external consumer

**Leave `pub`**:
- The struct fields `MlsError::code` and `MlsError::details` — currently `pub`, needed by tests
  that pattern-match on them. If Phase 2 adds accessor methods, these can be `pub(crate)` too.
  Leave this decision to Phase 2 authors.

### 4.2 What to verify

After narrowing:

```
cargo build --lib
```

Zero errors. The NIF shims in `lib.rs` call `ops::create_group(...)` using `pub(crate)` access
within the crate; this is fine because they are in the same crate.

Confirm the Elixir test suite still passes (`mix test`) — the Elixir boundary only cares about
the Rustler-registered NIF names, not Rust visibility.

### 4.3 Dependencies

Module split (Section 1) must complete first — `pub(crate)` is only meaningful once the items
live in separate modules.

### 4.4 Risk

Low. `pub(crate)` is more restrictive than `pub` for rlib consumers. If any downstream crate
(e.g. a future `mls_nif_test` crate) was importing these items directly, it would break. There is
no evidence of such a consumer in this repository.

---

## 5. Payload Allocation: with_capacity (Finding #13)

**Audit reference**: #13 — All 27 `Payload::new()` sites missing `with_capacity` despite known
insert counts. Rule: `mem-with-capacity`.

### 5.1 What changes

**File**: `src/ops.rs` and `src/error.rs` (after split).

`Payload` is `HashMap<String, String>`. Without `with_capacity`, the first insertion
triggers an allocation, and most functions grow the map to a known fixed size.

Enumerate the 27 sites by their operation and the number of inserts that follow:

| Site | Function | Fixed insert count | Fix |
|------|----------|--------------------|-----|
| `MlsError::with_code` | `error.rs` | 2 | `Payload::with_capacity(2)` |
| `nif_version` | `ops.rs` | 3 | `Payload::with_capacity(3)` |
| `nif_health` | `ops.rs` | 2 | `Payload::with_capacity(2)` |
| `create_key_package` success | `ops.rs` | 3 | `Payload::with_capacity(3)` |
| `create_group` | `ops.rs` | ~7 (+ snapshot extends) | `Payload::with_capacity(12)` |
| `join_from_welcome` success | `ops.rs` | ~6 (+ snapshot) | `Payload::with_capacity(11)` |
| `join_from_welcome` error | `ops.rs` | 2 | `Payload::with_capacity(2)` |
| `process_incoming` cache hit | `ops.rs` | 3 | `Payload::with_capacity(3)` |
| `process_incoming` error | `ops.rs` | 2–3 | `Payload::with_capacity(3)` |
| `process_incoming` success | `ops.rs` | ~4 (+ snapshot) | `Payload::with_capacity(9)` |
| `commit_to_pending` | `ops.rs` | 3 | `Payload::with_capacity(3)` |
| `lifecycle_ok` | `ops.rs` | 4 | `Payload::with_capacity(5)` |
| `mls_remove` success | `ops.rs` | ~5 (+ snapshot) | `Payload::with_capacity(10)` |
| `mls_remove` error | `ops.rs` | 2–3 | `Payload::with_capacity(3)` |
| `merge_staged_commit` inactive | `ops.rs` | ~5 (+ snapshot) | `Payload::with_capacity(10)` |
| `merge_staged_commit` success | `ops.rs` | ~5 (+ snapshot) | `Payload::with_capacity(10)` |
| `clear_pending_commit` | `ops.rs` | 3 | `Payload::with_capacity(3)` |
| `create_application_message` success | `ops.rs` | ~4 (+ snapshot) | `Payload::with_capacity(9)` |
| `export_group_info` | `ops.rs` | 3+ | `Payload::with_capacity(8)` |
| `export_ratchet_tree` | `ops.rs` | 2 | `Payload::with_capacity(2)` |
| `list_member_credentials` | `ops.rs` | 3 | `Payload::with_capacity(3)` |
| `serialize_snapshot_raw_data` | `codec.rs` | 5 | `Payload::with_capacity(5)` |
| `with_required_group` error | `ops.rs` | 2 | `Payload::with_capacity(2)` |
| `TryFrom for CreateGroupParams` error | `types.rs` | ~3 | `Payload::with_capacity(3)` |
| Various `err_details` local bindings | `ops.rs` | 2–3 | `Payload::with_capacity(3)` |

For sites that call `payload.extend(snapshot)` — snapshot contains exactly 5 keys
(`SNAPSHOT_SENDER_STORAGE_KEY`, `SNAPSHOT_RECIPIENT_STORAGE_KEY`, `SNAPSHOT_SENDER_SIGNER_KEY`,
`SNAPSHOT_RECIPIENT_SIGNER_KEY`, `SNAPSHOT_CACHE_KEY`) — add 5 to the base count.

Use a slightly over-estimated capacity at sites where `extend` adds a variable number of keys
to avoid re-allocation while keeping the estimate small.

### 5.2 What to verify

No compile-time test for allocation counts, but:

1. `cargo test` must pass unchanged.
2. The `perf` Clippy lint group (enabled in Section 2) includes
   `clippy::new_without_default` but not a `HashMap::new()` lint. Manually audit the 27 sites
   as a checklist in the PR description.
3. Optional: add a compile-time assertion `const _: () = assert!(...)` comment documenting the
   expected key count at each site, as living documentation for reviewers.

### 5.3 Dependencies

- Module split (Section 1) so the sites are in their permanent files.
- Clippy lint configuration (Section 2) is not a hard dependency but should land first so that the
  `perf` lint group is active during review.

### 5.4 Risk

Very low. `HashMap::with_capacity(n)` is a strict improvement over `HashMap::new()` when `n > 0`.
The only risk is over-allocating at sites where the insert count varies. Over-allocation wastes
a small amount of memory per call; it does not affect correctness. Use modestly over-estimated
capacities (never exact) to avoid churn if the insert count changes later.

---

## 6. serialize_snapshot_raw_data Hot-Path Allocation (Finding #14)

**Audit reference**: #14 — `serialize_snapshot_raw_data` uses `format!` in per-entry loops,
producing 3 allocations per storage entry (`encode_hex(k)` + `encode_hex(v)` + `format!`).
Rule: `anti-format-hot-path`.

### 6.1 What changes

**File**: `src/codec.rs` (after split).

The current inner loop in `serialize_snapshot_raw_data`:

```rust
.map(|(k, v)| format!("{}:{}", encode_hex(k), encode_hex(v)))
```

Replace the two per-entry loops with a single pre-sized `String` buffer approach:

- Before iterating, compute `capacity = entries.len() * (avg_key_hex_len + 1 + avg_val_hex_len + 1)`.
  Because key and value sizes are not known at compile time, use a heuristic: OpenMLS storage
  keys are typically 32–64 bytes (64–128 hex chars) and values 32–256 bytes (64–512 hex chars).
  A safe heuristic is `entries.len() * 300`.
- Allocate one `String::with_capacity(estimated)` outside the loop.
- Write directly into the buffer using `push_str` and `push` instead of `format!`:
  1. Append `encode_hex(k)` (returns an owned `String`; call `push_str(&encode_hex(k))`)
  2. Append `:`
  3. Append `encode_hex(v)`
  4. Append `,` (then sort and trim the trailing comma separately, or sort a `Vec<(String, String)>`
     of `(key_hex, val_hex)` pairs first, then join with minimal allocation).

The cleanest approach that avoids the intermediate `Vec<String>` while preserving the sort:

1. Collect `(hex_key, hex_val)` pairs into a `Vec<(String, String)>` — this is unavoidable for
   sorting.
2. Sort by `hex_key`.
3. Write sorted pairs into one pre-sized `String` using `push_str`.

This reduces the per-entry allocation from 3 strings to 2 strings (the two `encode_hex` results),
and the final `join(",")` allocation is replaced by a single `push_str` write loop.

The `encode_hex` function itself allocates one `String` per call. A further optimization — pass
a `&mut String` buffer into `encode_hex` — is listed in Section 7 (low-severity) and is separate
from this fix.

### 6.2 What to verify

- `cargo test` passes unchanged.
- The `session_cache_roundtrip` test (or its successor in `api_integration.rs`) validates that
  the serialized format is identical to the previous output by round-tripping: serialize →
  deserialize → compare field by field.
- Add a regression test in `tests/api_integration.rs` that calls `create_group`, captures the
  snapshot, destroys the in-memory session, then calls `create_application_message` with that
  snapshot to force a restore. If the format changes, this test fails.

### 6.3 Dependencies

- Module split (Section 1) so the function lives in `codec.rs`.
- Dead code removal (Section 3) should land first to avoid editing a function that will be
  deleted.

### 6.4 Risk

Medium. The serialized snapshot format is the wire format between Rust and Elixir. Any change to
the format of `serialize_snapshot_raw_data` output breaks existing snapshots stored in the
Elixir layer. The implementation change described here is purely internal (same format, fewer
allocations). The risk is accidentally introducing a bug that changes the separator character,
key order, or encoding. Mitigate with the round-trip regression test described above.

---

## 7. Low-Severity Ownership Fixes (Findings #24–#28)

These five findings are independent of each other and can be landed in any order after the module
split.

### 7.1 Finding #24 — has_non_empty for presence checks

**File**: `src/params.rs`

`has_complete_session_snapshot` calls `non_empty()` four times and immediately calls `.is_some()`
on each result, triggering four `String::clone()` calls for a boolean check.

Add a new helper:

```rust
pub(crate) fn has_non_empty(params: &Payload, key: &str) -> bool {
    params.get(key).is_some_and(|v| !v.trim().is_empty())
}
```

Rewrite `has_complete_session_snapshot`:

```rust
pub(crate) fn has_complete_session_snapshot(params: &Payload) -> bool {
    has_non_empty(params, SNAPSHOT_SENDER_STORAGE_KEY)
        && has_non_empty(params, SNAPSHOT_RECIPIENT_STORAGE_KEY)
        && has_non_empty(params, SNAPSHOT_SENDER_SIGNER_KEY)
        && has_non_empty(params, SNAPSHOT_RECIPIENT_SIGNER_KEY)
}
```

**Verify**: `cargo test` passes. Four clone calls eliminated per invocation. `is_some_and` requires
Rust 1.70+; the crate's `rust-version = "1.80"` satisfies this.

**Risk**: None. Pure refactor with no observable difference.

### 7.2 Finding #25 — parse_bool without clone

**File**: `src/params.rs`

Current `parse_bool` calls `non_empty(params, key)` which clones the value, then immediately
pattern-matches on `.as_str()`.

Replace with a borrow-only implementation:

```rust
pub(crate) fn parse_bool(params: &Payload, key: &str) -> Option<bool> {
    match params.get(key).map(String::as_str) {
        Some("true") | Some("1") => Some(true),
        Some("false") | Some("0") => Some(false),
        _ => None,
    }
}
```

**Verify**: All tests that use `parse_bool` indirectly (via `process_incoming`, `mls_remove`,
`create_application_message`, `merge_staged_commit`) pass unchanged.

**Risk**: None. Logical equivalence with the original is straightforward.

### 7.3 Finding #26 — deserialize_signer unnecessary clone

**File**: `src/codec.rs`

`deserialize_signer` clones `operation` into `op_owned` (line 1666) before the `catch_unwind`
closure, because `&str` is not `'static`. The clone is used only in the error arm.

The simplest fix without restructuring the function is to keep the clone but defer it:

```rust
Ok(Err(_e)) => Err(MlsError::with_code(
    ErrorCode::InvalidInput,
    operation,  // borrow directly — valid here because we are outside catch_unwind
    "signature_keypair_tls_malformed",
)),
Err(_panic) => Err(MlsError::with_code(
    ErrorCode::InvalidInput,
    operation,
    "signature_keypair_tls_malformed",
)),
```

The `operation: &str` borrow is valid in the `match result { ... }` arm because `result` is
fully evaluated before the arm executes, and `catch_unwind` does not extend the lifetime of
borrows captured in the closure. The `AssertUnwindSafe` wrapper borrows `bytes` by reference
inside the closure; `operation` is not captured by the closure at all in this corrected form.

Remove the `let op_owned = operation.to_owned()` line (line 1666).

**Verify**: `cargo test` passes. Also confirm `cargo clippy` does not warn about the
`AssertUnwindSafe` usage (the soundness comment from Finding #39 covers this — see Section 11.4).

**Risk**: Low. The only change is removing a `to_owned()` call that was unnecessary.

### 7.4 Finding #27 — cache_decrypted_message entry API

**File**: `src/codec.rs`

The current `cache_decrypted_message` performs two HashMap lookups via `contains_key` + `insert`
(lines 1822–1824). Use the entry API to collapse to one:

```rust
use std::collections::hash_map::Entry;

if let Entry::Occupied(mut occupied) = cache.entry(message_id) {
    *occupied.get_mut() = cached_message;
    return;
}
```

The remainder of the function (eviction + insertion) is unchanged.

**Verify**: `cargo test` passes. The `application_message_round_trip_is_stable` test exercises
the cache path.

**Risk**: None. The entry API guarantees single-lookup semantics with identical observable
behavior.

### 7.5 Finding #28 — serialize_message_cache_ordered collect-then-join

**File**: `src/codec.rs`

The current implementation collects into a `Vec<String>` then joins:

```rust
.collect::<Vec<_>>()
.join(",")
```

Replace with a pre-sized single-buffer approach using `push_str`:

1. Allocate a `String` with `String::with_capacity(ordered.len() * 80)` (heuristic: 80 chars
   per entry covers typical message IDs and small ciphertexts).
2. Iterate: write `hex_id:ciphertext:hex_plaintext`, appending `,` as separator between entries
   (not after the last).

Alternatively, use `itertools::join` if the `itertools` crate is acceptable. Since the project
currently has no `itertools` dependency, the manual approach is preferable to avoid a new dep.

**Verify**: Round-trip test in `tests/api_integration.rs` confirms format stability.

**Risk**: Low. Same format output, fewer intermediate allocations.

---

## 8. Cargo.toml: release profile (Finding #29)

**Audit reference**: #29 — No `[profile.release]` settings, missing LTO and `codegen-units=1`.

### 8.1 What changes

**File**: `Cargo.toml`

Add:

```toml
[profile.release]
# Link-time optimization eliminates dead code across crate boundaries.
# "thin" LTO is a reasonable balance between compile time and binary size for a NIF.
lto = "thin"
# Single codegen unit maximizes inlining across the crate.
codegen-units = 1
# Strip debug symbols from release builds to reduce .so size.
strip = "debuginfo"
# NOTE: Do NOT set panic = "abort" — catch_unwind in deserialize_signer requires
# stack unwinding to function correctly. Setting panic = "abort" silently disables
# catch_unwind semantics and would allow TLS codec panics to crash the BEAM VM.
```

Do not add `opt-level = 3` explicitly; that is already the `release` default.

### 8.2 What to verify

```
cargo build --release
```

Produces `target/release/libmls_nif.so` (or `.dylib` on macOS). Binary size should be smaller or
equal. Confirm with `./run rust:test` that the test suite still passes in release mode:

```
cargo test --release
```

### 8.3 Dependencies

None. Cargo.toml changes are independent.

### 8.4 Risk

Low. `lto = "thin"` and `codegen-units = 1` increase compile time, not runtime risk. The explicit
`panic = "abort"` exclusion comment is critical safety documentation — a future contributor
must not add it without understanding the `catch_unwind` dependency.

---

## 9. Public API Documentation (Finding #21)

**Audit reference**: #21 — No public API docs, no `//!` crate-level docs, no `# Errors` sections.

### 9.1 What changes

**File**: `src/lib.rs` (crate root), `src/error.rs`, `src/ops.rs`

#### Crate-level `//!` doc in `lib.rs`

Write a module-level `//!` comment at the top of `lib.rs` covering:

- What this crate is (Rustler NIF binding for Famichat's MLS layer)
- The `Payload` contract: every NIF takes and returns `HashMap<String, String>`
- The two-actor model: sender + recipient co-located in one `GroupSession`
- The snapshot protocol: five string keys that encode session state for Elixir-side persistence
- The `DirtyCpu` scheduling policy and why it matters for BEAM schedulers
- A note that `#![forbid(unsafe_code)]` is intentional and why (NIF boundary safety)
- A reference to ADR 012 and the Elixir adapter at `Famichat.Crypto.MLS.NifBridge`

#### `# Errors` sections on all `pub` business-logic functions

For each of the 17 functions in `ops.rs`, add a `/// # Errors` section listing which `ErrorCode`
variants can be returned and under what condition. Example:

```rust
/// # Errors
///
/// Returns [`ErrorCode::InvalidInput`] if `group_id` is missing, empty, longer than 256 bytes,
/// or contains a NUL byte.
///
/// Returns [`ErrorCode::CryptoFailure`] if OpenMLS key material generation fails.
///
/// Returns [`ErrorCode::StorageInconsistent`] if a snapshot is provided but the group cannot
/// be loaded from it.
pub(crate) fn create_group(params: &Payload) -> MlsResult {
```

#### `ErrorCode` variant docs

Each `ErrorCode` variant should have a `///` comment explaining when the Elixir caller should
expect it and what recovery action (if any) is appropriate:

```rust
/// Crypto primitive failure in OpenMLS. The operation cannot be retried without
/// fresh key material. Elixir callers should treat this as a fatal session error.
CryptoFailure,
```

#### `#[forbid(unsafe_code)]` justification

Add a comment immediately below the attribute in `lib.rs`:

```rust
// This crate loads into the BEAM VM via a NIF. Any undefined behaviour in unsafe
// Rust can corrupt the VM heap or crash the scheduler. We rely entirely on
// openmls and rustler to handle unsafe FFI internally; this crate adds no unsafe
// blocks of its own.
#![forbid(unsafe_code)]
```

### 9.2 What to verify

After adding docs:

```
cargo doc --no-deps --document-private-items 2>&1 | grep warning
```

The `missing_docs` lint (enabled in Section 2) will report any undocumented `pub` items.
Resolve all lint warnings before closing this task.

### 9.3 Dependencies

- Module split (Section 1) so docs are added to their permanent files.
- Visibility narrowing (Section 4) so that `pub(crate)` items are not flagged by `missing_docs`
  for external consumers.

### 9.4 Risk

None. Documentation changes cannot affect runtime behavior.

---

## 10. Integration Test Directory (Finding #22)

**Audit reference**: #22 — No integration tests in `tests/` directory; all tests are inline
`#[cfg(test)]`.

### 10.1 What changes

Create `backend/infra/mls_nif/tests/api_integration.rs`.

Integration tests in `tests/` compile as a separate crate that accesses the library only through
its public API (`pub use` re-exports). This enforces the same boundary that Elixir callers see
and catches regressions in the `pub` surface that unit tests (with `use super::*`) miss.

#### Suggested test modules to include

1. **Snapshot round-trip** — `create_group` → capture snapshot keys → drop the in-memory session
   manually (note: there is no `GROUP_SESSIONS.remove` in the public API; use a unique group ID
   per test and rely on isolation) → call `create_application_message` with the snapshot to force
   restore → confirm the operation succeeds and `plaintext` is correct.

2. **Snapshot format stability** — serialize a known `SnapshotRawData` equivalent, deserialize it,
   and confirm the round-trip is lossless. This test guards against accidental changes to the
   `"hex(k):hex(v)"` storage format or `"hex(id):ciphertext:hex(plaintext)"` cache format.

3. **Cross-operation snapshot transfer** — `create_group` → `create_application_message` →
   capture snapshot → `process_incoming` (using snapshot as params) → confirm decryption works
   on a session restored from snapshot. This is the primary regression guard for the Elixir
   persistence model.

4. **Error code taxonomy** — for each `ErrorCode` variant, confirm at least one operation can
   return it with a predictable `details` payload shape. This locks down the Elixir boundary
   contract.

5. **mls_remove + merge_staged_commit sequence** — mirrors the existing inline test but runs
   through the public API surface only, confirming the snapshot is valid after each operation.

#### What stays in `#[cfg(test)]` in source files

Helper functions that are inherently unit-level (`unique_group_id`, `payload` constructor, codec
helpers) can remain in the inline `#[cfg(test)]` blocks. Only cross-cutting scenario tests move
to `tests/`.

### 10.2 What to verify

```
cargo test --test api_integration
```

All tests pass. The test file must not use `use mls_nif::session::*` or any `pub(crate)` symbol —
only `use mls_nif::{Payload, MlsError, ErrorCode, MlsResult}` and the NIF business-logic
functions exported via `pub use`.

Note: because the `pub` business-logic functions are currently `pub(crate)` after Section 4, the
integration test crate will not be able to call them directly. There are two resolution options:

- **Option A**: Export the 17 business-logic functions as `pub` at crate root (not recommended —
  breaks the intent of Section 4).
- **Option B**: Write the integration tests against the `*_nif` shim functions, which is not
  possible without a live BEAM environment.
- **Option C** (recommended): Keep the integration tests calling the `pub(crate)` functions via
  a thin `pub` facade module that the tests/ crate can access, gated behind `#[cfg(test)]` or a
  `test-helpers` feature flag.

A simpler pragmatic approach: move the existing inline tests from `#[cfg(test)] mod tests` into
`tests/api_integration.rs` and keep the business-logic functions as `pub` (not `pub(crate)`)
for the duration of Phase 3. The `pub(crate)` narrowing from Section 4 can be applied to only the
truly internal helpers (`lifecycle_ok`, `with_required_group`, `determine_remove_target`,
`map_create_message_error`) while leaving the 17 top-level NIF functions as `pub` since they are
already part of the documented public contract.

### 10.3 Dependencies

- Module split (Section 1).
- Dead code removal (Section 3) so that `serialize_message_cache` does not appear in the
  integration test if it has been moved to `#[cfg(test)]` only.

### 10.4 Risk

Low. Creating `tests/` is additive. The only risk is that existing tests are duplicated between
inline and integration locations, causing maintenance burden. Resolve by moving (not copying)
tests during this step.

---

## 11. Low-Severity API Polish (Findings #32–#35)

These four findings are independent polish items and can be landed in any order after the module
split.

### 11.1 Finding #32 — payload_from_nif is a no-op

**File**: `src/lib.rs`

`fn payload_from_nif(params: HashMap<String, String>) -> Payload` is the identity function
because `Payload = HashMap<String, String>`. Its only purpose is a call-site label.

Options:
- Delete the function and inline `params` directly in the NIF shims:
  `encode_result(env, ops::create_group(&params))`
- Or replace with a type-annotated let: `let params: Payload = params;`

Recommendation: delete the function. The NIF shims already have the type annotation through
the `encode_result` call chain. Removing the indirection makes the shim pattern clearer.

**Verify**: `cargo build`. All 17 NIF shim functions compile correctly.

**Risk**: None. It is a no-op function.

### 11.2 Finding #33 — lifecycle_ok FnOnce instead of Fn

**File**: `src/ops.rs`

`fn lifecycle_ok<F: Fn(&mut Payload)>` takes a closure that is called exactly once. Change to
`FnOnce`:

```rust
fn lifecycle_ok<F: FnOnce(&mut Payload)>(operation: &str, params: &Payload, decorate: F) -> MlsResult
```

This is a more precise bound that does not restrict current callers (all use closures that could
be either `Fn` or `FnOnce`) and allows future callers to move values into the closure.

**Verify**: `cargo build`. All three call sites (`mls_commit`, `mls_update`, `mls_add`) compile
without change.

**Risk**: None. `FnOnce` is less restrictive for callers than `Fn`.

### 11.3 Finding #34 — validate_openmls_runtime return type

**File**: `src/params.rs`

`fn validate_openmls_runtime() -> Result<(), String>` is inconsistent with the rest of the crate
which uses `Result<_, MlsError>`.

Change to `Result<(), MlsError>`:

```rust
fn validate_openmls_runtime() -> Result<(), MlsError> {
    let provider = OpenMlsRustCrypto::default();
    let signer = SignatureKeyPair::new(DEFAULT_CIPHERSUITE.signature_algorithm())
        .map_err(|_| MlsError::with_code(ErrorCode::CryptoFailure, "health", "openmls_signer_init_failed"))?;
    signer
        .store(provider.storage())
        .map_err(|_| MlsError::with_code(ErrorCode::CryptoFailure, "health", "openmls_signer_store_failed"))
}
```

Update `nif_health` in `ops.rs` which currently pattern-matches on the `Result<(), String>`:

```rust
match validate_openmls_runtime() {
    Ok(()) => { ... }
    Err(e) => {
        payload.insert("status".to_owned(), "degraded".to_owned());
        payload.insert("reason".to_owned(), e.details.get("reason").cloned().unwrap_or_default());
    }
}
```

Or restructure `nif_health` to propagate the error through `MlsResult` directly:

```rust
pub(crate) fn nif_health() -> MlsResult {
    validate_openmls_runtime()?;
    let mut payload = Payload::with_capacity(2);
    payload.insert("status".to_owned(), "ok".to_owned());
    payload.insert("reason".to_owned(), "openmls_ready".to_owned());
    Ok(payload)
}
```

This is cleaner: `nif_health` returns an error payload automatically through `encode_result` if
the runtime check fails.

**Verify**: `cargo test` — specifically `health_reports_openmls_ready` must pass.

**Risk**: Low. The test for this function checks `status = "ok"` which is preserved. The
"degraded" path is not tested currently; consider adding a test.

### 11.4 Finding #35 — catch_unwind soundness comment

**File**: `src/codec.rs`

The `AssertUnwindSafe` wrapper in `deserialize_signer` (line 1667) currently has a comment
explaining the unwind safety (H3 note). That comment should be expanded to explicitly justify
why `AssertUnwindSafe` is sound here:

```rust
// SOUNDNESS: bytes and bytes_slice are owned/stack-allocated values created in this
// call frame. No shared mutable state is accessed inside the closure. If the TLS
// codec panics (e.g. length-prefix underflow), the only effect is an early return
// from this function; no global state is left in an inconsistent state.
// AssertUnwindSafe is sound because there is nothing to observe as "partially mutated"
// if the unwind fires.
let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
```

**Verify**: `cargo doc` renders the comment correctly. No compile change.

**Risk**: None. Comment only.

---

## 12. Execution Order and Dependency Graph

Execute tasks in the following waves. Tasks within a wave are independent and can be worked on in
parallel.

```
Wave 1 (prerequisite — no dependencies):
  [1]  Module split
  [8]  Cargo.toml release profile

Wave 2 (depends on [1]):
  [2]  Clippy lint configuration
  [3]  Dead code removal
  [4]  Visibility narrowing

Wave 3 (depends on [1], benefits from [2]):
  [5]  Payload::with_capacity
  [6]  serialize_snapshot_raw_data hot-path
  [7]  Low-severity ownership fixes (all five)
  [9]  Public API documentation
  [11] API polish (all four)

Wave 4 (depends on [1], [3], [4]):
  [10] Integration test directory
```

Total task count: 11 numbered items, 12 sub-items in Section 7, 4 sub-items in Section 11.
Estimated PR count: 4–5 PRs corresponding to the four waves, with Wave 3 possibly split into
two PRs (allocation fixes vs. documentation).

---

## 13. Risk Register

| Task | Risk level | What could go wrong | Mitigation |
|------|-----------|---------------------|------------|
| Module split | Low | Missing `use` import in new file | Compiler reports every missing import precisely |
| Clippy lints | Low | `correctness`-level lint fires on existing code | Treat as a bug; fix before merging |
| Dead code removal | Low | Test references deleted function | `cargo test` catches it immediately |
| Visibility narrowing | Low | Downstream rlib consumer breaks | No known downstream rlib consumer |
| with_capacity | Very low | Over-allocated HashMap wastes memory | Bounded: 12 extra slots max per call |
| Hot-path allocation | Medium | Snapshot format accidentally changes | Round-trip regression test required |
| Ownership fixes #24–28 | None | Pure refactor | `cargo test` confirms equivalence |
| Release profile | Low | `panic = "abort"` accidentally added | Documentation comment in Cargo.toml |
| API docs | None | Cannot affect runtime | N/A |
| Integration tests | Low | `pub(crate)` visibility blocks tests/ | Use public facade or keep functions `pub` |
| API polish | None | Comment and type-bound changes | `cargo build` confirms |

The only medium-risk task is the hot-path allocation change in Section 6 because it touches the
serialized snapshot wire format. A round-trip integration test is a hard requirement before
merging that task.
