# Phase 1 Plan Critique -- Senior Rust Engineer Review

**Date**: 2026-03-21
**Reviewer role**: Critic of Track A and Track B designs
**Source material**: AUDIT.md, PHASE1_PLAN.md, lib.rs (2103 lines), Cargo.toml, mls.ex, rust-skills rules

---

## Answers to the 8 Questions

### Question 1: Is `Arc<Mutex<GroupSession>>` actually needed?

**No. It is over-engineered for this architecture.**

The plan's premise is that DashMap shard contention blocks "other threads" during
crypto. But consider the actual call pattern:

1. Every NIF call receives a `group_id` from Elixir.
2. MLS requires strict epoch ordering -- you cannot process message N+1 before
   message N commits. The Elixir layer (`ConversationSecurityLifecycle`,
   `MessageService`) serializes operations per conversation.
3. Two concurrent calls for the **same** group_id would violate MLS protocol
   invariants regardless of locking strategy.

So the real contention is: two calls for **different** groups that hash to the
same DashMap shard. The plan acknowledges this but then proposes `Arc<Mutex>`
per session -- which solves per-session contention that the protocol already
forbids.

What `Arc<Mutex>` actually buys: converting shard write locks to shard read locks
(since you only need `get()` + `Arc::clone()` instead of `get_mut()`). This is a
real benefit, but the plan does not frame it this way. It frames it as preventing
concurrent session access, which is a non-problem.

**The simpler fix**: The code already implements the two-phase extract pattern
(lines 457-461, 628-632, 797-801, 872-876) where `extract_snapshot_raw_data`
runs under `get_mut` but `serialize_snapshot_raw_data` runs after `drop(entry)`.
The shard lock is held for:
- Byte clones of storage maps (~O(n) bytes, sub-ms for typical sessions)
- The actual crypto operation (AEAD encrypt/decrypt, 1-4ms)

The crypto time is the dominant cost. `Arc<Mutex>` moves that cost off the shard
lock -- but onto a per-session Mutex that, as established, will never actually see
contention because the Elixir layer serializes per-group calls.

**Verdict**: `Arc<Mutex>` adds complexity (new ownership model, changed
insert/restore semantics, `Send` bound requirements on `MlsGroup` + friends) for
a performance gain that matters only when two different groups hash to the same
shard AND their crypto operations overlap. With DashMap's default shard count
(num_cpus * 4), this is a low-probability event on a family messaging app.

**Recommendation**: Defer to Phase 2. If shard contention is measurable (profile
first -- `anti-premature-optimize`), increase shard count with
`DashMap::with_shard_amount(64)` as a zero-risk one-liner instead.

---

### Question 2: What happens to snapshot restore under `Arc<Mutex>`?

The plan does not address this adequately.

`restore_group_session_from_snapshot` (line 1464) constructs a **new**
`GroupSession` and calls `GROUP_SESSIONS.insert(group_id.clone(), restored)`.
Today this replaces the DashMap value directly. With `Arc<Mutex<GroupSession>>`,
you have two options:

**Option A: Replace the Arc in the DashMap.**
```rust
GROUP_SESSIONS.insert(group_id.clone(), Arc::new(Mutex::new(restored)));
```
This is what the plan implies. But anyone who previously called
`GROUP_SESSIONS.get(&group_id)` and cloned the Arc now holds a stale Arc pointing
to the old session. The old session continues to exist (kept alive by the Arc
refcount) and mutations to it are invisible to the new session. This is a
**silent data divergence bug** -- worse than the TOCTOU race it claims to fix.

**Option B: Lock the Mutex, swap internals.**
```rust
let entry = GROUP_SESSIONS.get(&group_id).unwrap();
let mut session = entry.lock().unwrap();
*session = restored;
```
This is correct but requires the caller to already know the key exists. For the
restore-then-insert pattern (lines 256-264, 345-354), the key may not exist yet.

**Option C: Use `entry()` API with Arc.**
```rust
GROUP_SESSIONS.entry(group_id)
    .and_modify(|arc| { *arc.lock().unwrap() = restored; })
    .or_insert_with(|| Arc::new(Mutex::new(restored)));
```
This is correct but means the restore closure runs inside the shard lock (same
problem the plan claims to solve for crypto -- see Question 3).

**The plan is silent on which option to use.** Any Track A implementer who
follows the plan as written will likely pick Option A and introduce a new bug.

---

### Question 3: Is the `entry()` API fix for TOCTOU actually correct?

**Partially correct, but the plan's code sample is dangerous.**

The plan proposes (page 1, Finding #1):
```
entry(group_id).or_try_insert_with(|| {
    restore_group_session_from_snapshot(...)
        .and_then(|opt| opt.map(Ok).unwrap_or_else(|| create_group_session(...)))
})
```

Problems:

1. **`or_try_insert_with` does not exist in dashmap 6.1.0.** DashMap 6.1.0
   provides `entry().or_insert_with()` (infallible) and `entry().or_default()`.
   The fallible variant `or_try_insert_with` was added in dashmap 6.1.0 via
   the `Entry::or_try_insert_with` method -- but actually checking the dashmap
   6.1.0 docs, this method returns `Result<RefMut, E>`. The plan's Track A
   agent needs to verify this compiles against the pinned version. If it doesn't
   exist, the only option is `or_insert_with` wrapping the result in a
   `Result`-laundering pattern, which is ugly.

2. **Restore runs inside the shard lock.** `restore_group_session_from_snapshot`
   does:
   - 4x `non_empty` lookups (cheap)
   - 2x `deserialize_storage_map` (hex decode, allocations)
   - 2x `deserialize_signer` (hex decode + TLS deserialize + `catch_unwind`)
   - 2x `OpenMlsRustCrypto::default()` (provider creation)
   - 2x RwLock write (storage population)
   - 2x `signer.store()` (storage write)
   - 2x `MlsGroup::load()` (deserialization from storage)

   This is easily 5-15ms of work. Running it inside `or_insert_with` holds the
   DashMap shard lock for the entire duration -- which is **exactly the "crypto
   under lock" problem** that Finding #2 identifies. The plan moves the problem
   from `get_mut` to `entry`, not eliminates it.

3. **The conditional restore logic does not fit `entry()`.** The current code at
   line 256 is:
   ```rust
   if has_complete_session_snapshot(params) || !GROUP_SESSIONS.contains_key(&group_id) {
       if let Some(restored) = restore_group_session_from_snapshot(...)? {
           GROUP_SESSIONS.insert(group_id.clone(), restored);
       } else if !GROUP_SESSIONS.contains_key(&group_id) {
           let session = create_group_session(...)?;
           GROUP_SESSIONS.insert(group_id.clone(), session);
       }
   }
   ```
   The first branch (`has_complete_session_snapshot`) forces a restore even if
   the key already exists (snapshot-driven overwrite). This is not an
   "insert if absent" pattern -- it is a "conditionally replace" pattern.
   `entry().or_insert_with()` only runs the closure when the key is absent.
   You cannot express "overwrite if snapshot is present" with `entry()`.

**The correct TOCTOU fix for this code is simpler**: the race window between
`contains_key` and `insert` at lines 260-263 is harmless in practice because:
- Both racing threads would create identical sessions (same group_id,
  same ciphersuite, same snapshot data)
- The second `insert` overwrites the first, but the first was never used
  (no `get_mut` was issued between `insert` and `insert`)
- MLS state is deterministic given the same inputs

The real risk is a race between "restore from snapshot + insert" and a concurrent
"get_mut for crypto operation" on a session that was just inserted. But this is
the per-group serialization problem -- which Elixir already handles.

**Recommendation**: For Phase 1, document the TOCTOU window with a comment
explaining why it is benign (both paths produce equivalent sessions). If you
must fix it mechanically, use a simple `if let dashmap::Entry::Vacant(e) = GROUP_SESSIONS.entry(group_id) { e.insert(session); }` for the create-only paths.
The snapshot-overwrite paths (line 256) should remain as `insert` because
they intentionally replace.

---

### Question 4: Does adding `thiserror` buy anything real?

**No. It is ceremony.**

Let me trace the error's entire lifecycle:

1. Rust: `MlsError` is created with `MlsError::with_code(code, operation, reason)`
2. Rust: `encode_result` at line 1923 converts it to `(atoms::error(), error_atom(error.code), error.details).encode(env)`
3. Elixir: receives `{:error, :crypto_failure, %{"operation" => "...", "reason" => "..."}}`
4. Elixir: `normalize_error` in mls.ex maps it to `{:error, code, redacted_details}`

Nobody in Rust ever calls `format!("{}", mls_error)`. Nobody chains `MlsError`
as a `#[source]`. There is no Rust caller that uses `?` to propagate `MlsError`
into `Box<dyn Error>`. The entire error path is:
`map_err(|_| MlsError{...})` -> `encode_result` -> Elixir atom + map.

Adding `thiserror` gives you:
- A `Display` impl that nobody calls
- An `Error` impl that nobody uses for source chaining
- A new dependency in `Cargo.toml`

The plan says #5 is a "prerequisite for #4" because "without Display,
`{e:?}` produces ugly output." But `{e:?}` is `Debug`, not `Display`, and
`MlsError` already derives `Debug`. The prerequisite relationship is false.

**What actually matters for Finding #4**: changing `|_|` to `|e|` and adding
`format!("{e:?}")` to the details map. This requires zero type changes to
`MlsError`. You just change the closure parameter name and add a details entry.

**Recommendation**: Skip #5 entirely. Do #4 directly. If you want Display for
logging later, add a manual 5-line `impl Display for MlsError` without a new
dependency. Save `thiserror` for Phase 2 when the error types are restructured.

---

### Question 5: Will enriched `map_err` leak openmls internals?

**Yes, and it does not matter -- but the plan should say so explicitly.**

After Fix #4, the `"reason"` field will contain strings like:
```
"RemoveMembersError(CreateCommitError(ProposalValidationError(Mismatch)))"
```

The Elixir adapter at `mls.ex` line 230 pattern-matches **only on the error code
atom** (`:invalid_input`, `:crypto_failure`, etc.), not on the details map values:
```elixir
defp normalize_error(_operation, code, details) when code in @error_codes do
  {:error, code, redact_sensitive_details(details)}
end
```

The `redact_sensitive_details` function (line 252) strips keys like `:ciphertext`,
`:plaintext`, `:key_material` but does NOT strip `:reason` or `"reason"`. So the
openmls Debug output will flow through to Elixir callers.

This is fine for debugging. But the plan should note:
1. The `"reason"` field is not a stable API -- consumers must not pattern-match
   on its value (only on the error code atom).
2. If openmls upgrades change Debug output, existing log-based alerts that grep
   for specific error strings will break. This is acceptable.
3. Consider adding `"reason"` to `@sensitive_error_key_strings` if the openmls
   debug output ever contains key material (it shouldn't, but audit).

---

### Question 6: Can the 4 bare `.unwrap()` calls be eliminated structurally?

**Yes. This is the right question. The plan proposes the wrong fix.**

The plan proposes replacing `.unwrap()` with `.ok_or_else(|| MlsError::...)?`.
This is defense-in-depth, but it leaves the code structure that necessitated the
unwraps intact: binding variables as `Option<String>`, checking them for `None`,
then unwrapping them 5 lines later.

The **subtractive** fix is to destructure in the guard:

```rust
// Current (lines 1469-1501):
let sender_storage = non_empty(params, SNAPSHOT_SENDER_STORAGE_KEY);
let recipient_storage = non_empty(params, SNAPSHOT_RECIPIENT_STORAGE_KEY);
let sender_signer = non_empty(params, SNAPSHOT_SENDER_SIGNER_KEY);
let recipient_signer = non_empty(params, SNAPSHOT_RECIPIENT_SIGNER_KEY);
// ... 25 lines of checks ...
let sender_storage = deserialize_storage_map(sender_storage.as_deref().unwrap(), operation)?;

// Subtractive fix:
let (sender_storage_str, recipient_storage_str, sender_signer_str, recipient_signer_str) =
    match (
        non_empty(params, SNAPSHOT_SENDER_STORAGE_KEY),
        non_empty(params, SNAPSHOT_RECIPIENT_STORAGE_KEY),
        non_empty(params, SNAPSHOT_SENDER_SIGNER_KEY),
        non_empty(params, SNAPSHOT_RECIPIENT_SIGNER_KEY),
    ) {
        (Some(ss), Some(rs), Some(ssg), Some(rsg)) => (ss, rs, ssg, rsg),
        (None, None, None, None) if cache.is_empty() => return Ok(None),
        _ => return Err(MlsError::with_code(
            ErrorCode::InvalidInput, operation, "incomplete_session_snapshot"
        )),
    };

let sender_storage = deserialize_storage_map(&sender_storage_str, operation)?;
// No unwrap needed -- the match already proved these are Some.
```

This eliminates 4 unwraps, the separate presence check at lines 1475-1483, and
the incomplete check at lines 1485-1494. Three blocks of code become one match.
The unwraps don't just get replaced with `ok_or_else` -- they **cease to exist**.

**Recommendation**: Use the destructuring approach. It is shorter, eliminates
the temporal gap between check and use, and is more idiomatic Rust.

---

### Question 7: What is the simplest possible Phase 1?

**The #1 highest-impact fix is Finding #6/#13 -- the silent poison recovery.**

Here is why: the TOCTOU race (#1) requires two BEAM dirty-CPU schedulers to call
the same group_id simultaneously, which the Elixir layer prevents. The crypto
under lock (#2) causes latency spikes, not data corruption. The map_err discard
(#4) makes debugging harder but does not lose data.

But silent poison recovery (#6/#13) **actively hides data corruption**. If a
thread panics while writing storage (which `catch_unwind` at line 1667 proves
is a real possibility -- the TLS deserialize can panic), the next
`restore_group_session_from_snapshot` call will:
1. Acquire the poisoned write lock via `into_inner()`
2. Overwrite the partially-written state with new data
3. Return `Ok(Some(session))` as if nothing happened
4. The Elixir caller has no idea the previous operation failed

This means a panicked deserialization silently corrupts the provider storage
and the corruption is never reported. In an E2EE system, silent state corruption
is the worst possible failure mode -- it can lead to messages being encrypted to
a broken key tree.

**The fix is 6 changed lines** (two `unwrap_or_else` blocks become `map_err`
blocks) and affects only `restore_group_session_from_snapshot`. It can be shipped
in under 30 minutes.

The 4 bare unwraps (#11) should land in the same commit since they are in the
same function and the destructuring fix (Question 6) touches adjacent lines.

**Minimum viable Phase 1**: Fix #6 + #13 + #11 (all in
`restore_group_session_from_snapshot`). Ship it. Everything else can wait.

---

### Question 8: What should be deferred to Phase 2?

| Finding | Phase 1? | Reason |
|---------|----------|--------|
| #1 TOCTOU | **Defer** | Benign race (both sides produce equivalent sessions); Elixir serializes per-group |
| #2 Crypto under lock | **Defer** | Performance issue, not correctness; profile before optimizing |
| #3 Triple nested locks | **Defer** | No deadlock today (consistent ordering); dissolves if #2 is done later |
| #4 map_err discard | **Phase 1** | Low-risk, high-value for debugging; 30+ mechanical changes but zero semantic risk |
| #5 thiserror | **Defer** | Ceremony; no Rust consumer uses Display/Error |
| #6 Poison recovery | **Phase 1** | Silent data corruption in E2EE system -- unacceptable |
| #11 Bare unwraps | **Phase 1** | Same function as #6; use destructuring to eliminate |
| #13 eprintln silent | **Phase 1** | Same fix as #6 (they are the same two code blocks) |

**Minimal Phase 1 = 2 PRs:**
- **PR-1**: #6 + #13 + #11 (restore function hardening, ~30 lines changed)
- **PR-2**: #4 (map_err enrichment, ~60 lines changed, mechanical)

---

## Verdict Summary

### #1 Highest-Impact Fix
**Finding #6/#13: silent poison recovery in `restore_group_session_from_snapshot`.**
6 lines changed, eliminates silent data corruption in an E2EE system.

### #1 Most Over-Engineered Proposal
**Finding #2: `Arc<Mutex<GroupSession>>` wrapping.** Adds a new ownership model,
introduces Option A / Option B / Option C restore semantics that the plan does
not resolve, solves a contention problem that the protocol layer already prevents,
and violates `anti-premature-optimize` (no profiling data cited). The simpler
alternative is `DashMap::with_shard_amount(64)` (one line, zero semantic change).

### What Track A Will Get Wrong
1. `or_try_insert_with` may not compile against dashmap 6.1.0 -- verify the API
   exists before writing code.
2. The `entry()` closure running `restore_group_session_from_snapshot` under the
   shard lock is the same "crypto under lock" problem as Finding #2.
3. The snapshot-overwrite pattern (`has_complete_session_snapshot` branch) cannot
   be expressed with `entry().or_insert_with()` -- it is an intentional replace,
   not an insert-if-absent.
4. If `Arc<Mutex>` is used, `GROUP_SESSIONS.insert(...)` during restore creates
   a stale-Arc divergence bug (Question 2, Option A).

### What Track B Will Get Wrong
1. Making #5 a prerequisite for #4 is unnecessary -- `{e:?}` uses `Debug`, not
   `Display`, and `MlsError` already has `Debug`.
2. Adding `thiserror` as a dependency for a type that never crosses a Rust API
   boundary (it is immediately encoded to Erlang terms) is over-engineering.
3. The `format!("{e:?}")` in `map_err` closures will allocate on every error
   path. For the 30+ sites, this is fine (errors are rare), but the plan should
   note it is not free.

### What Track C Will Get Right
Track C (poison handling + unwraps) is the best-scoped part of the plan. The
only improvement: use destructuring instead of `ok_or_else` to eliminate the
unwraps structurally (Question 6).
