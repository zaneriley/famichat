# MLS NIF Rust Audit — 5-Domain Conflict Report

**Date**: 2026-03-21
**Scope**: `backend/infra/mls_nif/src/lib.rs` (1947 lines) + `Cargo.toml`
**Method**: 5 parallel agents analyzing against 179 rust-skills rules + 9 Apollo rust-best-practices chapters

## Critical (fix before next feature work)

| # | Domain | Finding | Rule |
|---|--------|---------|------|
| 1 | **Concurrency** | TOCTOU race: `contains_key` → `insert` on DashMap has no atomicity — concurrent BEAM schedulers can silently overwrite live sessions | `perf-entry-api` |
| 2 | **Concurrency** | Crypto operations (`process_message`, `remove_members`, `create_message`) run under DashMap shard write lock — multi-ms hold time starves other threads | `async-spawn-blocking` |
| 3 | **Concurrency** | Triple nested lock: DashMap shard → sender RwLock → recipient RwLock in `extract_snapshot_raw_data` | `own-rwlock-readers` |
| 4 | **Error** | 30+ `map_err(\|_\| ...)` calls discard the underlying openmls error entirely — zero debug context | `err-source-chain` |
| 5 | **Error** | `MlsError` has no `Display` or `std::error::Error` impl, no `thiserror` | `err-thiserror-lib` |
| 6 | **Error** | Inconsistent poison handling: `extract_snapshot_raw_data` returns `LockPoisoned` error, but `restore_group_session_from_snapshot` silently recovers via `unwrap_or_else` + `eprintln!` | `err-no-unwrap-prod` |

## High (significant code quality / correctness impact)

| # | Domain | Finding | Rule |
|---|--------|---------|------|
| 7 | **Ownership** | `non_empty` / `required_non_empty` always clone — return `Option<String>` when `Option<&str>` suffices. Called 50+ times per NIF path | `anti-clone-excessive` |
| 8 | **API** | `Payload = HashMap<String, String>` as the entire API surface — stringly-typed input, output, AND error details | `anti-stringly-typed` |
| 9 | **Structure** | 1947-line single-file crate. Five separate domains crammed into one module | `proj-mod-by-feature` |
| 10 | **Structure** | No Clippy lint configuration at all — missing `deny(clippy::correctness)`, `warn(clippy::perf)`, etc. | `lint-deny-correctness` |
| 11 | **Structure** | 4 bare `.unwrap()` in production code path (snapshot restore, lines 1497-1501) | `anti-unwrap-abuse` |

## Medium (maintainability / performance improvement)

| # | Domain | Finding | Rule |
|---|--------|---------|------|
| 12 | **Ownership** | `with_required_group` closure takes `String` by value → forces 8+ `.clone()` sites | `anti-clone-excessive` |
| 13 | **Ownership** | All `Payload::new()` (27 sites) missing `with_capacity` despite known insert counts | `mem-with-capacity` |
| 14 | **Ownership** | `serialize_snapshot_raw_data` uses `format!` in per-entry loops → 3x allocations per storage entry | `anti-format-hot-path` |
| 15 | **API** | Group-ID validation block copy-pasted 4x — should be a `GroupId` newtype | `api-parse-dont-validate` |
| 16 | **API** | Ciphersuite is a `String` parsed at runtime — should be enum/newtype | `anti-stringly-typed` |
| 17 | **API** | Snapshot protocol is 5 string-keyed Payload fields — should be a typed `SessionSnapshot` struct | `api-parse-dont-validate` |
| 18 | **API** | Internal functions are `pub` — should be `pub(crate)` (this is a cdylib+rlib) | `proj-pub-crate-internal` |
| 19 | **Error** | Error reason strings mix `SCREAMING_SNAKE_CASE` and `snake_case` | `err-lowercase-msg` |
| 20 | **Structure** | `serialize_message_cache` (unordered variant) is dead code — superseded by `_ordered` variant | dead_code |
| 21 | **Structure** | No public API docs, no `//!` crate-level docs, no `# Errors` sections | `doc-all-public` |
| 22 | **Structure** | No integration tests in `tests/` directory — all tests in inline `#[cfg(test)]` | `test-integration-dir` |
| 23 | **Concurrency** | DashMap default shard count vs BEAM dirty-NIF scheduler contract — potential scheduler starvation | NIF safety |

## Low (cleanup / polish)

| # | Domain | Finding | Rule |
|---|--------|---------|------|
| 24 | **Ownership** | `has_complete_session_snapshot` clones 4 strings just for `.is_some()` presence checks | `anti-clone-excessive` |
| 25 | **Ownership** | `parse_bool` clones string before pattern matching on `&str` | `anti-clone-excessive` |
| 26 | **Ownership** | `deserialize_signer` clones `operation` for `catch_unwind` unnecessarily | `anti-clone-excessive` |
| 27 | **Ownership** | `cache_decrypted_message` double HashMap lookup (contains_key + insert) | `perf-entry-api` |
| 28 | **Ownership** | `serialize_message_cache_ordered` collect-then-join intermediate Vec | `anti-collect-intermediate` |
| 29 | **API** | `ErrorCode` missing `#[non_exhaustive]` | `api-non-exhaustive` |
| 30 | **API** | No `#[must_use]` on `MlsResult`-returning functions | `api-must-use` |
| 31 | **API** | `GroupSession`, `MemberSession`, `SnapshotRawData` missing `Debug` derives | `api-common-traits` |
| 32 | **API** | `payload_from_nif` is a no-op (collects HashMap into itself via type alias) | `anti-over-abstraction` |
| 33 | **API** | `lifecycle_ok` uses `Fn` bound instead of `FnOnce` | `type-generic-bounds` |
| 34 | **Error** | `validate_openmls_runtime` returns `Result<(), String>` instead of `MlsError` | `err-custom-type` |
| 35 | **Error** | `catch_unwind` discards panic payload without logging | `err-result-over-panic` |
| 36 | **Error** | `ErrorCode` missing `Display` impl (only has `as_str`) | `api-common-traits` |
| 37 | **Structure** | No `[profile.release]` in Cargo.toml — missing LTO, codegen-units=1 | `perf-release-profile` |
| 38 | **Structure** | `#![forbid(unsafe_code)]` correct but lacks crate-level `//!` doc explaining why | `lint-unsafe-doc` |
| 39 | **Structure** | `AssertUnwindSafe` lacks soundness justification comment | `lint-unsafe-doc` |
| 40 | **Concurrency** | `AtomicU64` `Relaxed` ordering undocumented (correct but needs comment) | documentation |
| 41 | **Concurrency** | `LazyLock` sessions lost silently on NIF hot-reload (needs Elixir-side doc) | documentation |

---

## Detailed Findings by Domain

### 1. Ownership & Memory (Agent 1)

**Finding 1 (high): `non_empty` always allocates**
- Location: lib.rs:1048-1053
- `non_empty` returns `Option<String>` via `.cloned()`. Called 50+ times per NIF path, including hot paths like `process_incoming`. Most callers only need `&str` — they pattern-match or call `.as_deref()` and discard the owned String immediately.
- Fix: Return `Option<&str>` via `params.get(key).filter(|v| !v.trim().is_empty()).map(String::as_str)`.

**Finding 2 (high): `required_non_empty` same problem**
- Location: lib.rs:1034-1046
- Returns `Option<String>` via `.to_owned()`. The returned String is often `.clone()`d again immediately (e.g., line 148).
- Fix: Return `Option<&str>`, let callers `.to_owned()` when they need ownership.

**Finding 3 (medium): `with_required_group` closure forces clones**
- Location: lib.rs:999-1032
- Closure bound `F: Fn(String)` moves `group_id` by value. At least 8 call sites clone `group_id` before the closure consumes it.
- Fix: Change to `F: Fn(&str)`.

**Finding 4 (medium): `create_group` — 3 clones of `parsed.group_id`**
- Location: lib.rs:213-221
- `GROUP_SESSIONS.insert` (clone), `payload.insert("group_id")` (clone), `format!("state:{}")` (implicit).
- Fix: Reorder to borrow first, move last.

**Finding 5 (medium): `process_incoming` — clone before move**
- Location: lib.rs:437-453
- `cache_plaintext = plaintext.clone()` then `plaintext` moved into payload. Only one copy needed.
- Fix: Insert cache entry first, then clone for payload (or vice versa).

**Finding 6 (medium): 27 `Payload::new()` sites missing `with_capacity`**
- Location: lib.rs:108,117,125,142,147,185,215,284,294,307... (27 sites)
- Most insert a known number of entries. `MlsError::with_code` always inserts exactly 2.
- Fix: `Payload::with_capacity(N)` at each site.

**Finding 7 (medium): `serialize_snapshot_raw_data` intermediate allocations**
- Location: lib.rs:1407-1426
- Per storage entry: `encode_hex(k)` alloc + `encode_hex(v)` alloc + `format!` alloc = 3x.
- Fix: Write directly into a pre-sized `String` buffer.

**Finding 8 (medium): Deep clone of `HashMap<Vec<u8>, Vec<u8>>` in snapshot extract**
- Location: lib.rs:1332-1348
- Full deep clone of both storage maps under lock. Comment says "cheap" but it's O(total bytes).
- Fix: Consider `Arc<RwLock<HashMap>>` for pointer-copy instead of deep clone.

**Finding 9 (low): `has_complete_session_snapshot` — 4 clones for presence check**
- Location: lib.rs:1055-1060
- Calls `non_empty` 4x and immediately discards with `.is_some()`.
- Fix: Add `has_non_empty(params, key) -> bool` that doesn't clone.

**Finding 10 (low): `parse_bool` clones then matches on `&str`**
- Location: lib.rs:1062-1068
- Fix: Match directly on `params.get(key).map(String::as_str)`.

**Finding 11 (low): `cache_decrypted_message` double lookup**
- Location: lib.rs:1815-1836
- `contains_key` then `insert` — use entry API instead.

### 2. Error Handling (Agent 2)

**Finding 12 (high): 30+ `map_err(|_| ...)` discard underlying errors**
- Location: lib.rs:400-402, 404-410, 416-422, 550-552, 560-566, 574-579... (30+ sites)
- Every openmls, TLS codec, and storage API call discards the original error. When `MlsGroup::load()` fails, caller gets only `"group_load_failed"` — no detail about which key, what format, or what the library said.
- Fix: Use `|e| { ... details.insert("reason", format!("{e:?}")); ... }` at minimum. Better: add `#[source]` field with `thiserror`.

**Finding 13 (high): Inconsistent lock-poison handling**
- Location: lib.rs:1507-1516, 1546-1558 vs 1337-1348
- Read path returns `LockPoisoned` error. Write path silently recovers with `eprintln!` + `into_inner()`.
- Fix: Return `Err(MlsError::with_code(ErrorCode::LockPoisoned, ...))` consistently.

**Finding 14 (medium): `validate_openmls_runtime` returns `Result<(), String>`**
- Location: lib.rs:1084-1091
- Should return `Result<(), MlsError>` for consistency.

**Finding 15 (medium): `catch_unwind` discards panic payload**
- Location: lib.rs:1679
- `Err(_panic)` arm drops the payload without logging.
- Fix: Downcast and include in error details.

**Finding 16 (low): Error reason case inconsistency**
- `"INVALID_GROUP_ID"` (screaming) vs `"missing_group_state"` (snake_case) — 8 sites.
- Fix: Normalize to `snake_case`.

### 3. API Design & Type Safety (Agent 3)

**Finding 17 (high): `Payload` as entire API contract**
- Location: lib.rs:16
- Every function takes `&Payload` and returns `Result<Payload, MlsError>`. Zero compile-time checking of required fields.
- Fix: Typed request/response structs, parse at NIF boundary.

**Finding 18 (medium): Group-ID validation duplicated 4x**
- Location: lib.rs:169-182, 241-254, 330-343, 1011-1024
- Fix: `GroupId` newtype with validated constructor.

**Finding 19 (medium): Ciphersuite is a `String`**
- Location: lib.rs:62, 184-192, 1093-1106
- Parsed at runtime via `parse_ciphersuite`. Should be enum/newtype.

**Finding 20 (medium): Snapshot protocol is 5 string-keyed Payload fields**
- Location: lib.rs:86-91, 1404-1447, 1469-1495
- Fix: `SessionSnapshot` struct with named fields.

**Finding 21 (medium): Internal fns are `pub` not `pub(crate)`**
- Location: all 17 public API functions
- Fix: `pub(crate)` for internal functions, `pub` only for NIF shims.

**Finding 22 (medium): Typestate applicable to group session lifecycle**
- Location: lib.rs:65-94, session restore/create patterns
- Fix: At minimum extract `ensure_session_loaded()` helper.

### 4. Concurrency & Performance (Agent 4)

**Finding 23 (high): TOCTOU race on DashMap**
- Location: lib.rs:256-263, 345-354, 509-515, 691-697, 839-845, 891-897, 943-949
- 7 sites with `contains_key` → `insert` pattern.
- Fix: Use `entry()` or `get_or_insert_with()`.

**Finding 24 (high): Crypto under shard write lock**
- Location: lib.rs:356-459, 517-630, 699-811, 847-876
- `process_message`, `remove_members`, `create_message` all run while `get_mut` guard is held.
- Fix: Wrap `GroupSession` in `Arc<Mutex<>>` inside DashMap. Hold shard lock only for Arc clone.

**Finding 25 (high): Triple nested locks in snapshot extract**
- Location: lib.rs:1324-1398, called from 7 sites
- DashMap shard → sender RwLock → recipient RwLock.
- Fix: Document lock ordering invariant. Better: clone-session-out approach.

**Finding 26 (medium): `list_member_credentials` holds shard lock during format! loop**
- Location: lib.rs:951-974
- Fix: Apply two-phase extract-then-serialize pattern.

**Finding 27 (medium): DashMap default shards vs BEAM scheduler contract**
- Location: lib.rs:93-94
- Fix: Tag crypto NIFs as dirty, or use `DashMap::with_shard_amount(32)`.

**Finding 28 (medium): `encode_hex` always allocates, no buffer reuse**
- Location: lib.rs:1838-1848
- Fix: Accept `&mut String` output buffer, or use `hex` crate.

**Finding 29 (low): No `[profile.release]` settings**
- Fix: Add LTO, codegen-units=1. Note: `panic = "abort"` conflicts with `catch_unwind`.

### 5. Anti-Patterns & Structure (Agent 5)

**Finding 30 (high): Single-file god module**
- Location: lib.rs:1-1947
- 5 conceptual domains in one file.
- Fix: Split into `nif.rs`, `api.rs`, `session.rs`, `snapshot.rs`, `codec.rs`, `error.rs`.

**Finding 31 (high): Missing Clippy lint configuration**
- Location: Cargo.toml
- No `[lints]` section at all.
- Fix: Add `[lints.clippy]` with correctness=deny, suspicious/style/complexity/perf=warn.

**Finding 32 (medium): Dead code: `serialize_message_cache` + `deserialize_message_cache`**
- Location: lib.rs:1690-1705, 1728-1734
- Superseded by `_ordered` variants. Only used in tests.
- Fix: Move to `#[cfg(test)]` or delete.

**Finding 33 (medium): No public API documentation**
- Location: all `pub` items
- Fix: Enable `#![warn(missing_docs)]`, add `///` + `# Errors` sections.

**Finding 34 (medium): No integration tests**
- Location: no `tests/` directory
- Fix: Create `tests/api_integration.rs`.

**Finding 35 (low): 146 `.to_owned()` on string literals**
- Fix: Helper function or `HashMap::from([...])` construction.
