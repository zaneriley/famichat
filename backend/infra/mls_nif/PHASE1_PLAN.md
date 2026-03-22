# MLS NIF Phase 1 — Correctness and Safety Fixes

**Scope**: Stop-the-bleeding fixes only. Critical and High findings from AUDIT.md that
affect runtime behavior: data races, silent error discard, lock inconsistency, panics
in production paths.

**Out of scope**: API redesign (#8), file splitting (#9), clone reduction (#7),
capacity hints (#13), Clippy configuration (#10). Those are Phase 2+.

---

## Dependency Graph

The eight findings split into three independent tracks plus one sequential chain.
Nothing in Track A blocks Track B or Track C. Fix #5 is a prerequisite for Fix #4
within Track B.

```
Track A (concurrency)
  #1 TOCTOU  ──────────────────────────────── independent
  #2 Crypto under lock ──────────────────────── independent (but related to #1)
  #3 Triple nested locks ──────────────────────── independent

Track B (error quality)          must be sequential:
  #5 MlsError Display/Error ──► #4 map_err discard

Track C (poison handling)        must be sequential:
  #6 Inconsistent poison base ──► #13 eprintln silent recovery  (same fix, same PR)
  #11 bare .unwrap() in restore ──── (lands together with #6/#13)
```

Parallelization recommendation:
- **Agent 1**: Track A — findings #1, #2, #3 (all concurrency, same code region)
- **Agent 2**: Track B — finding #5 first, then #4 immediately after
- **Agent 3**: Track C — findings #6, #13, #11 together (all in `restore_group_session_from_snapshot`)

---

## Finding #1 — TOCTOU Race on DashMap

### What changes

Seven `contains_key → insert` patterns must be replaced with DashMap's atomic
`entry()` API. The race: between `contains_key` returning false and the subsequent
`insert`, a concurrent BEAM dirty-CPU scheduler can insert for the same key,
causing the second insert to silently overwrite a live, in-use session.

Affected sites (function → lines):

| Function | Lines | Pattern |
|---|---|---|
| `join_from_welcome` | 256–264 | `contains_key` → `insert` (two-step restore) |
| `join_from_welcome` | 261–263 | second `contains_key` → `insert` (create path) |
| `mls_remove` | 509–515 | `contains_key` → `insert` |
| `merge_staged_commit` | 691–697 | `contains_key` → `insert` |
| `create_application_message` | 839–845 | `contains_key` → `insert` |
| `export_group_info` | 891–897 | `contains_key` → `insert` |
| `list_member_credentials` | 943–949 | `contains_key` → `insert` |

The fix at each site: collapse the check-then-insert into a single
`GROUP_SESSIONS.entry(group_id.clone()).or_insert_with(|| ...)` call, or use
`GROUP_SESSIONS.entry(...).or_try_insert_with(|| ...)` when the insert closure
returns a `Result`. For the restore-or-create pattern the logic is:

```
entry(group_id).or_try_insert_with(|| {
    restore_group_session_from_snapshot(...)
        .and_then(|opt| opt.map(Ok).unwrap_or_else(|| create_group_session(...)))
})
```

Note: `create_group` at line 213 uses a plain `insert` without a prior
`contains_key`, so it is not a TOCTOU site — it is an intentional overwrite
(restore-or-create path produces the session before inserting).

### How to verify

1. `cargo build` must succeed with no new warnings.
2. Run existing `#[cfg(test)]` suite: `./run cmd cargo test` — all tests must pass.
3. New targeted test: `join_from_welcome_concurrent_no_overwrite` — spawn two
   threads that call `join_from_welcome` with the same `group_id` simultaneously
   and assert that both succeed and the final entry is valid (not a default-initialized
   empty session). This test should fail on the old code and pass after the fix.

### Dependencies

None. Independent of all other findings.

### Risk

**Low to moderate.** The entry API returns a `RefMut`, which is the same type as
`get_mut`. Callers that already hold a `get_mut` guard for the same shard will
deadlock — but no call site does that; every site does `insert` and then separately
`get_mut`. The `or_try_insert_with` variant was stabilized in dashmap 5.x and is
present in dashmap 6 (the version in Cargo.toml).

Elixir NIF interface is unaffected: no changes to function signatures, return
types, or atom sets.

---

## Finding #2 — Crypto Operations Under Shard Write Lock

### What changes

`process_message`, `remove_members`, and `create_message` are currently called while
a `GROUP_SESSIONS.get_mut()` guard is held. That guard holds a DashMap shard write
lock for the entire duration of the multi-millisecond crypto operation, blocking all
other threads that need any key in the same shard.

Affected functions and their crypto operations held under lock:

| Function | Lines | Operation held under lock |
|---|---|---|
| `process_incoming` | 356–459 | `group.process_message(...)` (AEAD decryption) |
| `mls_remove` | 517–629 | `group.remove_members(...)` + `merge_pending_commit` + second `process_message` |
| `merge_staged_commit` | 699–811 | `group.process_message(...)` + `merge_staged_commit` |
| `create_application_message` | 847–884 | `group.create_message(...)` (AEAD encryption) |

The fix: wrap `GroupSession` in `Arc<Mutex<GroupSession>>` inside DashMap, changing
the map type from `DashMap<String, GroupSession>` to
`DashMap<String, Arc<Mutex<GroupSession>>>`.

The new access pattern per call site:

1. `let arc = GROUP_SESSIONS.get(&group_id)` — acquires DashMap shard read lock,
   clones the `Arc` (cheap pointer copy), drops shard lock immediately.
2. `let mut session = arc.lock()` — acquires per-session `Mutex` lock.
3. Perform crypto work under the `Mutex` only.
4. Drop the `Mutex` guard after snapshot extraction (which can remain inside the
   `Mutex` since `extract_snapshot_raw_data` is already fast — byte clones only).

This means the DashMap shard lock is held only for the time needed to clone an
`Arc`, not for multi-millisecond crypto work.

The TOCTOU fix (#1) and this fix (#2) are complementary: after both are applied,
the entry API holds the shard lock only for the `Arc` clone, and crypto runs under
the per-session `Mutex`.

Implications for `extract_snapshot_raw_data` (#3): the triple-nested lock issue
dissolves because the DashMap shard lock is no longer held during snapshot
extraction — see #3 below.

### How to verify

1. `cargo build` must succeed.
2. Existing test suite must pass unchanged.
3. New concurrency stress test: 8 threads each calling `create_application_message`
   on different group IDs in the same DashMap shard and asserting no scheduler
   starvation (wall-clock time for all 8 to complete should be ≤ max single-call
   time × 2, not max × 8).
4. `cargo test --release` with `RUST_TEST_THREADS=8` to exercise scheduler
   interaction.

### Dependencies

**Coordinate with #1**: if both fixes land in the same PR, the entry API change (#1)
and the Arc-wrapping (#2) should be designed together to avoid double-refactoring
the same sites.

**Prerequisite for #3**: once `GroupSession` is behind `Arc<Mutex>` and the shard
lock is dropped before crypto, the triple-nested lock in
`extract_snapshot_raw_data` no longer exists structurally.

### Risk

**Highest risk of the Phase 1 set.** This changes the fundamental ownership model
of `GROUP_SESSIONS`. Specific risks:

- `GroupSession` does not implement `Send` unless `MlsGroup`, `OpenMlsRustCrypto`,
  and `SignatureKeyPair` are `Send`. Verify with `cargo build`; the compiler will
  reject a non-`Send` type inside `Arc<Mutex<>>` used across thread boundaries.
- `Mutex` lock contention per session: two concurrent calls for the same group will
  now serialize at the `Mutex` rather than at the shard. This is the correct
  behavior (session state is not reentrant) but is a semantic change. Tests that
  rely on one call observing another's in-progress state would break — no such
  tests exist today.
- Elixir NIF interface: unchanged. No atom, arity, or return-type changes.

---

## Finding #3 — Triple Nested Locks in `extract_snapshot_raw_data`

### What changes

`extract_snapshot_raw_data` (lines 1324–1398) is called while the DashMap
`get_mut` guard is held, which itself holds a shard write lock. Inside, it calls
`.read()` on `sender_provider.storage().values` (an `RwLock`) and again on
`recipient_provider.storage().values`. This creates a lock ordering:

```
DashMap shard write lock
  └─ sender RwLock (storage values)
       └─ recipient RwLock (storage values)
```

If any other code path acquires these locks in a different order, a deadlock is
possible. Additionally, holding the shard write lock while waiting for RwLock
acquisition means any other thread wanting any session in the same shard is
blocked.

**If Fix #2 is applied first**, this issue dissolves: `extract_snapshot_raw_data`
will be called under the per-session `Mutex` only, with no DashMap shard lock held.
The inner `RwLock` reads become `Mutex → RwLock(sender) → RwLock(recipient)` which
is a flat two-level structure on a per-session basis.

**If Fix #2 is not applied in the same batch**: the standalone fix is to document
the lock ordering invariant with a comment block above `extract_snapshot_raw_data`
stating: "Callers must not hold any other lock protecting resources belonging to
this `GroupSession`. Lock order: DashMap shard → sender RwLock → recipient RwLock.
Acquiring these in any other order is a deadlock."

Additionally, audit all call sites of `extract_snapshot_raw_data` (7 sites) to
confirm they all acquire the DashMap shard lock first and the storage RwLocks
second (they do — the shard lock is held via `get_mut` or `get`, and the RwLocks
are acquired inside `extract_snapshot_raw_data` only).

### How to verify

1. If Fix #2 applied: `cargo build` + test suite. The structural issue is gone.
2. If documented-only fix: add a `cargo test` that calls
   `extract_snapshot_raw_data` from a context where no DashMap lock is held
   (as will be the case post-#2), confirming it still functions correctly.
3. `RUSTFLAGS="-Z sanitize=thread" cargo test` (nightly) to detect lock-order
   inversion at runtime.

### Dependencies

**Downstream of #2.** If #2 lands first, #3 requires only a documentation
comment. If #2 is deferred, #3 needs the standalone lock-ordering comment and
call-site audit.

### Risk

**Low** if #2 is applied. The current code has no known deadlock because all 7
call sites acquire the locks in the same order (shard first, then storage RwLocks).
The risk is latent: a future call site that acquires storage RwLocks before a shard
lock (e.g. a background eviction task) would deadlock silently. Documenting the
invariant now prevents that.

Elixir NIF interface: unchanged.

---

## Finding #4 — 30+ `map_err(|_| ...)` Discard Underlying Errors

### What changes

Every `map_err(|_| ...)` closure in the file (30+ sites) discards the original
error completely. The caller receives only a string like `"group_load_failed"` with
no context about what OpenMLS, TLS codec, or storage actually returned. This makes
production debugging impossible.

The minimum fix: change `map_err(|_| ...)` to `map_err(|e| ...)` and include
`format!("{e:?}")` in the `details` payload.

Representative sites:

| Lines | Operation | Current discard |
|---|---|---|
| 400–402 | `MlsMessageIn::tls_deserialize` | `\|_\|` |
| 404–410 | `try_into_protocol_message` | `\|_\|` |
| 416–422 | `group.process_message` | `\|_\|` |
| 550–552 | `tls_serialize_detached` | `\|_\|` |
| 560–566 | `merge_pending_commit` | `\|_\|` |
| 574–579 | `MlsMessageIn::tls_deserialize` (recipient path) | `\|_\|` |
| 1140–1146 | `MlsGroup::new_with_group_id` | `\|_\|` |
| 1163–1169 | `KeyPackage::builder().build` | `\|_\|` |
| 1177–1179 | `sender_group.add_members` | `\|_\|` |
| 1182–1189 | `merge_pending_commit` | `\|_\|` |
| 1199–1205 | `MlsMessageIn::tls_deserialize` (welcome) | `\|_\|` |
| 1223–1233 | `StagedWelcome::new_from_welcome` + `.into_group` | `\|_\|` |
| 1257–1263 | `SignatureKeyPair::new` | `\|_\|` |
| 1265–1271 | `signer.store` | `\|_\|` |
| 1529–1535 | `MlsGroup::load` (sender) | `\|_\|` |
| 1571–1577 | `MlsGroup::load` (recipient) | `\|_\|` |

The correct fix per site is:
```
.map_err(|e| {
    let mut details = Payload::new();
    details.insert("operation".to_owned(), operation.to_owned());
    details.insert("reason".to_owned(), format!("{e:?}"));
    MlsError { code: ErrorCode::CryptoFailure, details }
})
```

For sites that already have a typed `map_err` with an `error` parameter (e.g.,
`mls_remove` line 539–547 and `merge_staged_commit` lines 760–766, 776–782),
the pattern is already correct — those sites are not affected.

Note: using `{e:?}` (Debug) rather than `{e}` (Display) is intentional because
`MlsError` does not yet implement `Display` (#5). After #5 is applied, callers
can switch to `{e}` for cleaner output where the library type implements `Display`.

### How to verify

1. `cargo build` must succeed.
2. Add a test that intentionally passes malformed ciphertext to
   `process_incoming` and asserts that `error.details["reason"]` contains a
   non-empty string (not the previous behavior of containing only the static
   reason string). This confirms the error context is flowing through.
3. `cargo clippy` must not flag these sites (the `|_|` pattern in `map_err`
   is not a Clippy error by default, but with `warn(clippy::map_err_ignore)`
   it would be — consider adding that lint in Phase 2).

### Dependencies

**Prerequisite: Fix #5 (MlsError Display/Error impl).** The reason: without a
`Display` impl on `MlsError`, adding `{e:?}` to details where `e` is itself an
`MlsError` will produce Rust struct Debug output (verbose, ugly, but functional).
Once `#5` adds proper `Display`, the 4–5 sites where the error type is already
`MlsError` (re-mapped from an inner operation) will produce clean messages.
More importantly, #5 may change the type of `e` at some sites if `thiserror`
derives are added to intermediate types — fixing #4 before #5 risks touching the
same `map_err` closures twice.

Recommended order: **#5 first, then #4**.

### Risk

**Low**. This is additive: the `details` map gains a new `"reason"` field with
richer content. Existing Elixir code that pattern-matches on `details` keys will
not break because it either checks for the `"reason"` key (which gets a better
value) or ignores unknown keys.

The one behavioral change: some errors that currently return a two-key details map
(`"operation"` + static `"reason"`) will now return a three-key map with a
longer `"reason"` value. Any Elixir tests that do exact equality on the `details`
map will need updating.

---

## Finding #5 — `MlsError` Missing Display/Error/thiserror

### What changes

`MlsError` (lines 51–55) is `#[derive(Debug, Clone, PartialEq, Eq)]` only. It has
no `std::fmt::Display` impl and does not implement `std::error::Error`. This means:

- `format!("{e}")` fails to compile wherever `e: MlsError`
- `MlsError` cannot be used as a source in `#[source]` chains
- The error cannot be passed to third-party logging or tracing infrastructure
- `?` propagation from a function returning `Result<_, MlsError>` into one
  returning `Result<_, Box<dyn Error>>` does not work

The fix:

1. Add `thiserror` to `[dependencies]` in `Cargo.toml`:
   `thiserror = "1"`
2. Add `#[derive(thiserror::Error)]` to `MlsError`.
3. Add `#[error("{code}: {details:?}")]` or a custom `Display` impl that formats
   the code as its string representation and the details map as key=value pairs.
   A custom impl is preferable for readability:
   ```rust
   impl std::fmt::Display for MlsError {
       fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
           write!(f, "{}", self.code.as_str())?;
           for (k, v) in &self.details {
               write!(f, " {k}={v}")?;
           }
           Ok(())
       }
   }
   ```
4. Implement `std::error::Error` for `MlsError` (no methods required; `thiserror`
   does this automatically if `#[derive(thiserror::Error)]` is used).

`ErrorCode` should also get a `Display` impl — currently it only has `as_str()`.
This is listed as audit finding #36 (Low) but is directly required to support a
clean `MlsError::Display` and is a trivial two-line addition:
```rust
impl std::fmt::Display for ErrorCode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}
```

### How to verify

1. `cargo build` — compilation confirms the impls are correct.
2. Add a test: `let msg = format!("{}", MlsError::with_code(ErrorCode::InvalidInput, "test", "reason"))` and assert it contains `"invalid_input"` and `"reason"`. This is a compile-time guarantee that `Display` is present.
3. Add a test: `let _: &dyn std::error::Error = &MlsError::with_code(...)` — confirms `std::error::Error` is implemented (compile-time check).

### Dependencies

None. This is a pure additive change. It is the **prerequisite for Fix #4**.

### Risk

**Very low.** Adding `Display` and `Error` impls to a type is additive. No existing
code breaks. The only risk is if a `thiserror` version is specified that conflicts
with a transitive dependency — check `cargo tree` after adding it.

Elixir NIF interface: unchanged. `MlsError` is not exposed directly to Elixir;
only `encode_result` converts it to atoms and a details map.

---

## Finding #6 — Inconsistent Poison Handling (Base)

### What changes

There are two inconsistent behaviors when an `RwLock` or `Mutex` is poisoned:

**Read path** (`extract_snapshot_raw_data`, lines 1332–1348): returns
`Err(MlsError::with_code(ErrorCode::LockPoisoned, ...))`. Correct.

**Write path** (`restore_group_session_from_snapshot`, lines 1507–1516 and
1546–1558): calls `unwrap_or_else(|e| { eprintln!(...); e.into_inner() })`.
This silently recovers from a poisoned lock by using the lock's inner value, which
may be in a partially-written, inconsistent state. A panicked thread caused the
poison; the inner value was left in whatever state the panic interrupted.

The fix for both write-path sites:
```rust
let mut values = sender_provider
    .storage()
    .values
    .write()
    .map_err(|_| MlsError::with_code(ErrorCode::LockPoisoned, operation, "lock_poisoned"))?;
*values = sender_storage;
```

Same pattern for the recipient write at lines 1546–1558.

The `eprintln!` calls at lines 1512–1513 and 1552–1554 are removed. They are both
unstructured and silent from the Elixir caller's perspective — the error was
swallowed. After the fix, the Elixir caller receives `{:error, :lock_poisoned, details}`
and can decide how to handle it (e.g., restart the group session, alert).

### How to verify

1. `cargo build` must succeed.
2. Add a test that poisons a write lock (by `std::panic::catch_unwind` with a
   closure that acquires the write lock and panics) and then calls
   `restore_group_session_from_snapshot`. Assert that it returns
   `Err(MlsError { code: ErrorCode::LockPoisoned, ... })` rather than silently
   succeeding.
3. `grep -n "unwrap_or_else.*eprintln\|eprintln.*unwrap_or_else" src/lib.rs` must
   return no results after the fix.

### Dependencies

**Coordinate with #11 (bare .unwrap())**: both are in `restore_group_session_from_snapshot`.
Apply both in the same commit to avoid leaving the function in a half-fixed state.
**Coordinate with #13**: this is the write-path side of the same inconsistency.
#6 and #13 are effectively the same fix applied to the same function — treat as one
unit of work.

### Risk

**Low, but a behavioral change visible to Elixir.** Previously a poisoned write
lock produced a warning log and continued. After the fix, it returns an error to
the Elixir caller. Any Elixir integration test that verifies a restore succeeds
even after a panic will now see a `lock_poisoned` error. This is the correct
behavior — the fix surfaces a real fault that was previously hidden.

The `LockPoisoned` error code already exists in the atom set and is already handled
in `encode_result` (line 1940). No Elixir module changes are required, but
`Famichat.Crypto.MLS` should be audited to ensure it handles `{:error, :lock_poisoned, _}`
rather than crashing.

---

## Finding #11 — 4 Bare `.unwrap()` in Production Path

### What changes

Lines 1497–1501 in `restore_group_session_from_snapshot` contain four `.unwrap()`
calls:

```rust
let sender_storage = deserialize_storage_map(sender_storage.as_deref().unwrap(), operation)?;
let recipient_storage = deserialize_storage_map(recipient_storage.as_deref().unwrap(), operation)?;
let sender_signer = deserialize_signer(sender_signer.as_deref().unwrap(), operation)?;
let recipient_signer = deserialize_signer(recipient_signer.as_deref().unwrap(), operation)?;
```

Each `.unwrap()` panics if the `Option` is `None`. The function reaches these
lines only after a completeness check at lines 1485–1494 that verifies all four
are `Some`. However, the completeness check and the unwraps are separated by code
that could in principle be refactored to skip the check — a latent panic hazard.

The fix: replace each `.unwrap()` with `.ok_or_else(|| MlsError::with_code(...))`:

```rust
let sender_storage_str = sender_storage.ok_or_else(|| {
    MlsError::with_code(ErrorCode::StorageInconsistent, operation, "missing_sender_storage")
})?;
let sender_storage = deserialize_storage_map(sender_storage_str.as_str(), operation)?;
```

And similar for the other three. This eliminates the `as_deref()` dance entirely
since the variables are already `Option<String>` and can be consumed directly.

Note: The completeness guard at lines 1485–1494 can remain as an early-exit
optimization — it returns a clear `"incomplete_session_snapshot"` error before
reaching the individual deserializations. The unwrap replacements are a defense-in-depth
measure.

### How to verify

1. `cargo build` must succeed.
2. `grep -n "\.unwrap()" src/lib.rs` should return zero results in production code
   paths after the fix. (Test code may still use `expect()`.)
3. The existing test `create_group_requires_group_id_and_ciphersuite` exercises
   the validation path. A new test should directly call
   `restore_group_session_from_snapshot` with a partially-complete snapshot
   (missing one of the four fields) and assert `Err(...)` is returned, not a panic.

### Dependencies

**Apply together with #6 and #13**: all three are in or directly adjacent to
`restore_group_session_from_snapshot`. One focused PR covering this entire function
is safer than three separate PRs that each leave the function in a transitional state.

### Risk

**Low.** The completeness check above already prevents the `None` case from reaching
the `.unwrap()` calls in normal operation. This fix only improves the case where
that invariant is accidentally violated by future refactoring.

Elixir NIF interface: unchanged. The error codes used (`StorageInconsistent`) are
already in the atom set.

---

## Finding #13 — Inconsistent Lock Poison: Silent Recovery

### What changes

This is the write-path counterpart of Finding #6. The two `eprintln!` + recovery
blocks at lines 1507–1516 and 1546–1558 are the same problem from the same
function. They are described together here for completeness.

As stated in Finding #6, the fix is to replace both `unwrap_or_else(|e| { eprintln!(...); e.into_inner() })` blocks with `.map_err(|_| MlsError::with_code(ErrorCode::LockPoisoned, ...))`.

The `eprintln!` calls produce output to stderr of the BEAM OS process, which:
- Is not captured by the Logger infrastructure
- Does not produce a structured log event
- Is not observable by Elixir telemetry
- Has no severity routing

After the fix, the error is returned up the call stack and reaches `encode_result`,
which encodes it as `{:error, :lock_poisoned, %{"operation" => ..., "reason" => "lock_poisoned"}}`.
The Elixir layer can then log it through `Logger` with proper severity.

### How to verify

Same as Finding #6 — these are the same code region and the same verification applies.

1. `grep -n "eprintln!" src/lib.rs` must return zero results after the fix.
2. `cargo build` + full test suite.

### Dependencies

Same as #6 and #11 — apply all three together in `restore_group_session_from_snapshot`.

### Risk

Same as #6. Behavioral change visible to Elixir: poison errors now propagate instead
of being swallowed.

---

## Execution Order and Parallelization

### Recommended PR structure (3 parallel PRs)

**PR-A: Concurrency (findings #1, #2, #3)**
- Owner: Agent 1
- #1 (TOCTOU) and #2 (crypto under lock) share the same 7 code sites — implement
  together using the Arc<Mutex> wrapper from #2 and the entry API from #1.
- #3 (triple locks) is resolved structurally once #2 is applied; add the lock-ordering
  comment regardless.
- Verification gate: `cargo build` + `cargo test` + new concurrency stress test.
- Merge prerequisite: none.

**PR-B: Error quality (findings #5, then #4)**
- Owner: Agent 2
- Apply #5 (Display/Error) first, confirm `cargo build`, then apply #4 (map_err discard).
- #4 has 30+ sites — mechanical but careful. The sites with existing `|e|` capture
  (lines 539–547, 760–766, 776–782) are already correct and must not be regressed.
- Verification gate: `cargo build` + `cargo test` + new map_err detail test.
- Merge prerequisite: #5 must be committed before #4 starts.

**PR-C: Poison handling (findings #6, #13, #11)**
- Owner: Agent 3
- All three findings are in `restore_group_session_from_snapshot` (lines 1497–1558).
  Apply as a single atomic change to the function.
- Verification gate: `cargo build` + `cargo test` + new poison propagation test.
- Merge prerequisite: none.

### Sequential constraint within PR-B

```
commit: add thiserror dep + Display/Error for MlsError (#5)
  └─ cargo build ✓
      └─ commit: replace |_| with |e| + format!("{e:?}") at all 30+ sites (#4)
```

Do not squash these two commits — keeping them separate makes the diff reviewable
and the bisect story clean.

### Integration order

PRs A, B, and C can be reviewed and merged in any order. There are no cross-PR
dependencies. If all three merge cleanly, run the full `mix test` suite (which
invokes `cargo build` via Rustler) to confirm the Elixir NIF bridge still loads.

---

## Risk Summary Table

| Finding | NIF interface change? | Elixir behavioral change? | Can break existing tests? |
|---|---|---|---|
| #1 TOCTOU | No | No | No |
| #2 Crypto lock | No | No | No (type must be Send) |
| #3 Triple locks | No | No | No |
| #4 map_err | No | Details map has richer reason | Yes — exact equality tests on `details` |
| #5 Display/Error | No | No | No |
| #6 Poison base | No | lock_poisoned returned instead of silent recovery | Yes — tests expecting success after poison |
| #11 bare unwrap | No | StorageInconsistent on impossible None | No (guard prevents None in practice) |
| #13 eprintln silent | No | Same as #6 | Same as #6 |

---

## Files Affected

All changes are in `backend/infra/mls_nif/src/lib.rs` and `backend/infra/mls_nif/Cargo.toml`.

`Cargo.toml` changes: add `thiserror = "1"` to `[dependencies]` for finding #5.

No Elixir files require changes in Phase 1. The Elixir adapter at
`backend/lib/famichat/chat/crypto/mls.ex` should be audited for `lock_poisoned`
handling as a follow-up to finding #6/#13, but that is not a Phase 1 blocker.
